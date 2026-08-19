#!/bin/sh
# PostgreSQL reference runner — spins up a one-shot PG server inside the
# postgres:16-alpine image, runs each corpus entry against `regexp_match`
# (PG's ARE engine, Henry Spencer's Tcl/POSIX regex), emits JSON ground
# truth.
#
# stdin:  JSON array of {id, pattern, testText, flags}
# stdout: JSON object of {id: {matches, error}}
#
# Invoked by generate-ground-truth.ts as:
#   docker run --rm -i -v $runnersDir:/runners -w /runners \
#     postgres:16-alpine sh run_postgres.sh
#
# Note: PG's regexp_match / regexp_matches expose the captured substring
# only — no byte offset. We emit `index: -1` as a sentinel, and the
# corpus-side comparator should skip offset comparison for the postgres
# runner. Matches-content-only comparison is still meaningful because
# it catches adapter rewrites that mangle the match.
set -eu

apk add --no-cache jq >/dev/null 2>&1

export PGDATA=/tmp/pgdata
mkdir -p "$PGDATA"
chown postgres:postgres "$PGDATA"

su-exec postgres sh -c '
  initdb -D "$PGDATA" -U postgres --auth=trust -E UTF8 >/dev/null 2>&1
  pg_ctl -D "$PGDATA" \
    -o "-k /tmp -c listen_addresses=\"\"" \
    -l /tmp/pg.log start >/dev/null
'

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if su-exec postgres psql -h /tmp -U postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
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
  pattern=$(printf '%s' "$entry" | jq -j '.pattern'; printf X)
  pattern=${pattern%X}
  test_text=$(printf '%s' "$entry" | jq -j '.testText'; printf X)
  test_text=${test_text%X}

  # Map our flag letters to PG's inline flag letters (AREs).
  #   i → i  (case-insensitive)
  #   m → n  (newline-sensitive: ^/$ match line boundaries, . excludes \n)
  #   x → x  (expanded whitespace)
  # PG has no direct `s` (dotAll) — `.` matches newline only when the
  # newline-sensitive flag `n` is OFF, which is PG's default; so `s`
  # maps to no-op.
  pg_inline=""
  case "$flags" in *i*) pg_inline="${pg_inline}i";; esac
  case "$flags" in *m*) pg_inline="${pg_inline}n";; esac
  case "$flags" in *x*) pg_inline="${pg_inline}x";; esac
  if [ -n "$pg_inline" ]; then
    pattern="(?${pg_inline})${pattern}"
  fi

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
  # Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
  # and matches the bridge's behavior.
  # Postgres quirk: `regexp_matches` returns an array of *capture groups*,
  # not a [full_match, groups...] shape. When the user's pattern has
  # capture groups, `m[1]` gives the first capture — NOT the whole match.
  # Wrap the pattern in an outer capture so m[1] is always the full match
  # regardless of user-supplied groups. (Backref numbers in the user's
  # pattern shift by +1 under this wrap, but the match-test path doesn't
  # consume captures, only the full match text, so this is safe.)
  result=$(su-exec postgres psql -h /tmp -U postgres -tAX \
    -c "SELECT coalesce(jsonb_agg(jsonb_build_object('match', m[1], 'index', -1)), '[]'::jsonb)
         FROM (SELECT regexp_matches('${esc_text}', '(' || '${esc_pattern}' || ')', 'g') AS m) t" \
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
