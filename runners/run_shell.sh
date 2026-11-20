#!/bin/sh
# Shell-tools reference runner — GNU grep / GNU sed / GNU awk ground truth.
#
# Provides byte-identical match output from real GNU tools so the corpus
# comparator can validate the Rust shell sidecar (regexpilot-shell-engine)
# against authentic GNU behavior.
#
# This produces the RETAINED reference columns `shell-gnu.json` and
# `shell-awk-gnu.json`. The authoritative shell column is BSD and comes from
# `run_shell_bsd.sh` (owner, 2026-09-10); this file records what the other
# dialect does, for a future "GNU tools" option.
#
# ## Runs in the `gnu-grep` and `gawk` engine images (task E6, 2026-11-20)
#
# GNU grep 3.12 (`-P` on PCRE2 10.49) and GNU Awk 5.4.2, built from the GNU
# release tarballs inside the image; `test/corpus/generate-ground-truth.ts`
# names the image per column. The history below is why it ran on the host
# from 2026-09-10 until then.
#
# ## Ran on the HOST from 2026-09-10, not in alpine — and why
#
# It ran in `alpine:3.19` until the owner asked for the NEWER gawk, and the
# newer gawk turned out not to exist in any distribution image. Measured, all on
# 2026-09-10, arm64:
#
#   alpine:3.19  gawk 5.3.0   alpine:3.22  gawk 5.3.2   fedora:43  gawk 5.3.2
#   alpine:3.20  gawk 5.3.0   alpine:edge  gawk 5.3.2   debian:trixie gawk 5.2.1
#   host (Homebrew)           gawk 5.4.1
#
# (archlinux:latest is amd64-only and does not run here at all.)
#
# The 5.3→5.4 boundary is not a point release. gawk 5.4.0 REPLACED its default
# regexp engine with Mike Haertel's MinRX (gawk NEWS, "Changes from 5.3.x to
# 5.4.0", item 1), and the two engines disagree. The case that surfaced it:
#
#   pattern (?:foo|bar)baz     5.3.0/5.3.2         5.4.1
#   over "barbaz"              MATCH               fatal: invalid regexp
#   over "?:foobaz"            MATCH               fatal: invalid regexp
#
# That second row is the whole story. 5.3.x never supported `(?:` — it read the
# `?` as a LITERAL, because no subpattern preceded it, and matched the branch
# `?:foo` or `bar`. So the old engine answered a question nobody asked, and the
# new one diagnoses it. Following the newer version means following the host.
#
# The script runs unchanged on the host too: tool resolution below accepts
# `ggrep`/`gsed` and the plain names when they self-identify as GNU, and the
# `apk add` block is kept, guarded on `apk` existing.
#
# ## Versions the columns were last generated with
#
#   GNU grep 3.12 (PCRE2 10.49), GNU Awk 5.4.2   (engine images, 2026-11-20)
#   GNU sed 4.10 (Debian trixie, gnu-sed:4.10)   (engine image, 2026-11-20:
#                                                 shell-sed-gnu.json and
#                                                 shell-sed-gnu-ere.json)
#   GNU grep 3.12, GNU sed 4.10, GNU Awk 5.4.1   (Homebrew, 2026-09-10)
#
# `test/corpusShellAwkExtraction.test.ts` fails if the local gawk drops below
# 5.4, because that is the engine boundary.
#
# Tool selection — read from each corpus entry's optional `shellTool` key:
#   "grep" (default) — GNU grep -o [-E] [-i]; covers BRE, ERE, word-boundary
#   "sed"            — GNU sed 's/pattern/M1&M2/g' [-E], I flag for 'i';
#                      match-extract by marker bytes (see the sed arm below)
#   "gawk"           — GNU awk '/pattern/ { print }' [-i]; match-extract via
#                      gawk --re-interval (enabled by default in gawk 4+)
# When `shellTool` is absent, the runner dispatches by pattern/flag heuristics:
#   flags contain 'E' → use grep -E (ERE)
#   flags do not contain 'E' → use plain grep (BRE)
#   Sed and gawk dispatch is only triggered by explicit `shellTool` field.
#
# Mode flags (applied to whichever tool is selected):
#   'E' → ERE mode  (-E for grep/sed, default for gawk)
#   'i' → case-insensitive (-i flag)
#   'g' → all matches (grep always emits all; sed with g flag; gawk matches all lines)
#   'm' → multiline anchors (^/$ match line boundaries in grep by default;
#          no direct sed/gawk equivalent — grep is line-oriented by nature)
#
# stdin:  JSON array of {id, pattern, testText, flags, shellTool?}
# stdout: JSON object of {id: {matches, error}}
#
# KNOWN GAPS (document for the Rust sidecar validation report):
#   1. \d, \w, \S etc. are GNU-grep extensions; in POSIX ERE (-E) mode, GNU grep
#      3.8+ warns "stray \ before X". The warning is captured as `error` in the
#      ground truth — this IS the correct behavior, matching what real GNU grep
#      does, and this ground-truth generator must keep recording it as `error`.
#      The Rust sidecar (sidecars/shell/src/main.rs) does NOT propagate that
#      warning: it never shells out to system grep at all (the macOS App
#      Sandbox forbids spawning `/usr/bin/grep` — see that file's own header),
#      it is TRE-based, and TRE compiles these same escapes as plain literals
#      with no error and no warning. So the sidecar cannot reproduce grep's
#      stderr line — the app achieves parity a different way, on the TypeScript
#      side: `src/core/flavor/shellEscapeWarnings.ts` reimplements grep's
#      "stray \ before X" detection and `validateRegex` (src/core/validation.ts)
#      surfaces it as a non-blocking warning before a pattern ever reaches this
#      sidecar. Corrected 2026-09-09 — this comment previously claimed the
#      sidecar propagated the warning, which was never true of the TRE
#      rewrite.
#   2. grep does not report byte offsets with -o.  All matches have index: -1.
#      The corpus comparator skips offset comparison for the shell flavor.
#   3. Zero-width assertions (lookahead, lookbehind) are NOT supported in GNU
#      grep BRE/ERE.  Patterns using (?=...) / (?<=...) will error.
#   4. The 'm' (multiline) flag is a no-op for grep — grep is inherently line-
#      oriented, so ^/$ always match line boundaries.  For sed and gawk, the
#      behaviour depends on record separator config (not applied here).
#   5. Sed and gawk sub-runners produce match-only output (not the result of
#      a substitution).  Replace semantics are validated by the Rust sidecar's
#      own unit tests (sidecars/shell/src/main.rs expand_shell_template tests;
#      GNU sed's replacement in sidecars/shell/src/gnu/sed.rs, measured with gsed).

