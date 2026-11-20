#!/bin/sh
# Shell-tools reference runner — BSD grep / BWK awk ground truth, ON THE HOST.
#
# This is the AUTHORITATIVE shell column (owner, 2026-09-10). `run_shell.sh` is
# its GNU twin and is retained, not replaced: it still produces the GNU column,
# kept as knowledge for a future "GNU tools" option. Today the app supports BSD
# only, because that is what its users have.
#
# That twin ALSO runs on the host now (2026-09-10, same day) — its own header
# has the measurement, but the short version is that no container image has a
# gawk newer than 5.3.2 and 5.4.0 changed the matcher. So the two runners share
# a model: both resolve their tools by name, both verify the dialect they got,
# and both exit 3 rather than emit a column under the wrong one's filename.
# They differ only in which direction they refuse.
#
# ## Why the host and not a container
#
# There is no BSD container to run. Measured 2026-09-10:
#
#   docker manifest inspect freebsd/freebsd-runtime:14.2
#     -> freebsd/arm64, freebsd/amd64   (no linux/* image exists at all)
#   docker run --platform freebsd/arm64 ... /bin/sh -c 'uname -a'
#     -> pulls, then exit 139 (SIGSEGV)
#
# Docker Desktop is a linux/arm64 VM and a FreeBSD userland needs a FreeBSD
# kernel. And even if it ran, it would be the WRONG oracle: BSD grep carries no
# regex engine — it calls the platform libc's `regcomp`/`regexec` (confirmed:
# both the macOS and FreeBSD binaries import those symbols rather than defining
# them). Apple's libc and FreeBSD's libc forked long ago, so identical
# `2.6.0-FreeBSD` version strings on both say nothing about matching behaviour.
# "BSD" is not one engine; it is whatever libc the machine has. The machine
# this app runs on is the only correct reference.
#
# ## The cost, stated plainly
#
# Shell becomes the one flavor whose ground truth is not reproducible in a
# container. Regenerate it on macOS or not at all — which is why this script
# REFUSES to run on GNU tools rather than quietly emitting a GNU column under a
# BSD name. A mislabelled oracle is worse than a missing one.
#
# ## Tools
#
#   grep — /usr/bin/grep, "BSD grep, GNU compatible" 2.6.0-FreeBSD
#   awk  — /usr/bin/awk, one-true-awk (BWK) version 20200816
#
# Absolute paths deliberately: Homebrew's `ggrep`/`gawk` are frequently ahead
# of these on PATH, and picking one up here is exactly the failure this file
# exists to prevent.
#
# ## sed HAS A COLUMN (since 2a213fc7) — this section used to deny it
#
# What stood here: "`sed -n 's/PAT/&/p'` prints the PATTERN SPACE, i.e. the whole
# line, so the column records lines rather than matches … sed has no native
# print-every-match-on-a-line idiom … Until someone builds and verifies a real
# extractor, the sweep saying `correctness NOT compared` is the honest state."
#
# The first half is still true and is why the naive form was reverted after an
# hour on 2026-09-09. The conclusion is not: the `sed)` branch below builds a
# real per-match extractor with the same marker technique the awk case uses, and
# its own comment records that this text is superseded. Leaving the denial here
# told a reader the sed dialect has no oracle while one was shipping two hundred
# lines down — and "no oracle" is precisely the state that made every sed-path
# defect invisible to the corpus. Found by CodeRabbit, 2026-09-11.
#
# ## KNOWN GAPS
#
#   1. BWK awk has NO case-insensitive facility. `IGNORECASE` is a gawk
#      extension and is a measured no-op here:
#
#        printf 'aXb' | awk 'BEGIN{IGNORECASE=1}{print match($0,/x/)?"y":"n"}'
#        -> n
#
#      11 of the 295 shell-applicable corpus entries carry the `i` flag. They
#      are recorded as an ERROR rather than silently answered case-sensitively,
#      because a case-sensitive answer to a case-insensitive question is a
#      wrong fact, and silently dropping the flag is what
#      `src/core/flavor/shellToolCapabilities.ts` already documents as the
#      reason `AWK.caseInsensitiveFlag` is `null`.
#
#   2. No byte offsets. All matches carry `index: -1`, the sentinel every
#      offset-less runner uses; the comparator skips offset checks for shell.
#
#   3. Both tools read ONE LINE AT A TIME, so a pattern spanning a newline
#      cannot match however correct it looks. Same for GNU.
#
# stdin:  JSON array of {id, pattern, testText, flags, shellTool?}
# stdout: JSON object of {id: {matches, error}}

