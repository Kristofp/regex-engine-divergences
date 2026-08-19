#!/bin/sh
# MySQL 8 reference runner — spins up a one-shot MySQL server inside
# the mysql:8 image, runs each corpus entry against `REGEXP_LIKE` /
# `REGEXP_SUBSTR` (MySQL 8.0.4+ ICU-backed regex), emits JSON ground
# truth.
#
# stdin:  JSON array of {id, pattern, testText, flags}
# stdout: JSON object of {id: {matches, error}}
#
# Invoked by generate-ground-truth.ts as:
#   docker run --rm -i -v $runnersDir:/runners -w /runners \
#     mysql:8 sh run_mysql.sh
#
# Note: MySQL's REGEXP_INSTR returns 1-based byte offsets (not char
# offsets) for multi-byte patterns. REGEXP_SUBSTR returns the matched
# string. To avoid encoding surprises we report the string match and
# translate to 0-based char offset via REGEXP_INSTR - 1; patterns
# touching multi-byte boundaries will need the comparator to skip
# exact offset checks (matches-content-only still catches adapter
# divergences).
set -eu

# mysql:8 is Oracle Linux with microdnf (not Debian/Alpine). Install
# jq quietly — takes ~3s cold, cached on repeat runs.
microdnf install -y jq >/dev/null 2>&1

# Initialize a data dir owned by the `mysql` user, then start mysqld on
# a unix socket only (no TCP) for sandbox tightness.
DATA=/var/lib/mysql-runner
mkdir -p "$DATA"
chown -R mysql:mysql "$DATA"

mysqld --initialize-insecure --user=mysql --datadir="$DATA" >/tmp/init.log 2>&1 || {
  echo '{"_error":"mysqld --initialize-insecure failed"}' >&2
  tail -20 /tmp/init.log >&2 || true
  exit 1
}

# UTF-8 and binary (case-sensitive) collation are required for accurate
# REGEXP/regex matching against our bundled mysql-icu sidecar:
#   - utf8mb4 server charset → \p{Letter}+ produces café/résumé/naïve
#     instead of mojibake (caf� r�…) which the default
#     character set produces when the runner sends Unicode input.
#   - utf8mb4_bin collation → ^[a-z_][a-z0-9_]*$ stays case-sensitive
#     (Docker default is *_ai_ci which case-folds, so camelCase would
#     match a snake-case-only validator pattern).
mysqld --user=mysql --datadir="$DATA" \
  --socket=/tmp/mysql.sock --skip-networking \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_bin \
  --log-error=/tmp/mysqld.log \
  --pid-file=/tmp/mysqld.pid &

# Wait for the socket to accept queries.
ready=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if mysql --protocol=SOCKET -S /tmp/mysql.sock -u root -e 'SELECT 1' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.5
done
if [ "$ready" != 1 ]; then
  echo '{"_error":"mysql failed to start"}' >&2
  tail -20 /tmp/mysqld.log >&2 || true
  exit 1
fi

INPUT_FILE=/tmp/input.json
RESULTS_FILE=/tmp/results.jsonl
ENTRIES_FILE=/tmp/entries.jsonl
cat > "$INPUT_FILE"
: > "$RESULTS_FILE"
jq -c '.[]' "$INPUT_FILE" > "$ENTRIES_FILE"

# Shell helper: run a MySQL query, stringify the result as a single-line
# JSON value. Escaping the pattern / text as SQL string literals via jq
# (-Rs with @sh) avoids injection from corpus entries that include
# unescaped quotes.
run_mysql() {
  sql="$1"
  # `--raw` suppresses MySQL's default batch-mode escaping of tab and
  # newline to `\t` / `\n` — we need real tabs for our TSV-to-JSON awk
  # splitter, and real newlines to iterate rows.
  # `--default-character-set=utf8mb4` ensures the client sends UTF-8 bytes
  # to the server intact (without it, the system default is sometimes
  # latin1 and any non-ASCII test text gets mangled before regex match).
  mysql --raw --default-character-set=utf8mb4 \
    --protocol=SOCKET -S /tmp/mysql.sock -u root -BN -e "$sql" 2>/tmp/err || true
}