set -eu

# Optional first argument: force ONE tool for every entry, ignoring each
# entry's own `shellTool`. `run_shell.sh sed` produces a whole-corpus sed
# column, `run_shell.sh gawk` a gawk one; with no argument the per-entry
# behaviour is exactly as before. Validated here rather than at the dispatch
# below so a typo fails immediately with the valid list, instead of producing
# a full column of `unknown shellTool` errors that looks like a measurement.
FORCE_TOOL="${1:-}"
# Two more arguments are GREP DIALECT columns, not tools: `grep-pcre` runs
# `ggrep -o -P` for every entry (the `shell-gnu-pcre` column, what the GNU
# variant's `P` flag answers) and `grep-ere` runs `ggrep -o -E` for every entry
# (`shell-gnu-ere`; the default `shell-gnu` column is BRE). Both are grep, so
# they are folded into `FORCE_TOOL=grep` plus a DIALECT after validation.
# `sed-ere` is the same for sed: `gsed -E` for every entry (`shell-sed-gnu-ere`;
# the default `shell-sed-gnu` column is BRE, where every back-reference row is
# an error, so only the ERE column measures GNU sed's back-reference matching).
DIALECT=""
case "$FORCE_TOOL" in
  grep-pcre) FORCE_TOOL=grep; DIALECT=pcre ;;
  grep-ere) FORCE_TOOL=grep; DIALECT=ere ;;
  sed-ere) FORCE_TOOL=sed; DIALECT=ere ;;
esac
case "$FORCE_TOOL" in
  "" | grep | sed | gawk) ;;
  *)
    echo "run_shell.sh: unknown tool '$FORCE_TOOL' (expected grep, sed, gawk, grep-pcre, grep-ere or sed-ere)" >&2
    exit 2
    ;;
