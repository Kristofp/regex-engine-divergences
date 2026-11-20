# R reference runner — BOTH of R's regex engines.
#
# R is not one regex language. `grepl(p, x)` runs TRE (POSIX ERE + a fair
# number of extensions); `grepl(p, x, perl = TRUE)` runs PCRE2. A single
# column cannot describe "R", so both are recorded.
#
# What TRE actually does, measured against r-base:4.4.0 and cross-checked
# against R's own `?regex` page from the SAME image:
#
#   supported  (?:...)  (?i:...)  \d \w \s \D \W \S  \b \B \< \>
#              backreferences \1-\9, POSIX [[:alpha:]], lazy quantifiers*
#   rejected   named groups, all four lookarounds, atomic groups,
#              possessive quantifiers  -> compile error
#   INERT      \A \Z \z \K \G \R \X, and every escape INSIDE a class
#              -> compiles clean, matches nothing or matches the letter
#
#   * `a+?` is identical to PCRE2, but lazy inside a counted repetition is
#     NOT: `(?:(?:\w+?)\s){2,3}` on "a bb ccc dddd eeeee" gives PCRE2
#     ["a bb ccc "] and TRE ["a bb ","ccc dddd "].
#
# The inert set is the trap. `?regex` states the rule that explains it —
# "Only `^ - \ ]` are special inside character classes" — so `[\d\s]+`
# under TRE matches a literal `d`, and `[^\W]+` matches the whole string.
# Not an error, just a wrong answer.
#
# Engine is chosen by the first CLI argument, defaulting to pcre2 so the
# existing `r.json` keeps its meaning:
#   Rscript run_r.R pcre2   -> ground-truth/r.json      (perl = TRUE)
#   Rscript run_r.R tre     -> ground-truth/r-tre.json  (base R default)
# stdin: JSON array of {id, pattern, testText, flags}
# stdout: JSON object of {id: {matches: [{match, index}], error}}
#
# Uses only base R (no jsonlite dependency) — manual JSON parsing/output.

input <- paste(readLines("stdin", warn = FALSE), collapse = "\n")

# `use_perl` drives ONLY the pattern under test. The runner's own JSON
# parsing below stays on PCRE2 unconditionally — it is our code, not the
# subject, and it must parse identically in both modes or the two columns
# would differ for reasons that have nothing to do with the patterns.
# (An earlier version of this comment claimed the parser needs `(?:...)`,
# which TRE supposedly lacked. TRE supports `(?:...)` — measured. The
# reason to pin it is determinism, not capability.)
args <- commandArgs(trailingOnly = TRUE)
engine <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "pcre2"
if (!engine %in% c("pcre2", "tre")) {
  stop(sprintf("unknown R engine '%s' (expected 'pcre2' or 'tre')", engine))
}
use_perl <- identical(engine, "pcre2")

# Sentinel returned by `json_unescape` when the body contains U+0000, which R
# cannot represent at all. A value no real subject can equal, so a caller can
# test for it with `identical` rather than inspecting the string.
NUL_SENTINEL <- "\u0001__regexpilot_nul_in_subject__\u0001"

# Decode a JSON string body — convert escape sequences (\n, \t, \r,
# \", \\, \/, \uXXXX) into actual characters. The previous
# implementation used `gsub("\\\\(.)", "\\1", ...)` which stripped
# the leading backslash but left the escape LETTER as a literal
# character — turning `\t` into a literal `t` (dropping the tab
# entirely from testText). That bug silently corrupted every R
# ground-truth entry whose testText contained whitespace escapes,
# which is why `\s+` / `\S+` / `\R` / `^anchor` etc. all diverged
# from the reference result. (fix 2026-04-23)
json_unescape <- function(s) {
  out <- character(0)
  chars <- strsplit(s, "", fixed = TRUE)[[1]]
  n <- length(chars)
  i <- 1L
  while (i <= n) {
    ch <- chars[i]
    if (ch == "\\" && i < n) {
      nxt <- chars[i + 1L]
      if (nxt == "u" && i + 5L <= n) {
        hex <- paste0(chars[(i + 2L):(i + 5L)], collapse = "")
        code <- suppressWarnings(strtoi(hex, base = 16L))
        if (!is.na(code)) {
          # R CANNOT HOLD A NUL, and `intToUtf8` does not say so -- it SILENTLY
          # DROPS the code point. Measured 2026-09-11: 8 code points in,
          # `nchar` 7 out, and a literal is rejected outright with "nul
          # character not allowed". So a subject containing U+0000 would be
          # matched here as a SHORTER string than the one the app sees, and the
          # snapshot would record a confident answer about different input.
          # That cost 42 fuzz rows, every one on the single witness string
          # carrying a NUL, and they read as engine divergences for weeks.
          #
          # A sentinel keeps the decoder pure (it returns a string); the caller
          # turns it into a recorded ERROR, so the comparison SKIPS the entry
          # rather than grading against a truncated subject. Refusing beats
          # silently answering about the wrong input -- the same rule the
          # `\50` -> `(` and sidecar-JSON incidents are both about.
          if (code == 0L) return(NUL_SENTINEL)
          out <- c(out, intToUtf8(code))
          i <- i + 6L
          next
        }
      }
      repl <- switch(nxt,
                     "n" = "\n",
                     "t" = "\t",
                     "r" = "\r",
                     "b" = "\b",
                     "f" = "\f",
                     "\"" = "\"",
                     "\\" = "\\",
                     "/" = "/",
                     paste0("\\", nxt))
      out <- c(out, repl)
      i <- i + 2L
    } else {
      out <- c(out, ch)
      i <- i + 1L
    }
  }
  paste0(out, collapse = "")
}

