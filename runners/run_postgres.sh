#!/bin/sh
# PostgreSQL reference runner — spins up a one-shot PG server inside the
# postgres engine image (PostgreSQL 18.6), runs each corpus entry against `regexp_match`
# (PG's ARE engine, Henry Spencer's Tcl/POSIX regex), emits JSON ground
# truth.
#
# stdin:  JSON array of {id, pattern, testText, flags}
# stdout: JSON object of {id: {matches, error}}
#
# Invoked by generate-ground-truth.ts as:
#   docker run --rm -i -v $runnersDir:/runners -w /runners \
#     localhost/regexpilot-engine/postgres:18.6 sh run_postgres.sh
#
# Note: PG's regexp_match / regexp_matches expose the captured substring
# only — no byte offset. We emit `index: -1` as a sentinel, and the
# corpus-side comparator should skip offset comparison for the postgres
# runner. Matches-content-only comparison is still meaningful because
# it catches adapter rewrites that mangle the match.
set -eu

apk add --no-cache jq >/dev/null 2>&1

# Builds the exact pattern PG receives, outer capture wrap included.
#
# The wrap exists so `m[1]` is the whole match whatever groups the user wrote
# (regexp_matches returns capture groups, not [full, groups...]). Applying it
# naively corrupts two things, and did:
#
#   1. Embedded options are legal ONLY at the very start of an RE. `((?n)^a)`
#      is rejected outright — "quantifier operand invalid" — while `(?n)(^a)`
#      is fine. This hit both our flag-derived prefix and any pattern that
#      carries its own leading `(?x)`.
#   2. The wrap becomes group 1, so every user backreference shifts by one.
#      `(^(\w).*\1$)` makes `\1` point at the enclosing, still-open group and
#      PG rejects it as an invalid backreference number.
#
# Both produced ERRORS recorded as ground truth for patterns PostgreSQL
# accepts. 55 of 258 postgres corpus entries were affected, and because
# constructCorpus.test.ts SKIPS any entry whose reference errored, they were
# not failures — they were silently untested.
PG_XFORM='
def shift_backrefs:
  gsub("\\\\(?<d>[1-8])"; "\\" + ((.d | tonumber + 1) | tostring));