esac
# A UTF-8 locale for EVERY column, set here rather than inherited. `-P` needs
# one to switch PCRE2 into UTF mode (otherwise it matches bytes), and the
# sidecar's `P` path runs with UTF on, so the reference must too; BRE, ERE, sed
# and gawk read `.` and bracket expressions per character only in a multibyte
# locale. Until task E6 the non-`-P` columns inherited the caller's locale,
# which a container does not have (it would run in C, byte mode). `C.UTF-8`,
# not `en_US.UTF-8`: the Debian images carry only C, C.utf8 and POSIX, and
# macOS has C.UTF-8 too.
LC_ALL=C.UTF-8
export LC_ALL

# ── Runtime dependency install (containers only) ──────────────────────────────
# Alpine ships busybox, not the GNU builds. Guarded on `apk` so the block is
# simply absent on the host rather than being a failing command; `apk add` is
# idempotent, so it is also a no-op in any image that pre-bundles them.
if command -v apk >/dev/null 2>&1; then
  for pkg in grep sed gawk jq; do
    apk add --no-cache "$pkg" >/dev/null 2>&1 || true
  done
fi

# ── Resolve the GNU tools, and REFUSE anything else ───────────────────────────
#
# The mirror image of `run_shell_bsd.sh`'s refusal, and it exists for the same
# reason pointed the other way: on macOS the bare names `grep` and `sed` are
# BSD's, so resolving by name alone would emit a BSD column under a GNU
# filename — indistinguishable from the real thing afterwards, and every
# comparison built on it wrong in a way nothing could detect.
#
# Preferred name first (`ggrep`/`gsed`, how Homebrew installs GNU grep and sed
# on macOS), then the plain name for a Linux container where the plain name IS
# the GNU build. Each candidate must SAY it is GNU; a tool that does not
# self-identify is skipped rather than trusted, so an unknown third
# implementation fails instead of passing by omission.
pick_gnu() { # $1 preferred name, $2 fallback name, $3 expected --version marker
  for cand in "$1" "$2"; do
    resolved=$(command -v "$cand" 2>/dev/null) || continue
    [ -n "$resolved" ] || continue
    if "$resolved" --version </dev/null 2>&1 | head -1 | grep -q "$3"; then
      printf '%s' "$resolved"
      return 0
    fi
  done
  return 1
}

if ! GREP=$(pick_gnu ggrep grep 'GNU grep'); then
  echo "run_shell.sh: no GNU grep found (looked for ggrep, then grep)." >&2
  echo "  On macOS: brew install grep. Refusing to emit a GNU column from BSD grep." >&2
  exit 3
fi
if ! SED=$(pick_gnu gsed sed 'GNU sed'); then
  echo "run_shell.sh: no GNU sed found (looked for gsed, then sed)." >&2
  echo "  On macOS: brew install gnu-sed." >&2
  exit 3
fi
# gawk is required only when an entry can reach the gawk branch: a forced
# `gawk` column, or no forced tool (each entry's own `shellTool` decides). A
# forced grep or sed column does not need it, which is what lets the grep
# columns run in the `gnu-grep` image (Debian, whose only awk is mawk).
AWK=""
case "$FORCE_TOOL" in
  "" | gawk)
    if ! AWK=$(pick_gnu gawk gawk 'GNU Awk'); then
      echo "run_shell.sh: no GNU awk found. On macOS: brew install gawk." >&2
      echo "  BWK awk is NOT a substitute — see run_shell_bsd.sh, which owns that column." >&2
      exit 3
    fi
    ;;
esac
if ! command -v jq >/dev/null 2>&1; then
  echo "run_shell.sh: jq is required" >&2
  exit 3
fi

# Announced, not recorded: the column's schema is {id: {matches, error}} and
# has no room for provenance. A regeneration that silently used a different
# gawk than the header claims is the failure this line exists to make visible.
if [ -n "$AWK" ]; then
  awk_banner=$("$AWK" --version </dev/null | head -1)
else
  awk_banner="gawk not needed"
fi
echo "run_shell.sh: $("$GREP" --version </dev/null | head -1) | $("$SED" --version </dev/null | head -1) | $awk_banner | LC_ALL=$LC_ALL" >&2