while IFS= read -r entry; do
  id=$(printf '%s' "$entry" | jq -r '.id')
  pattern=$(printf '%s' "$entry" | jq -r '.pattern')
  test_text=$(printf '%s' "$entry" | jq -r '.testText')
  flags=$(printf '%s' "$entry" | jq -r '.flags // ""')

  # Map our flag letters to MySQL's match_type:
  #   i → i, m → m, s → n (MySQL's `n` = dot matches newline),
  #   c → c (case-sensitive override), u → u.
  # No `x` — MySQL's ICU regex doesn't surface verbose-mode as a
  # match_type flag (it's available inside the pattern via `(?x)`).
  match_type=""
  case "$flags" in *i*) match_type="${match_type}i";; esac
  case "$flags" in *m*) match_type="${match_type}m";; esac
  case "$flags" in *s*) match_type="${match_type}n";; esac
  # MySQL's ICU-backed REGEXP_INSTR / REGEXP_SUBSTR is case-insensitive
  # by DEFAULT regardless of column collation — ICU regex ignores
  # collation for case-handling. `c` is the only way to opt into the
  # case-sensitive behavior that aligns with our utf8mb4_bin server
  # config (and matches user expectation when typing /pattern/ with
  # no /i flag). Without this, ground truth treats `[a-z]` as case-
  # insensitive and inflates match counts on identifiers like
  # camelCase. Add `c` if `i` wasn't requested.
  case "$flags" in *i*) ;; *) match_type="${match_type}c";; esac

  # Escape pattern + text for MySQL single-quoted literal:
  # double every ' and \ to stay literal. (ICU doesn't care; MySQL
  # does.)
  esc_pattern=$(printf '%s' "$pattern" | sed "s/\\\\/\\\\\\\\/g; s/'/''/g")
  esc_text=$(printf '%s' "$test_text" | sed "s/\\\\/\\\\\\\\/g; s/'/''/g")

  : > /tmp/err

  # Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
  # and matches the bridge's behavior.
  # MySQL 8 supports recursive CTEs — use one to enumerate all matches
  # without needing stored-procedure WHILE loops. Each step starts
  # from the previous match-end + 1 (or +1 char for zero-width
  # matches) and emits one row per match. We inline the pattern and
  # text as SQL literals to avoid session-variable scope quirks in
  # batch mode.
  # Guard against advancing past the text length — REGEXP_INSTR
  # raises "Index out of bounds" when pos > CHAR_LENGTH(text) + 1.
  # The recursive step only runs when the previous match ended
  # strictly before end-of-text.
  matches_tsv=$(run_mysql "
    WITH RECURSIVE steps AS (
      SELECT
        REGEXP_INSTR('${esc_text}', '${esc_pattern}', 1, 1, 0, '${match_type}') AS start_pos,
        REGEXP_SUBSTR('${esc_text}', '${esc_pattern}', 1, 1, '${match_type}') AS match_str,
        1 AS depth,
        CHAR_LENGTH('${esc_text}') AS txt_len
      UNION ALL
      SELECT
        REGEXP_INSTR('${esc_text}', '${esc_pattern}',
          start_pos + GREATEST(CHAR_LENGTH(match_str), 1), 1, 0, '${match_type}') AS start_pos,
        REGEXP_SUBSTR('${esc_text}', '${esc_pattern}',
          start_pos + GREATEST(CHAR_LENGTH(match_str), 1), 1, '${match_type}') AS match_str,
        depth + 1,
        txt_len
      FROM steps
      WHERE match_str IS NOT NULL
        AND start_pos > 0
        AND (start_pos + GREATEST(CHAR_LENGTH(match_str), 1)) <= txt_len
        AND depth < 10000
    )
    SELECT CONCAT(start_pos - 1, '\t', match_str)
    FROM steps
    WHERE match_str IS NOT NULL AND start_pos > 0;
  " 2>/tmp/err)

  err=$(tr -d '\r' < /tmp/err | head -c 500 || true)

  # Convert TSV rows (index\tmatch per line) to a JSON matches array.
  # Use jq's -R (raw text input) + split so every character — including
  # control bytes returned by REGEXP_SUBSTR — is properly escaped
  # according to the JSON spec. Previous version built JSON by hand in
  # awk, which dropped control chars below 0x20 and produced payloads
  # jq's --argjson rejected downstream.
  if [ -n "$err" ]; then
    jq -nc --arg id "$id" --arg e "$err" '{($id): {matches: [], error: $e}}' >> "$RESULTS_FILE"
  else
    if [ -z "$matches_tsv" ]; then
      matches_json='[]'
    else
      matches_json=$(printf '%s' "$matches_tsv" | jq -Rsc '
        split("\n")
        | map(select(length > 0))
        | map(split("\t"))
        | map(select(length >= 2))
        | map({match: (.[1:] | join("\t")), index: (.[0] | tonumber)})
      ')
    fi
    jq -nc --arg id "$id" --argjson m "$matches_json" '{($id): {matches: $m, error: null}}' >> "$RESULTS_FILE"
  fi
done < "$ENTRIES_FILE"

jq -sc 'add' "$RESULTS_FILE"