set -eu

GREP=/usr/bin/grep
SED=/usr/bin/sed
AWK=/usr/bin/awk

FORCE_TOOL="${1:-}"
case "$FORCE_TOOL" in
  "" | grep | sed | awk) ;;
  *)
    echo "run_shell_bsd.sh: unknown tool '$FORCE_TOOL' (expected grep, sed or awk)" >&2
    exit 2
    ;;
esac

# ── Refuse to produce a BSD column from GNU tools ─────────────────────────────
#
# Fails LOUDLY and in both directions rather than falling back. A column
# generated on Linux and committed as BSD truth would be indistinguishable from
# the real thing afterwards, and every comparison built on it would be wrong in
# a way nothing could detect.
if ! "$GREP" --version 2>&1 | head -1 | "$GREP" -q 'BSD grep'; then
  echo "run_shell_bsd.sh: $GREP is not BSD grep — refusing to emit a BSD column." >&2
  echo "  got: $("$GREP" --version 2>&1 | head -1)" >&2
  echo "  This column must be generated on macOS. See the header." >&2
  exit 3
fi
# BWK awk identifies itself as `awk version NNNNNNNN` and has no `--version`;
# gawk answers `GNU Awk x.y.z`. Test for the GNU string rather than for the BWK
# one, so an unknown third awk also fails rather than passing by omission.
if "$AWK" --version 2>&1 | head -1 | "$GREP" -q 'GNU Awk'; then
  echo "run_shell_bsd.sh: $AWK is GNU Awk — refusing to emit a BSD column." >&2
  exit 3
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "run_shell_bsd.sh: jq is required" >&2
  exit 3
fi

# ── I/O setup ─────────────────────────────────────────────────────────────────
#
# A private temp dir, not fixed /tmp paths. The GNU runner can use /tmp because
# it owns its container; this one shares a real machine with everything else,
# including a possible second regeneration.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rp-shell-bsd.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

INPUT_FILE="$WORK/input.json"
RESULTS_FILE="$WORK/results.jsonl"
ENTRIES_FILE="$WORK/entries.jsonl"
ERR_FILE="$WORK/err"
cat > "$INPUT_FILE"
: > "$RESULTS_FILE"
jq -c '.[]' "$INPUT_FILE" > "$ENTRIES_FILE"

