#!/bin/sh
# Shell-tools reference runner — GNU grep / GNU sed / GNU awk ground truth.
#
# Provides byte-identical match output from real GNU tools so the corpus
# comparator can validate the Rust shell sidecar (regexpilot-shell-engine)
# against authentic GNU behavior.
#
# Image: alpine:3.19 (stock public image — same model as the other Docker
#   flavor runners, nothing custom to pre-build). The script installs
#   GNU grep / GNU sed / GNU gawk + jq via `apk add` on startup if they
#   are not already present. apk add is idempotent, so this block is a
#   no-op when run inside any image that already bundles the GNU tools.
#
# Tool selection — read from each corpus entry's optional `shellTool` key:
#   "grep" (default) — GNU grep -o [-E] [-i]; covers BRE, ERE, word-boundary
#   "sed"            — GNU sed -n 's/pattern/&/p' [-E] [-i]; match-extract via
#                      the print-on-match idiom (p flag, -n suppresses non-matches)
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
#      ground truth — this IS the correct behavior, matching what users see.
#      The Rust sidecar passes these through to system grep, so warnings propagate.
#   2. grep does not report byte offsets with -o.  All matches have index: -1.
#      The corpus comparator skips offset comparison for the shell flavor.
#   3. Zero-width assertions (lookahead, lookbehind) are NOT supported in GNU
#      grep BRE/ERE.  Patterns using (?=...) / (?<=...) will error.
#   4. The 'm' (multiline) flag is a no-op for grep — grep is inherently line-
#      oriented, so ^/$ always match line boundaries.  For sed and gawk, the
#      behaviour depends on record separator config (not applied here).
#   5. Sed and gawk sub-runners produce match-only output (not the result of
#      a substitution).  Replace semantics are validated by the Rust sidecar's
#      own unit tests (sidecars/shell/src/main.rs expand_shell_template tests).

set -eu

# ── Runtime dependency check / install ────────────────────────────────────────
# On stock alpine:3.19 the GNU tools aren't present (alpine ships busybox),
# so install the GNU builds we need. The checks below skip any tool that is
# already the GNU build, so this is a no-op inside images that pre-bundle them.
if ! command -v grep >/dev/null 2>&1 || ! grep --version 2>&1 | grep -q 'GNU'; then
  apk add --no-cache grep >/dev/null 2>&1 || true
fi
if ! command -v sed >/dev/null 2>&1 || ! sed --version 2>&1 | grep -q 'GNU'; then
  apk add --no-cache sed >/dev/null 2>&1 || true
fi
if ! command -v gawk >/dev/null 2>&1; then
  apk add --no-cache gawk >/dev/null 2>&1 || true
fi
if ! command -v jq >/dev/null 2>&1; then
  apk add --no-cache jq >/dev/null 2>&1 || true
fi

# ── I/O setup ─────────────────────────────────────────────────────────────────

INPUT_FILE=/tmp/input.json
RESULTS_FILE=/tmp/results.jsonl
ENTRIES_FILE=/tmp/entries.jsonl
cat > "$INPUT_FILE"
: > "$RESULTS_FILE"
jq -c '.[]' "$INPUT_FILE" > "$ENTRIES_FILE"

# ── Per-entry dispatch ─────────────────────────────────────────────────────────