def pg_pattern($flags):
  (capture("^\\((?<o>\\?[a-z]+)\\)(?<rest>[\\s\\S]*)$") // null) as $lead
  | (if $lead then $lead.o[1:] else "" end) as $inline
  | (if $flags | test("i") then "i" else "" end) as $i
  | (if $flags | test("m") then "n" else "" end) as $m
  | (if $flags | test("x") then "x" else "" end) as $x
  | (if $lead then $lead.rest else . end) as $body
  | (($inline + $i + $m + $x) | split("") | unique | join("")) as $opts
  | (if $opts == "" then "" else "(?" + $opts + ")" end)
    + "(" + ($body | shift_backrefs) + ")";
'

# Runs a command as the postgres user. The postgres:16-alpine images carried su-exec; postgres:18 dropped it and
# carries only gosu (task E6, 2026-11-20: the 18.6 image failed here with "su-exec: not found"). Both take
# `USER COMMAND...`, so whichever the image has is used, su-exec first.
if command -v su-exec >/dev/null 2>&1; then DROP_TO=su-exec; else DROP_TO=gosu; fi
as_postgres() { "$DROP_TO" postgres "$@"; }

export PGDATA=/tmp/pgdata
mkdir -p "$PGDATA"
chown postgres:postgres "$PGDATA"

as_postgres sh -c '
  initdb -D "$PGDATA" -U postgres --auth=trust -E UTF8 >/dev/null 2>&1
  pg_ctl -D "$PGDATA" \
    -o "-k /tmp -c listen_addresses=\"\"" \
    -l /tmp/pg.log start >/dev/null
'

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if as_postgres psql -h /tmp -U postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.3
done
if [ "$ready" != 1 ]; then
  echo '{"_error":"postgres failed to start"}' >&2
  exit 1
fi

INPUT_FILE=/tmp/input.json
RESULTS_FILE=/tmp/results.jsonl
cat > "$INPUT_FILE"
: > "$RESULTS_FILE"

# `jq -c '.[]'` into a here-file avoids the subshell trap with
# `... | while read`. We materialize the entries, then a plain for-read
# loop runs in the current shell.
ENTRIES_FILE=/tmp/entries.jsonl
jq -c '.[]' "$INPUT_FILE" > "$ENTRIES_FILE"

while IFS= read -r entry; do
  id=$(printf '%s' "$entry" | jq -r '.id')
  flags=$(printf '%s' "$entry" | jq -r '.flags // ""')

  # `$(...)` STRIPS every trailing newline, so a subject like "the end\n"
  # arrived as "the end" and `end\Z` matched — recording ground truth that
  # real PostgreSQL does not produce (verified against postgres 16.14:
  # `end\Z` over E'the end\n' returns no rows). `jq -j` emits the value
  # with no newline of its own, and the X sentinel is stripped afterwards,
  # so whatever trailing newlines the SUBJECT has survive intact.
  test_text=$(printf '%s' "$entry" | jq -j '.testText'; printf X)
  test_text=${test_text%X}

  # Build the pattern PG actually receives, wrap included. See PG_XFORM at the
  # top of this file for why the wrap cannot be applied naively.
  #
  # Flag letters map to PG's inline option letters (AREs):
  #   i → i  (case-insensitive)
  #   m → n  (newline-sensitive: ^/$ match line boundaries, . excludes \n)
  #   x → x  (expanded whitespace)
  # PG has no direct `s` (dotAll) — `.` matches newline only when the
  # newline-sensitive flag `n` is OFF, which is PG's default; so `s`
  # maps to no-op.
  pattern=$(printf '%s' "$entry" \
    | jq -j --arg f "$flags" "$PG_XFORM"' .pattern | pg_pattern($f)'; printf X)
  pattern=${pattern%X}

  # Escape for a single-quoted SQL literal: PG doubles apostrophes;
  # backslashes are literal inside plain '...' literals (no E'...' prefix).
  # Same sentinel guard here: `sed` may add a trailing newline of its own
  # and `$(...)` would then eat the subject's, so the round trip must be
  # newline-exact on both ends.
  esc_pattern=$(printf '%s' "$pattern" | sed "s/'/''/g"; printf X)
  esc_pattern=${esc_pattern%X}
  esc_text=$(printf '%s' "$test_text" | sed "s/'/''/g"; printf X)
  esc_text=${esc_text%X}

  : > /tmp/err
  # Always emit all matches regardless of 'g' flag — see docs/archive/task-briefs/v1-corpus-fix-spec.md
  # and matches the bridge's behavior.
  # `m[1]` is the whole match because PG_XFORM already wrapped the pattern in
  # an outer capture. Do NOT add a second wrap here — the escaping, the option
  # hoist and the backreference shift are all done together up there, and a
  # wrap applied afterwards would re-break exactly what that function fixes.
  result=$(as_postgres psql -h /tmp -U postgres -tAX \
    -c "SELECT coalesce(jsonb_agg(jsonb_build_object('match', m[1], 'index', -1)), '[]'::jsonb)
         FROM (SELECT regexp_matches('${esc_text}', '${esc_pattern}', 'g') AS m) t" \
    2>/tmp/err || true)

  err=$(tr -d '\r' < /tmp/err | head -c 500 || true)
  if [ -z "$result" ]; then
    result='[]'
  fi

  if [ -n "$err" ]; then
    jq -nc --arg id "$id" --arg e "$err" '{($id): {matches: [], error: $e}}' >> "$RESULTS_FILE"
  else
    jq -nc --arg id "$id" --argjson m "$result" '{($id): {matches: $m, error: null}}' >> "$RESULTS_FILE"
  fi
done < "$ENTRIES_FILE"

jq -sc 'add' "$RESULTS_FILE"