while IFS= read -r entry; do
  id=$(printf '%s' "$entry" | jq -r '.id')
  pattern=$(printf '%s' "$entry" | jq -r '.pattern')
  test_text=$(printf '%s' "$entry" | jq -r '.testText')
  flags=$(printf '%s' "$entry" | jq -r '.flags // ""')

  if [ -n "${FORCE_TOOL:-}" ]; then
    shell_tool="$FORCE_TOOL"
  else
    shell_tool=$(printf '%s' "$entry" | jq -r '.shellTool // "grep"')
    # The GNU runner spells its awk branch `gawk`, after the binary it
    # installs. Accept that spelling so a corpus entry written for one runner
    # is not silently skipped by the other.
    [ "$shell_tool" = "gawk" ] && shell_tool=awk
  fi

  use_ere=0
  case "$flags" in *E*) use_ere=1 ;; esac
  use_ci=0
  case "$flags" in *i*) use_ci=1 ;; esac

  : > "$ERR_FILE"
  matches_raw=""

  case "$shell_tool" in

    grep)
      # -o one match per line, -E ERE (default is BRE), -i case-fold,
      # -- so a pattern starting with `-` is a pattern. Exit 1 is "no match",
      # not an error.
      grep_flags="-o"
      [ "$use_ere" = 1 ] && grep_flags="$grep_flags -E"
      [ "$use_ci" = 1 ] && grep_flags="$grep_flags -i"

      # shellcheck disable=SC2086 — intentional word-splitting of grep_flags
      matches_raw=$(printf '%s' "$test_text" \
        | "$GREP" $grep_flags -- "$pattern" 2>"$ERR_FILE") || true
      ;;

    sed)
      # sed HAS no `-o`. It has `s///g`, which is the same thing once every
      # match is made findable — the marker technique the awk case below
      # already uses, pointed at a different tool.
      #
      # This file used to say "sed has no native print-every-match-on-a-line
      # idiom … until someone builds and verifies a real extractor, the sweep
      # saying `correctness NOT compared` is the honest state". Honest, and
      # it left the sed dialect with NO ORACLE AT ALL: every sed-path defect
      # in the sidecar was invisible to the corpus by construction. A second
      # model reviewing the tool work found three of them in one pass, all in
      # code the corpus could not have caught.
      #
      # TWO free bytes and a DELIMITER, and they are different problems:
      #
      #   markers   — must be absent from the SUBJECT, or a marker occurring
      #               in the data splits a match in half. Chosen per subject,
      #               same as awk below, same reasoning.
      #   delimiter — must be absent from the PATTERN, and must be PRINTABLE.
      #               Measured: BSD sed rejects a control byte here with
      #               `unescaped newline inside substitute pattern`, whatever
      #               byte it actually is. So the two cannot share a pool.
      free=$(printf '%s' "$test_text" | RP_PATTERN="$pattern" "$AWK" '
        BEGIN { pat = ENVIRON["RP_PATTERN"] }
        { rec = rec $0 "\n" }
        END {
          m1 = ""; m2 = ""
          for (c = 1; c <= 31 && m2 == ""; c++) {
            if (c == 10) continue
            ch = sprintf("%c", c)
            if (index(rec, ch) == 0) { if (m1 == "") m1 = ch; else m2 = ch }
          }
          # Printable delimiter candidates, none of them regex-special enough
          # to matter INSIDE an s command (the delimiter is not part of the
          # pattern) and all of them ordinary in a shell double-quoted string.
          d = ""
          n = split(",;:|#%!@~=+/", cand, "")
          for (i = 1; i <= n && d == ""; i++) {
            if (index(pat, cand[i]) == 0) d = cand[i]
          }
          if (m2 == "" || d == "") exit 3
          printf "%s%s%s", m1, m2, d
        }') || {
        jq -nc --arg id "$id" \
          '{($id): {matches: [], error: "corpus harness: no free marker byte or s-command delimiter for this pattern/subject pair"}}' \
          >> "$RESULTS_FILE"
        continue
      }
      m1=$(printf '%s' "$free" | cut -c1)
      m2=$(printf '%s' "$free" | cut -c2)
      delim=$(printf '%s' "$free" | cut -c3)

      sed_flags=""
      [ "$use_ere" = 1 ] && sed_flags="-E"
      # BSD sed spells case-insensitive as an `I` flag on the s command —
      # `shellToolCapabilities.ts` records the same letter.
      subst="g"
      [ "$use_ci" = 1 ] && subst="gI"

      # Zero-length matches produce an EMPTY marker pair and are dropped by
      # the `length > 0` filter, matching `grep -o`, which prints nothing at a
      # zero-width position — so the two columns stay comparable.
      # shellcheck disable=SC2086 — intentional word-splitting of sed_flags
      matches_raw=$(printf '%s' "$test_text" \
        | "$SED" $sed_flags "s${delim}${pattern}${delim}${m1}&${m2}${delim}${subst}" 2>"$ERR_FILE" \
        | "$AWK" -v m1="$m1" -v m2="$m2" '
          {
            rec = $0
            while (match(rec, m1 "[^" m2 "]*" m2)) {
              s = substr(rec, RSTART + 1, RLENGTH - 2)
              if (length(s) > 0) print s
              rec = substr(rec, RSTART + RLENGTH)
            }
          }') || true
      ;;

    awk)
      if [ "$use_ci" = 1 ]; then
        # KNOWN GAP 1. Recorded as an error, deliberately — see the header.
        jq -nc --arg id "$id" \
          '{($id): {matches: [], error: "BWK awk has no case-insensitive facility (IGNORECASE is a gawk extension and a measured no-op here); the i flag cannot be honoured"}}' \
          >> "$RESULTS_FILE"
        continue
      fi

      # The pattern travels in the ENVIRONMENT, never through `-v`.
      #
      # `-v` runs its value through awk's escape processing before the regex
      # engine sees it, so `\w` arrives as a bare `w` and the column records a
      # different pattern from the one the corpus holds. That defect shipped
      # once already and is pinned by test/corpusShellAwkExtraction.test.ts.
      # `ENVIRON` does no such processing.
      #
      # Extraction is marker-gsub, not a match() loop. The obvious
      #
      #     while (match(rest, pat)) { print ...; rest = substr(rest, ...) }
      #
      # REBUILDS the subject each time, so every remainder begins with a fresh
      # start-of-line and every anchored pattern over-matches. `gsub` anchors
      # once against the whole record, which is the correct semantics.
      # Verified on BWK awk 20200816: `^a` over "aaa" gives 1 replacement, and
      # over "aa aa" gives 1 — the naive loop gives 3 and 2.
      #
      # The markers are CHOSEN PER SUBJECT, ported from `run_shell.sh`, which
      # learned this the hard way and whose comment records it. The first
      # version of THIS file hard-coded \001/\002 on the same assumption its
      # GNU twin had already disproved — that no corpus subject contains them
      # — and the corpus holds two that do: `l3-edge-backref-in-class-literal`
      # (test text "\001 1 a") and `l3-edge-null-in-class` ("\000\001\002abc").
      #
      # Neither is shell-applicable TODAY, so a fixed pair would have produced
      # a correct column by luck. That is precisely the state this repo keeps
      # paying for: the column would simply have been wrong, confidently, the
      # day such an entry gained the shell flavor. Cannot collide by
      # construction now; if a subject somehow uses all 30 candidates the entry
      # errors out and says so rather than reporting plausible nonsense.
      #
      # \n is excluded as a candidate so the one-match-per-line stream cannot
      # be confused with a match containing one.
      #
      # Zero-length matches arrive as an EMPTY marker pair and are dropped by
      # the `length > 0` filter in the jq below, matching `grep -o`, which
      # prints nothing at a zero-width position — so the two tools stay
      # comparable. The loop cannot spin on them either: every span it consumes
      # is at least the two marker bytes long, so `rest` always shrinks.
      matches_raw=$(printf '%s' "$test_text" \
        | RP_PATTERN="$pattern" "$AWK" '
          BEGIN { pat = ENVIRON["RP_PATTERN"] }
          {
            rec = $0
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
            if (gsub(pat, m1 "&" m2, rec) == 0) next
            while (match(rec, m1 "[^" m2 "]*" m2)) {
              print substr(rec, RSTART + 1, RLENGTH - 2)
              rec = substr(rec, RSTART + RLENGTH)
            }
          }
        ' 2>"$ERR_FILE") || true
      ;;

    *)
      jq -nc --arg id "$id" --arg t "$shell_tool" \
        '{($id): {matches: [], error: ("unknown shellTool: " + $t)}}' >> "$RESULTS_FILE"
      continue
      ;;
  esac

  # `source line number N` in a BWK awk diagnostic is a line number in THIS
  # SCRIPT'S OWN awk program, not in anything the corpus supplies — harness
  # noise sitting inside recorded ground truth. Left in, it churns the column
  # every time the program is reformatted: adding the per-subject marker block
  # above moved it from 5 to 11 and rewrote 130 of the 290 entries WITHOUT
  # CHANGING A SINGLE MATCH. Same disease, same treatment as `run_shell.sh`'s
  # `cmd. line:N:` normalisation. Normalised so a diff of this column only ever
  # shows a difference in what the ENGINE said.
  err=$(tr -d '\r' < "$ERR_FILE" \
    | sed 's/source line number [0-9][0-9]*/source line number N/' \
    | head -c 500 || true)

  if [ -n "$err" ]; then
    # stderr IS ground truth here, warnings included — the same contract the
    # GNU runner documents. BSD grep is quieter than GNU grep (it accepts
    # `\x1b` where GNU 3.8+ warns "stray \ before x"), and that difference is
    # precisely what this column exists to record.
    jq -nc --arg id "$id" --arg e "$err" \
      '{($id): {matches: [], error: $e}}' >> "$RESULTS_FILE"
    continue
  fi

  if [ -z "$matches_raw" ]; then
    jq -nc --arg id "$id" '{($id): {matches: [], error: null}}' >> "$RESULTS_FILE"
    continue
  fi

  matches_json=$(printf '%s' "$matches_raw" | jq -Rsc '
    split("\n")
    | map(select(length > 0))
    | map({match: ., index: -1})
  ')

  jq -nc --arg id "$id" --argjson m "$matches_json" \
    '{($id): {matches: $m, error: null}}' >> "$RESULTS_FILE"

done < "$ENTRIES_FILE"

jq -sc 'add // {}' "$RESULTS_FILE"