# Minimal JSON array-of-objects parser using base R
parse_entries <- function(json) {
  json <- trimws(json)
  json <- substr(json, 2, nchar(json) - 1)
  parts <- strsplit(json, "\\},\\s*\\{")[[1]]
  parts <- gsub("^\\{|\\}$", "", parts)

  lapply(parts, function(p) {
    extract <- function(field) {
      pat <- paste0('"', field, '"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"')
      m <- regmatches(p, regexec(pat, p, perl = TRUE))[[1]]
      if (length(m) >= 2) json_unescape(m[2]) else ""
    }
    list(id = extract("id"), pattern = extract("pattern"),
         testText = extract("testText"), flags = extract("flags"))
  })
}

entries <- parse_entries(input)
results <- list()

for (e in entries) {
  tryCatch({
    flags <- e$flags
    ignore_case <- grepl("i", flags)
    p <- e$pattern
    # Inline flag groups: TRE rejects `(?m)` / `(?s)` / `(?x)` outright
    # ("TRE pattern compilation error 'Invalid regexp'") and base R exposes no
    # argument for them, so prefixing in TRE mode would record a compile error
    # where a real R user gets a plain literal miss. Unprefixed is truthful.
    #
    # Note what this does NOT mean. Dotall is not missing from TRE, it is the
    # BASELINE — measured in r-base:4.4.0:
    #
    #   grepl("a.b", "a\nb")             TRUE    <- TRE: dot matches newline
    #   grepl("a.b", "a\nb", perl=TRUE)  FALSE   <- PCRE2 default
    #   grepl("(?n)a.b", "a\nb")         FALSE   <- (?n) turns dot-newline OFF
    #
    # Multiline genuinely has no switch: `^b` on "a\nb" is FALSE under TRE and
    # `(?n)` does not change that. `?regex` says TRE's `^`/`$` match "the
    # beginning and end of a line", but R compiles without REG_NEWLINE, so the
    # measured behaviour is string-only. Docs and engine disagree; engine wins.
    #
    # Consequence for the columns: entries carrying m/s/x are NOT comparable
    # between them. Three more agree only by coincidence (TRE being dotall
    # already, or the test text having no newline), so the non-comparable set
    # is 24 entries, not the 21 that merely carry a flag.
    # A subject or pattern R cannot represent has no ground truth. See
    # `NUL_SENTINEL`.
    #
    # CHECKED AGAINST `e$pattern`, NOT `p`, and BEFORE the flag prefix below.
    # This guard used to sit after that block and test `p`, which the prefixing
    # reassigns — so for a perl-mode entry carrying `m`, `s` or `x`,
    # `identical(p, NUL_SENTINEL)` could never be true and the sentinel ran as a
    # LITERAL pattern, recorded as a confident clean result for input R never
    # received. Exactly the class of silent-wrong-answer this sentinel exists to
    # prevent, reintroduced one line below it. Found by CodeRabbit, 2026-09-11.
    if (identical(e$testText, NUL_SENTINEL) || identical(e$pattern, NUL_SENTINEL)) {
      stop("subject or pattern contains U+0000, which R cannot represent")
    }

    if (use_perl) {
      prefix <- ""
      if (grepl("m", flags)) prefix <- paste0(prefix, "m")
      if (grepl("s", flags)) prefix <- paste0(prefix, "s")
      if (grepl("x", flags)) prefix <- paste0(prefix, "x")
      if (nchar(prefix) > 0) p <- paste0("(?", prefix, ")", p)
    }

    # Warnings are CAPTURED, not blanket-suppressed, and the distinction
    # matters. They still must not reach stdout -- that would corrupt the JSON
    # payload streamed to the orchestrator, which is why `suppressWarnings` was
    # here -- but they do not all mean the same thing:
    #
    #   a COMPILE warning ("quantifier does not follow a repeatable item")
    #     really does mean no match, and `m == -1` records it correctly;
    #   a LIMIT warning ("match limit exceeded") means R GAVE UP. Recording
    #     that as an empty matches array says "no match" about a question R
    #     never answered.
    #
    # The old comment here claimed warnings "surface as m == -1 (no match)
    # anyway; our ground truth records that as an empty matches array, which
    # matches what real R code gets". True of the first kind, FALSE of the
    # second -- and it cost 67 fuzz rows that read as the app refusing patterns
    # R accepted. Measured 2026-09-11: `gregexpr` on fuzz_73_3 with perl=TRUE
    # warns "PCRE error 'match limit exceeded'" and returns -1, exactly like a
    # clean miss, and 63 of the 67 were snapshotted as {matches: [], error:
    # null}. The app hits the SAME limit and reports it; only the recording
    # disagreed.
    #
    # Matched on "limit" because that is the word every give-up carries --
    # match limit, recursion limit, backtracking limit -- and a false positive
    # here costs one SKIPPED entry, while a false negative costs a confident
    # wrong answer.
    warnings_seen <- character(0)
    m <- withCallingHandlers(
      gregexpr(p, e$testText, perl = use_perl, ignore.case = ignore_case)[[1]],
      warning = function(w) {
        warnings_seen <<- c(warnings_seen, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    gave_up <- any(grepl("limit", warnings_seen, ignore.case = TRUE))
    if (gave_up) {
      stop(paste0("R gave up: ", paste(unique(warnings_seen), collapse = "; ")))
    }
    if (m[1] == -1) {
      results[[e$id]] <- list(matches = list(), error = NULL)
    } else {
      lens <- attr(m, "match.length")
      matches <- mapply(function(start, len) {
        list(match = substr(e$testText, start, start + len - 1),
             index = start - 1L)
      }, m, lens, SIMPLIFY = FALSE, USE.NAMES = FALSE)
      results[[e$id]] <- list(matches = matches, error = NULL)
    }
  }, error = function(err) {
    results[[e$id]] <<- list(matches = list(), error = conditionMessage(err))
  })
}

# Manual JSON output. Must escape every JSON-illegal code unit: `"`
# and `\` per spec, plus every control char U+0000..U+001F. Previous
# version only did `\n`/`\r`/`\t`, which left form feeds, vertical
# tabs, and NULs in the payload — any of those makes the orchestrator
# fail with "Bad control character in string literal". `\u00XX`
# escape catches the lot.
escape_json <- function(s) {
  s <- gsub("\\\\", "\\\\\\\\", s)
  s <- gsub('"', '\\\\"', s)
  s <- gsub("\n", "\\\\n", s)
  s <- gsub("\r", "\\\\r", s)
  s <- gsub("\t", "\\\\t", s)
  s <- gsub("\b", "\\\\b", s)
  s <- gsub("\f", "\\\\f", s)
  # Remaining controls U+0000..U+001F → \u00XX. R's gsub with perl=TRUE
  # + a backreference lets us compute the hex on the fly via callback
  # emulation: enumerate each codepoint individually.
  ctrl_chars <- sapply(0:31, intToUtf8)
  for (i in seq_along(ctrl_chars)) {
    cc <- ctrl_chars[i]
    if (nzchar(cc) && !(cc %in% c("\n", "\r", "\t", "\b", "\f"))) {
      # ONE backslash, not two. `fixed = TRUE` makes the replacement literal,
      # and R's "\\\\" is two backslashes — which emitted JSON `\\u001b`, i.e.
      # the six-character TEXT `\u001b` rather than the control character. Every
      # other runner recorded a real ESC for the same input; only R's ground
      # truth carried the literal, so an ANSI-escape pattern compared the app's
      # correct answer against a wrong reference.
      s <- gsub(cc, sprintf("\\u%04x", i - 1), s, fixed = TRUE)
    }
  }
  s
}

parts <- character(0)
for (id in names(results)) {
  r <- results[[id]]
  match_parts <- character(0)
  for (m in r$matches) {
    match_parts <- c(match_parts,
      sprintf('{"match":"%s","index":%d}', escape_json(m$match), m$index))
  }
  err <- if (is.null(r$error)) "null" else sprintf('"%s"', escape_json(r$error))
  parts <- c(parts,
    sprintf('"%s":{"matches":[%s],"error":%s}',
      escape_json(id), paste(match_parts, collapse = ","), err))
}
cat(paste0("{", paste(parts, collapse = ","), "}"))