# ── I/O setup ─────────────────────────────────────────────────────────────────
#
# A private temp dir. The fixed `/tmp/input.json` these were was safe while
# this script owned a container to itself and is not on a shared machine, where
# a second regeneration — or anything else that likes that name — would read
# and write the same files.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rp-shell-gnu.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

INPUT_FILE="$WORK/input.json"
RESULTS_FILE="$WORK/results.jsonl"
ENTRIES_FILE="$WORK/entries.jsonl"
ERR_FILE="$WORK/err"
cat > "$INPUT_FILE"
: > "$RESULTS_FILE"
jq -c '.[]' "$INPUT_FILE" > "$ENTRIES_FILE"

# ── Per-entry dispatch ─────────────────────────────────────────────────────────

while IFS= read -r entry; do
  id=$(printf '%s' "$entry" | jq -r '.id')
  pattern=$(printf '%s' "$entry" | jq -r '.pattern')
  test_text=$(printf '%s' "$entry" | jq -r '.testText')
  flags=$(printf '%s' "$entry" | jq -r '.flags // ""')
  # `$1` FORCES a tool for every entry, overriding each entry's own
  # `shellTool`. That is what produces a whole-corpus column for one tool —
  # `run_r.R`'s `tre`/`pcre2` argument, in the same shape and for the same
  # reason.
  #
  # Without it there is no way to score the sweep's `--engine sed` / `--engine
  # awk` passes. `shell.json` records ONE answer per entry, for whichever tool
  # that entry named, and as of 2026-09-09 no corpus entry names one at all —
  # all 18 shell entries fall through to grep. So the file is 100% grep truth,
  # the sed and gawk branches below had never been reached by a corpus run,
  # and the sweep drove those two tools with correctness comparison switched
  # off entirely.
  if [ -n "${FORCE_TOOL:-}" ]; then
    shell_tool="$FORCE_TOOL"
  else
    shell_tool=$(printf '%s' "$entry" | jq -r '.shellTool // "grep"')
  fi

  # ── Determine which tool to call ────────────────────────────────────────────
  # 'E' in flags → ERE; absence → BRE.
  use_ere=0
  case "$flags" in *E*) use_ere=1;; esac
  use_ci=0
  case "$flags" in *i*) use_ci=1;; esac

  : > "$ERR_FILE"
  matches_raw=""
  HAVE_OFFSETS=0

  case "$shell_tool" in

    grep)
      # ── GNU grep match-extract ─────────────────────────────────────────────
      # -o   : print only the matched part, one match per line
      # -E   : ERE mode (when 'E' flag is set); default is BRE
      # -i   : case-insensitive (when 'i' flag is set)
      # --   : end options, so patterns starting with '-' are treated as patterns
      # exit 1 from grep means "no matches" — not an error; we suppress it with `|| true`.
      grep_flags="-o"
      # -b prefixes every match with its BYTE offset in the input ("5:bb"), which the dialect columns record as
      # `index` so scripts/score-shell-column.mjs can compare offsets with the sidecar (it reports bytes too).
      case "$DIALECT" in
        pcre) grep_flags="$grep_flags -b -P"; HAVE_OFFSETS=1 ;;
        ere) grep_flags="$grep_flags -b -E"; HAVE_OFFSETS=1 ;;
        *) if [ "$use_ere" = 1 ]; then grep_flags="$grep_flags -E"; fi ;;
      esac
      if [ "$use_ci"  = 1 ]; then grep_flags="$grep_flags -i"; fi

      # shellcheck disable=SC2086 — intentional word-splitting of grep_flags
      matches_raw=$(printf '%s' "$test_text" \
        | "$GREP" $grep_flags -- "$pattern" 2>"$ERR_FILE") || true
      ;;

    sed)
      # ── GNU sed match-extract: `s///g` plus marker bytes ───────────────────
      # The technique of `run_shell_bsd.sh`'s sed arm (task 8, 2026-11-20).
      # This arm was `sed -n 's/PATTERN/&/p'`, which prints the PATTERN SPACE,
      # so it recorded whole lines, not matches, and spliced a pattern holding
      # `/` into the command unescaped (`unknown option to s'`). The column it
      # produced on 2026-09-09 was wrong data and was deleted
      # (`generate-ground-truth.ts`, the comment above the "shell-sed-gnu" entry).
      #
      # Every match is wrapped in two marker bytes by `s//M1&M2/g`, then the
      # spans are read back out. `g` finds each match on a line with GNU
      # sed's own anchoring, so `^a` over "aaa" is one match, not three.
      #
      # TWO free bytes and a DELIMITER, chosen per entry, as in the BSD arm:
      #   markers   — control bytes absent from the SUBJECT (a marker in the
      #               data would split a match), never \n;
      #   delimiter — a printable byte absent from the PATTERN, so the pattern
      #               is passed whole, with no `/` to escape.
      # jq picks them, not awk: the `gnu-sed` image carries mawk only, and a
      # forced sed column resolves no awk at all (`AWK` is empty here).
      free=$(printf '%s' "$entry" | jq -j '
        .testText as $t | .pattern as $p
        | [range(1; 32) | select(. != 10) | [.] | implode | . as $c | select(($t | index($c)) == null)] as $m
        | [",;:|#%!@~=+/" | split("")[] | . as $c | select(($p | index($c)) == null)] as $d
        | if ($m | length) < 2 or ($d | length) == 0 then empty else $m[0] + $m[1] + $d[0] end')
      if [ -z "$free" ]; then
        jq -nc --arg id "$id" \
          '{($id): {matches: [], error: "corpus harness: no free marker byte or s-command delimiter for this pattern/subject pair"}}' \
          >> "$RESULTS_FILE"
        continue
      fi
      m1=$(printf '%s' "$free" | cut -c1)
      m2=$(printf '%s' "$free" | cut -c2)
      delim=$(printf '%s' "$free" | cut -c3)

      sed_flags=""
      # The `sed-ere` column forces `-E` whatever the entry's flags say.
      if [ "$DIALECT" = ere ]; then use_ere=1; fi
      if [ "$use_ere" = 1 ]; then sed_flags="-E"; fi
      # GNU sed spells case-insensitive as the `I` flag of the s command (its
      # `-i` is in-place editing).
      subst="g"
      if [ "$use_ci" = 1 ]; then subst="gI"; fi

      # Zero-length matches give an EMPTY marker pair and are dropped by the
      # `length > 0` select, as `grep -o` prints nothing at a zero-width
      # position, so the columns stay comparable. sed's stderr is the entry's
      # error; jq only reads what sed printed.
      # shellcheck disable=SC2086 — intentional word-splitting of sed_flags
      matches_raw=$(printf '%s' "$test_text" \
        | "$SED" $sed_flags "s${delim}${pattern}${delim}${m1}&${m2}${delim}${subst}" 2>"$ERR_FILE" \
        | jq -Rj --arg m1 "$m1" --arg m2 "$m2" \
          'split($m1)[1:][] | split($m2)[0] | select(length > 0) | . + "\n"') || true
      ;;

    gawk)
      # ── GNU awk match-extract ──────────────────────────────────────────────
      # gawk /PATTERN/ { match($0, /PATTERN/, arr); print arr[0] }
      # gawk always uses ERE natively; the 'E' flag is a no-op here.
      # Case-insensitive: set IGNORECASE=1 at BEGIN.
      # IGNORECASE now rides in the same BEGIN block that reads ENVIRON, so
      # there is exactly one BEGIN and the two settings cannot get separated.
      awk_begin=""
      if [ "$use_ci" = 1 ]; then awk_begin='IGNORECASE=1;'; fi

      # Build the gawk program: mark every match with `gsub`, then read the
      # marked spans back out.
      #
      # ## Why not the obvious `match()` loop
      #
      # This was
      #
      #   while (match($0, pat, arr)) { print arr[0]; $0 = substr($0, RSTART + RLENGTH) }
      #
      # and it REBUILDS THE RECORD after every hit, so position 1 of the
      # remainder is a fresh start-of-line and a fresh word start. Every
      # anchored pattern that can match more than once therefore matched too
      # often. Measured 2026-09-09 against GNU grep and against gawk's own
      # `gsub`, which is the authority on how gawk anchors:
      #
      #   pattern  subject   this loop   grep -oE   gawk gsub
      #   ^a       aaa       a a a       a          1 replacement
      #   \<a      aa aa     a a a a     a a        2 replacements
      #
      # No corpus entry has that shape TODAY, so the committed `shell-awk.json`
      # is correct by luck rather than by construction — and this file has now
      # produced a wrong ground-truth column twice (the `-v` escape mangling
      # below, and the whole-line `sed` column that was deleted). A column is
      # not "fine because nothing exercises it": it is an oracle other engines
      # are scored against, and it must be right before the entry arrives, not
      # after someone notices.
      #
      # ## What this does instead
      #
      # `gsub` applies the pattern to the WHOLE record with gawk's real
      # anchoring semantics — `^` matches once, at the true start — and
      # replaces each match with the match itself wrapped in two control
      # bytes. Reading the wrapped spans back out is then a plain unanchored
      # scan, so nothing re-anchors. Verified to agree with `grep -oE` on
      # anchored, word-boundary, zero-width, repeated-group and multi-match
      # subjects.
      #
      # The markers are CHOSEN PER SUBJECT, from the control bytes the subject
      # does not itself contain. A fixed pair looked safe and was not: the
      # first version hard-coded \001/\002 on the assumption that no corpus
      # entry contains them, and regenerating the column immediately failed on
      # `l3-edge-backref-in-class-literal`, whose test text is literally
      # " 1 a". The guard caught it rather than mis-parsing, which is
      # what a guard is for — but a guard firing on real data is a design
      # answer, not a passing grade, so the markers now cannot collide by
      # construction. If a subject somehow used all 30 candidates the entry
      # errors out and says so, instead of reporting plausible nonsense.
      #
      # (`\n` is excluded as a candidate purely so the printed one-match-per-
      # line stream cannot be confused with a match that contains one; awk
      # records never contain the record separator anyway.)
      #
      # ## Zero-length matches
      #
      # Still skipped, and still for the reason the previous comment gave:
      # `grep -o` prints nothing at a zero-width position, so skipping keeps
      # the three tools comparable. Here they arrive as an EMPTY marker pair,
      # which is why the guard reads `RLENGTH > 2` (the two markers) rather
      # than `> 0`.
      #
      # The old loop's `RLENGTH < 1` guard existed to make it TERMINATE at
      # all: `substr($0, RSTART + RLENGTH)` advances by nothing on a
      # zero-length match, and on corpus entry `a+?` gawk matched empty at
      # position 1 and the container burned 8m51s of CPU at 99% before being
      # killed. That hazard is gone by construction — every span this loop
      # consumes is at least the two marker bytes long.
      awk_prog='{ rec = $0
        m1 = ""; m2 = ""
        for (c = 1; c <= 31 && m2 == ""; c++) {
          if (c == 10) continue
          ch = sprintf("%c", c)
          if (index(rec, ch) == 0) { if (m1 == "") m1 = ch; else m2 = ch }
        }
        if (m2 == "") {
          print "corpus harness: no free control byte to mark matches with" > "/dev/stderr"
          exit 3
        }
        gsub(pat, m1 "&" m2, rec)
        while (match(rec, m1 "[^" m2 "]*" m2)) {
          if (RLENGTH > 2) print substr(rec, RSTART + 1, RLENGTH - 2)
          rec = substr(rec, RSTART + RLENGTH)
        } }'

      # The pattern travels through the ENVIRONMENT, not `-v`.
      #
      # `gawk -v pat="$pattern"` processes the value as a STRING LITERAL, so
      # every backslash escape in the pattern is expanded before the regex
      # engine ever sees it: `\w` becomes the plain letter `w` and gawk warns
      # "escape sequence `\w' treated as plain `w'" on stderr. This script
      # captures stderr as the entry's `error`, so a whole corpus column came
      # back as errors that were the harness talking to itself.
      #
      # Measured 2026-09-09 before the fix: 180 of 181 "errors" in
      # `shell-awk.json` were that warning, and 168 of them were on entries
      # GNU grep compiles happily. `printf 'hello world' | gawk -v pat='\w+'`
      # matched `w`; via ENVIRON it matches `hello` and `world`.
      #
      # `ENVIRON` is read verbatim — no escape processing — which is the
      # documented way to hand gawk a regex that contains backslashes.
      matches_raw=$(printf '%s' "$test_text" \
        | RP_PAT="$pattern" "$AWK" "BEGIN{pat=ENVIRON[\"RP_PAT\"];${awk_begin}}${awk_prog}" 2>"$ERR_FILE") || true
      ;;

    *)
      # Unknown tool — record as error.
      jq -nc --arg id "$id" --arg e "unknown shellTool: $shell_tool" \
        '{($id): {matches: [], error: $e}}' >> "$RESULTS_FILE"
      continue
      ;;

  esac

  # The `cmd. line:N:` in a gawk diagnostic is a line number in THIS SCRIPT'S
  # OWN awk program, not in anything the corpus supplies, so it is harness
  # noise sitting inside recorded ground truth. Left in, it churns the column
  # every time the program is reformatted: making the extraction readable
  # moved it from line 1 to line 6 and rewrote 86 of the 290 entries without
  # changing a single fact about gawk. Normalised so a diff of this column
  # only ever shows a difference in what the ENGINE said.
  #
  # The `g` prefix is normalised away for the same reason. GNU grep and GNU sed
  # are installed as `ggrep`/`gsed` on macOS and as `grep`/`sed` in a container,
  # and each prints its own argv[0] in a diagnostic — so an identical warning
  # from an identical binary would be recorded as `ggrep: …` here and `grep: …`
  # there. That is a fact about the install, not about the engine, and leaving
  # it in would make every row carrying a warning differ between two
  # regenerations that agreed completely.
  # The tool is called by its RESOLVED path (`pick_gnu` prints `command -v`),
  # and grep names itself by that path: in the engine image every warning read
  # `/usr/bin/grep: warning: …` (task E6, 2026-11-20). The directory is
  # stripped first, so both installs come down to the bare tool name.
  err=$(tr -d "\r" < "$ERR_FILE" \
    | "$SED" -e 's/cmd\. line:[0-9][0-9]*:/cmd. line:/' \
             -e 's#^/[^:]*/\([a-z]*\):#\1:#' \
             -e 's/^ggrep:/grep:/' \
             -e 's/^gsed:/sed:/' \
    | head -c 500 || true)

  if [ -n "$err" ]; then
    # Tool emitted stderr — capture as error (warnings included).
    # This is intentional: GNU grep's "stray \ before d" warning IS ground truth
    # for patterns using non-POSIX escapes, and belongs in `error` here exactly
    # as recorded — do not change that. It does NOT mean the Rust sidecar
    # reproduces the same stderr line: sidecars/shell/src/main.rs is TRE-based
    # and never spawns real grep (App Sandbox forbids it), so TRE compiles
    # these escapes as silent literals instead of warning. The comparator is
    # not expected to match error-for-error against the sidecar on these rows
    # for that reason; parity for the USER is achieved separately, on the
    # TypeScript side, by `src/core/flavor/shellEscapeWarnings.ts` +
    # `validateRegex` (src/core/validation.ts). Corrected 2026-09-09 — see
    # KNOWN GAPS item 1 above for the full explanation.
    jq -nc --arg id "$id" --arg e "$err" \
      '{($id): {matches: [], error: $e}}' >> "$RESULTS_FILE"
    continue
  fi

  if [ -z "$matches_raw" ]; then
    # No error, no output → legitimate zero-match result.
    jq -nc --arg id "$id" \
      '{($id): {matches: [], error: null}}' >> "$RESULTS_FILE"
    continue
  fi

  # Wrap match lines as JSON array.
  # index: -1 is the sentinel used by all runners that don't report byte offsets
  # (postgres, shell).  The corpus comparator skips offset checking for shell.
  if [ "$HAVE_OFFSETS" = 1 ]; then
    # `ggrep -o -b` lines are "<byte offset>:<match>". A match that itself contains ":" keeps it (the offset is
    # everything before the FIRST colon).
    matches_json=$(printf '%s' "$matches_raw" | jq -Rsc '
      split("\n")
      | map(select(length > 0))
      | map(capture("^(?<o>[0-9]+):(?<m>.*)$") | {match: .m, index: (.o | tonumber)})
    ')
  else
    matches_json=$(printf '%s' "$matches_raw" | jq -Rsc '
      split("\n")
      | map(select(length > 0))
      | map({match: ., index: -1})
    ')
  fi

  jq -nc --arg id "$id" --argjson m "$matches_json" \
    '{($id): {matches: $m, error: null}}' >> "$RESULTS_FILE"

done < "$ENTRIES_FILE"

# Merge all per-entry JSONL lines into one JSON object.
jq -sc 'add // {}' "$RESULTS_FILE"
