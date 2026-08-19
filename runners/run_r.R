# R reference runner — PCRE2 engine (perl=TRUE mode)
# stdin: JSON array of {id, pattern, testText, flags}
# stdout: JSON object of {id: {matches: [{match, index}], error}}
#
# Uses only base R (no jsonlite dependency) — manual JSON parsing/output.

input <- paste(readLines("stdin", warn = FALSE), collapse = "\n")

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
    prefix <- ""
    if (grepl("m", flags)) prefix <- paste0(prefix, "m")
    if (grepl("s", flags)) prefix <- paste0(prefix, "s")
    if (grepl("x", flags)) prefix <- paste0(prefix, "x")
    if (nchar(prefix) > 0) p <- paste0("(?", prefix, ")", p)

    # `suppressWarnings` prevents PCRE compile warnings (e.g.
    # "quantifier does not follow a repeatable item") from being
    # emitted on stdout, which would corrupt the JSON payload we
    # stream to the orchestrator. Warnings for bad patterns surface
    # as `m == -1` (no match) anyway; our ground truth records that
    # as an empty matches array, which matches what real R code gets.
    m <- suppressWarnings(
      gregexpr(p, e$testText, perl = TRUE, ignore.case = ignore_case)[[1]]
    )
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
      s <- gsub(cc, sprintf("\\\\u%04x", i - 1), s, fixed = TRUE)
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