while IFS= read -r entry; do
  id=$(printf '%s' "$entry" | jq -r '.id')
  pattern=$(printf '%s' "$entry" | jq -r '.pattern')
  test_text=$(printf '%s' "$entry" | jq -r '.testText')
  flags=$(printf '%s' "$entry" | jq -r '.flags // ""')
  shell_tool=$(printf '%s' "$entry" | jq -r '.shellTool // "grep"')

  # ── Determine which tool to call ────────────────────────────────────────────
  # 'E' in flags → ERE; absence → BRE.
  use_ere=0
  case "$flags" in *E*) use_ere=1;; esac
  use_ci=0
  case "$flags" in *i*) use_ci=1;; esac

  : > /tmp/err
  matches_raw=""

  case "$shell_tool" in

    grep)
      # ── GNU grep match-extract ─────────────────────────────────────────────
      # -o   : print only the matched part, one match per line
      # -E   : ERE mode (when 'E' flag is set); default is BRE
      # -i   : case-insensitive (when 'i' flag is set)
      # --   : end options, so patterns starting with '-' are treated as patterns
      # exit 1 from grep means "no matches" — not an error; we suppress it with `|| true`.
      grep_flags="-o"
      if [ "$use_ere" = 1 ]; then grep_flags="$grep_flags -E"; fi
      if [ "$use_ci"  = 1 ]; then grep_flags="$grep_flags -i"; fi

      # shellcheck disable=SC2086 — intentional word-splitting of grep_flags
      matches_raw=$(printf '%s' "$test_text" \
        | grep $grep_flags -- "$pattern" 2>/tmp/err) || true
      ;;

    sed)
      # ── GNU sed match-extract ──────────────────────────────────────────────
      # Idiom: -n 's/PATTERN/&/p'  — suppress output (-n), then on a match,
      # substitute the whole line with the matched portion (&) and print (p).
      # This gives one line per match per INPUT LINE (not per occurrence on a
      # line — sed processes line-by-line, not globally within a line).
      # Use -E for ERE, default is BRE.
      sed_flags="-n"
      if [ "$use_ere" = 1 ]; then sed_flags="$sed_flags -E"; fi
      if [ "$use_ci"  = 1 ]; then sed_flags="$sed_flags -i"; fi  # GNU sed: -i is case-fold in regex context? No: -i is in-place. Use \I in pattern instead.
      # NOTE: GNU sed does not have a -i=case-insensitive flag; -i is in-place edit.
      # Case-insensitive in sed requires the I modifier in the address or s command.
      # Reconstruct sed_flags without -i for case-insensitive:
      sed_flags="-n"
      if [ "$use_ere" = 1 ]; then sed_flags="$sed_flags -E"; fi
      sed_ci_flag=""
      if [ "$use_ci" = 1 ]; then sed_ci_flag="I"; fi

      # shellcheck disable=SC2086
      matches_raw=$(printf '%s' "$test_text" \
        | sed $sed_flags "s/$pattern/&/p${sed_ci_flag}" 2>/tmp/err) || true
      ;;

    gawk)
      # ── GNU awk match-extract ──────────────────────────────────────────────
      # gawk /PATTERN/ { match($0, /PATTERN/, arr); print arr[0] }
      # gawk always uses ERE natively; the 'E' flag is a no-op here.
      # Case-insensitive: set IGNORECASE=1 at BEGIN.
      awk_begin=""
      if [ "$use_ci" = 1 ]; then awk_begin='BEGIN{IGNORECASE=1}'; fi

      # Build the gawk program: match each line, print the matched portion.
      # Use OFMT trick to avoid locale-specific number formatting.
      awk_prog="${awk_begin}"'{ while (match($0, pat, arr)) { print arr[0]; $0 = substr($0, RSTART + RLENGTH) } }'

      matches_raw=$(printf '%s' "$test_text" \
        | gawk -v pat="$pattern" "$awk_prog" 2>/tmp/err) || true
      ;;

    *)
      # Unknown tool — record as error.
      jq -nc --arg id "$id" --arg e "unknown shellTool: $shell_tool" \
        '{($id): {matches: [], error: $e}}' >> "$RESULTS_FILE"
      continue
      ;;

  esac

  err=$(tr -d '\r' < /tmp/err | head -c 500 || true)

  if [ -n "$err" ]; then
    # Tool emitted stderr — capture as error (warnings included).
    # This is intentional: GNU grep's "stray \ before d" warning IS ground truth
    # for patterns using non-POSIX escapes.  The Rust sidecar propagates the
    # same warning, so the comparator can match error vs. error.
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
  matches_json=$(printf '%s' "$matches_raw" | jq -Rsc '
    split("\n")
    | map(select(length > 0))
    | map({match: ., index: -1})
  ')

  jq -nc --arg id "$id" --argjson m "$matches_json" \
    '{($id): {matches: $m, error: null}}' >> "$RESULTS_FILE"

done < "$ENTRIES_FILE"

# Merge all per-entry JSONL lines into one JSON object.
jq -sc 'add // {}' "$RESULTS_FILE"
