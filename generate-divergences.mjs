#!/usr/bin/env node
// Generates DIVERGENCES.md from constructs.json + ground-truth/*.json.
// Zero dependencies. Run:
//   node generate-divergences.mjs [corpusDir] > DIVERGENCES.md
//   node generate-divergences.mjs [corpusDir] --figures > figures.json

import { readFileSync, readdirSync, realpathSync } from "node:fs";
import { basename, join } from "node:path";
import { pathToFileURL } from "node:url";

// ── Which ground-truth files count, and as what ──────────────────────────────
//
// Every file in `ground-truth/` must appear in exactly one of the five tables
// below, or the generator refuses to run. A new column is a decision (does it
// change the headline?), and a generator that silently counts whatever file
// appears is how a probe table once became "engine number 29".

/**
 * The headline: one column per language, the engine that language uses out of
 * the box, with no extra library and no option. Every Class A/B/C figure is
 * computed over these and nothing else. Policy agreed with the owner on
 * 2026-11-21.
 *
 * Two choices in it are not obvious:
 * - R is `r-tre`, not `r`. Base R's `grepl`/`regmatches` use TRE unless the
 *   caller passes `perl = TRUE`, and RegexPilot defaults to TRE too. The
 *   August 2026 figures counted `r` (that is, PCRE2) while the README's engine
 *   table said TRE.
 * - Shell is `shell`, which is BSD grep: the tool macOS ships. The other BSD
 *   tools and the GNU tools are alternatives below.
 */
export const ENGINES = {
  csharp: "C# (.NET)",
  dart: "Dart",
  elixir: "Elixir (PCRE via Erlang OTP)",
  go: "Go (RE2)",
  java: "Java (java.util.regex)",
  javascript: "JavaScript (V8)",
  mysql: "MySQL (ICU)",
  perl: "Perl",
  php: "PHP (PCRE2)",
  postgresql: "PostgreSQL (Spencer ARE)",
  python: "Python (re)",
  "r-tre": "R (TRE)",
  ruby: "Ruby (Onigmo)",
  rust: "Rust (regex crate)",
  shell: "Shell (BSD grep)",
  swift: "Swift (ICU)",
};

/**
 * Real, executed columns that are NOT the language's default: an engine you
 * opt into, or another tool. Each is compared with its language's default
 * column (`of`) in its own section and never enters the headline: counting
 * them would let one language with eight shell tools outvote the rest.
 */
export const ALTERNATIVES = {
  r: { of: "r-tre", label: "R with `perl = TRUE` (PCRE2)" },
  "python-regex": { of: "python", label: "Python `regex` module" },
  "rust-fancy-regex": { of: "rust", label: "Rust `fancy-regex` crate" },
  "js-regex-plus": { of: "javascript", label: "JavaScript through Regex+" },
  "shell-sed": { of: "shell", label: "BSD sed" },
  "shell-awk": { of: "shell", label: "BWK awk (macOS awk)" },
  "shell-gnu": { of: "shell", label: "GNU grep" },
  "shell-gnu-ere": { of: "shell", label: "GNU grep -E" },
  "shell-gnu-pcre": { of: "shell", label: "GNU grep -P" },
  "shell-sed-gnu": { of: "shell", label: "GNU sed" },
  "shell-sed-gnu-ere": { of: "shell", label: "GNU sed -E" },
  "shell-awk-gnu": { of: "shell", label: "GNU awk (gawk)" },
};

/** The same tool in its BSD and its GNU build: [BSD column, GNU column, tool]. */
export const BSD_GNU_PAIRS = [
  ["shell", "shell-gnu", "grep"],
  ["shell-sed", "shell-sed-gnu", "sed"],
  ["shell-awk", "shell-awk-gnu", "awk"],
];

/**
 * These targets were never executed — their ground truth is copied from the
 * engine they share. Counting them as independent agreement would inflate every
 * consensus figure in this document by up to five, so they are excluded from
 * the comparison and reported separately.
 *
 * The assumption is not free: `dart` was aliased to `javascript` on the same
 * "identical engine" reasoning, and disagreed on 5 of 247 entries once it was
 * actually run. Treat the remaining aliases as untested.
 */
export const ALIASES = {
  typescript: "javascript",
  scala: "java",
  kotlin: "java",
  groovy: "java",
  clojure: "java",
};

/**
 * Has recorded ground truth but no runner in the current generator — last
 * regenerated 2026-04-27 against an older corpus, so it cannot be reproduced
 * and cannot be shown to be correct. `go` covers the same RE2 engine with a
 * live runner, so nothing is lost by leaving this out.
 */
export const UNREPRODUCIBLE = ["re2"];

/** Files in `ground-truth/` that are not per-construct answers at all.
 *  `shell-capabilities-measured` is the shell tools' capability probe table. */
export const NOT_GROUND_TRUTH = ["shell-capabilities-measured"];

/**
 * Sorts every file name (without `.json`) into its table and refuses an
 * unclassified or missing one. The caller loads only the `engines` and
 * `alternatives` it returns; anything else in the directory is never read.
 */
export function classifyFiles(names) {
  const known = new Set([
    ...Object.keys(ENGINES),
    ...Object.keys(ALTERNATIVES),
    ...Object.keys(ALIASES),
    ...UNREPRODUCIBLE,
    ...NOT_GROUND_TRUTH,
  ]);
  const unknown = names.filter((n) => !known.has(n));
  if (unknown.length > 0) {
    throw new Error(
      `ground-truth/ holds unclassified file(s): ${unknown.join(", ")}. ` +
        "Add each to ENGINES, ALTERNATIVES, ALIASES, UNREPRODUCIBLE or NOT_GROUND_TRUTH in generate-divergences.mjs.",
    );
  }
  const present = new Set(names);
  const missing = [...Object.keys(ENGINES), ...Object.keys(ALTERNATIVES)].filter((n) => !present.has(n));
  if (missing.length > 0) throw new Error(`ground-truth/ is missing: ${missing.join(", ")}.json`);
  return {
    engines: Object.keys(ENGINES).sort(),
    alternatives: Object.keys(ALTERNATIVES).sort(),
  };
}

/** Signature for one engine's answer: the ordered list of matched substrings.
 *  Any recorded `error` counts as a rejection, including GNU grep's
 *  "warning: stray \" (it comes with zero matches, so the tool did say so). */
export const signature = (r) => (r.error ? "ERROR" : JSON.stringify(r.matches.map((m) => m.match)));

/** Groups `engines` by identical answer for construct `id`, largest group first.
 *  An engine with no recorded answer for `id` is left out, not counted as empty. */
function group(truth, engines, id) {
  const byAnswer = new Map();
  for (const e of engines) {
    const r = truth[e][id];
    if (!r) continue; // engine not exercised on this construct
    const sig = signature(r);
    if (!byAnswer.has(sig)) byAnswer.set(sig, []);
    byAnswer.get(sig).push(e);
  }
  return [...byAnswer.entries()].sort((a, b) => b[1].length - a[1].length);
}

/**
 * Three outcomes are NOT equally dangerous, so they are reported separately:
 *   A  two or more engines return different, non-empty match sets — no error anywhere
 *   B  every engine that matched agrees, but others return zero matches silently
 *   C  every engine that ran agrees, but others reject the pattern outright
 * A and B are silent. C is loud, and therefore harmless.
 */
export function classify(groups) {
  const answers = groups.filter(([sig]) => sig !== "ERROR");
  const nonEmpty = answers.filter(([sig]) => sig !== "[]");
  if (nonEmpty.length >= 2) return "A";
  if (nonEmpty.length === 1 && answers.length > 1) return "B";
  if (groups.some(([sig]) => sig === "ERROR") && answers.length >= 1) return "C";
  return "agree";
}

/** Compares one alternative column with another column on the constructs both
 *  answered. `silent` counts the differences where neither side reports an error. */
function compareColumns(truth, alt, base) {
  let compared = 0;
  let differ = 0;
  let silent = 0;
  for (const [id, r] of Object.entries(truth[alt])) {
    const b = truth[base][id];
    if (!b) continue;
    compared++;
    const [x, y] = [signature(r), signature(b)];
    if (x === y) continue;
    differ++;
    if (x !== "ERROR" && y !== "ERROR") silent++;
  }
  return { compared, differ, silent };
}

/**
 * Reads a corpus directory (`constructs.json` + `ground-truth/`) and returns
 * everything the report and the figures are built from. Throws on an
 * unclassified ground-truth file (see `classifyFiles`).
 */
export function analyse(dir) {
  const constructs = JSON.parse(readFileSync(join(dir, "constructs.json"), "utf8"));
  const gtDir = join(dir, "ground-truth");
  const names = readdirSync(gtDir)
    .filter((f) => f.endsWith(".json"))
    .map((f) => basename(f, ".json"));
  const { engines, alternatives } = classifyFiles(names);
  const truth = Object.fromEntries(
    [...engines, ...alternatives].map((e) => [e, JSON.parse(readFileSync(join(gtDir, `${e}.json`), "utf8"))]),
  );

  // Only a construct answered by two or more engines can agree or disagree.
  // One answered by a single engine (most probe one language's own feature)
  // is counted in `singleEngine` and classified as nothing: until 2026-11-21
  // those landed in "every engine agrees", which made 298 of 332 agreements
  // constructs that had nothing to be compared with.
  const buckets = { A: [], B: [], C: [], agree: [] };
  let answered = 0;
  for (const c of constructs) {
    const groups = group(truth, engines, c.id);
    if (groups.length === 0) continue; // no engine answered it
    answered++;
    if (groups.reduce((sum, [, es]) => sum + es.length, 0) < 2) continue; // nothing to compare with
    buckets[classify(groups)].push({ c, groups });
  }

  const altRows = alternatives.map((alt) => ({
    alt,
    ...ALTERNATIVES[alt],
    ...compareColumns(truth, alt, ALTERNATIVES[alt].of),
  }));
  const bsdGnuRows = BSD_GNU_PAIRS.map(([bsd, gnu, tool]) => ({ bsd, gnu, tool, ...compareColumns(truth, gnu, bsd) }));

  return { constructs, engines, truth, answered, buckets, altRows, bsdGnuRows };
}

/** Class B constructs where the shell column is the ONLY one matching nothing:
 *  BSD grep lacking the feature. The figure the prose tells readers to discount. */
function shellOnlyB(buckets) {
  return buckets.B.filter(({ groups }) => {
    const empty = groups.find(([sig]) => sig === "[]")?.[1] ?? [];
    return empty.length === 1 && empty[0] === "shell";
  }).length;
}

/**
 * The headline numbers, as the marketing site and the README quote them.
 * Written to `marketing-site/src/constants/corpus-figures.json`; a test
 * fails when that file disagrees with the corpus.
 */
export function figures({ constructs, engines, answered, buckets }) {
  const n = (k) => buckets[k].length;
  const compared = n("A") + n("B") + n("C") + n("agree");
  const shellOnly = shellOnlyB(buckets);
  return {
    constructs: constructs.length,
    answered,
    compared,
    singleEngine: answered - compared,
    engines: engines.length,
    agree: n("agree"),
    classA: n("A"),
    classB: n("B"),
    classC: n("C"),
    diverge: compared - n("agree"),
    silent: n("A") + n("B"),
    silentPercent: Math.round(((n("A") + n("B")) / compared) * 100),
    classBShellOnly: shellOnly,
    classBNotShell: n("B") - shellOnly,
    divergeNotShell: compared - n("agree") - shellOnly,
    silentNotShell: n("A") + n("B") - shellOnly,
  };
}

/** Renders the full DIVERGENCES.md text from `analyse`'s result. Deterministic:
 *  the same corpus always gives byte-identical output. */
export function render(analysis) {
  const { constructs, engines, truth, buckets, altRows, bsdGnuRows } = analysis;
  const f = figures(analysis);
  const pct = (k) => ((buckets[k].length / f.compared) * 100).toFixed(0);
  // Backticks survive markdown tables; a literal pipe does not.
  const code = (s) => "`" + String(s).replaceAll("|", "\\|") + "`";
  const show = (s) => JSON.stringify(s).slice(1, -1);
  // Descriptions are free text and routinely contain \h, \b, \w — markdown eats
  // a lone backslash, so escape it rather than silently rendering "h" for "\h".
  const prose = (s) => s.replaceAll("\\", "\\\\");
  const answer = (sig) => (sig === "ERROR" ? "_rejects the pattern_" : sig === "[]" ? "_no matches_" : code(sig));

  const out = [];
  const w = (s = "") => out.push(s);

  w("# Where regex engines disagree");
  w();
  w(`Generated from \`constructs.json\` + \`ground-truth/\` — do not edit by hand.`);
  w();
  w(`**${constructs.length}** constructs, **${engines.length}** engines. **${f.answered}** constructs have an answer;`);
  w(`**${f.singleEngine}** of them ran on one engine only (most probe one language's own`);
  w(`feature) and have nothing to be compared with. The other **${f.compared}** ran on two or`);
  w("more engines, and every figure below is out of those:");
  w();
  w(`- **${f.agree}** (${pct("agree")}%) — every engine agrees`);
  w(`- **${f.classA}** (${pct("A")}%) — **Class A**: engines return *different* matches, silently`);
  w(`- **${f.classB}** (${pct("B")}%) — **Class B**: at least one engine matches *nothing*, silently`);
  w(`- **${f.classC}** (${pct("C")}%) — **Class C**: at least one engine rejects the pattern, loudly`);
  w();
  w("Class C is the safe case: the engine tells you. Classes A and B are the");
  w("ones that reach production, because nothing anywhere reports a problem.");
  w();
  w(`${f.classBShellOnly} of the ${f.classB} Class B constructs are silent only in \`shell\` (BSD grep),`);
  w("which lacks the feature and says nothing. Discount those and");
  w(`${f.divergeNotShell} constructs still diverge, ${f.silentNotShell} of them silently.`);
  w();
  w("Each language is counted once, with the engine it uses out of the box. The");
  w("engines and tools you can opt into instead are compared with that default");
  w("in [Alternative engines and tools](#alternative-engines-and-tools).");
  w();
  w("The constructs were written to find differences: edge cases, known quirks,");
  w("one feature at a time. The shares above describe this corpus, not how often");
  w("an everyday regex breaks when it moves between languages.");
  w();

  w("## Class A — different matches, no error");
  w();
  w("A pattern that returns one answer in the engine you tested it in, and a");
  w("different answer in the engine you shipped it to.");
  w();
  for (const { c, groups } of buckets.A) {
    w(`### \`${c.id}\``);
    w();
    w(prose(c.description));
    w();
    w(`| | |`);
    w(`| --- | --- |`);
    w(`| pattern | ${code(c.pattern)} |`);
    w(`| subject | ${code(show(c.testText))} |`);
    w(`| flags | ${code(c.flags || "(none)")} |`);
    w();
    w(`| Result | Engines |`);
    w(`| --- | --- |`);
    for (const [sig, es] of groups) w(`| ${answer(sig)} | ${es.join(", ")} |`);
    w();
  }

  w("## Class B — silently matches nothing");
  w();
  w("Every engine that produced matches agrees with the others. The engines");
  w("listed as returning nothing raise no error — the pattern is accepted and");
  w("simply finds nothing.");
  w();
  {
    const tally = new Map();
    for (const { groups } of buckets.B) {
      const empty = groups.find(([sig]) => sig === "[]")?.[1] ?? [];
      for (const e of empty) tally.set(e, (tally.get(e) ?? 0) + 1);
    }
    w(`| Engine | Constructs silently matching nothing |`);
    w(`| --- | --- |`);
    for (const [e, n] of [...tally].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))) w(`| ${e} | ${n} |`);
    w();
    w("<details><summary>All Class B constructs</summary>");
    w();
    w(`| Construct | Pattern | Matches nothing in | Everyone else |`);
    w(`| --- | --- | --- | --- |`);
    for (const { c, groups } of buckets.B) {
      const empty = groups.find(([sig]) => sig === "[]")?.[1] ?? [];
      const real = groups.find(([sig]) => sig !== "[]" && sig !== "ERROR");
      w(`| \`${c.id}\` | ${code(c.pattern)} | ${empty.join(", ")} | ${answer(real?.[0] ?? "[]")} |`);
    }
    w();
    w("</details>");
    w();
  }

  w("## Class C — rejected outright");
  w();
  w("Listed for completeness. These are safe: the engine refuses the pattern,");
  w("so you find out at once rather than in production.");
  w();
  w("<details><summary>All Class C constructs</summary>");
  w();
  w(`| Construct | Pattern | Rejected by |`);
  w(`| --- | --- | --- |`);
  for (const { c, groups } of buckets.C) {
    const errs = groups.find(([sig]) => sig === "ERROR")?.[1] ?? [];
    w(`| \`${c.id}\` | ${code(c.pattern)} | ${errs.join(", ")} |`);
  }
  w();
  w("</details>");
  w();

  w("## Alternative engines and tools");
  w();
  w("Executed like every other column, but not counted above: each is an engine");
  w("or tool you opt into, compared here with its language's default on the");
  w("constructs both answered. \"Silently\" means neither side reports an error.");
  w();
  w(`| Column | What it is | Compared with | Compared | Differ | Differ silently |`);
  w(`| --- | --- | --- | --- | --- | --- |`);
  for (const r of altRows) w(`| ${r.alt} | ${r.label} | ${r.of} | ${r.compared} | ${r.differ} | ${r.silent} |`);
  w();
  w("### Shell: BSD and GNU");
  w();
  w("Shell is measured as the BSD tools macOS ships and, separately, as their");
  w("GNU builds. The same tool, BSD against GNU:");
  w();
  w(`| Tool | BSD column | GNU column | Compared | Differ | Differ silently |`);
  w(`| --- | --- | --- | --- | --- | --- |`);
  for (const r of bsdGnuRows) w(`| ${r.tool} | ${r.bsd} | ${r.gnu} | ${r.compared} | ${r.differ} | ${r.silent} |`);
  w();
  w("GNU grep and gawk print a warning such as `stray \\ before d` for an escape");
  w("they do not know, and still match nothing. That warning is recorded as an");
  w("error, so those rows count as loud. BSD grep matches nothing without a word.");
  w();

  w("## Engine coverage");
  w();
  w("Not every construct is exercised on every engine — many are written to");
  w("probe one flavor's specific behaviour.");
  w();
  w(`| Engine | What it is | Constructs exercised |`);
  w(`| --- | --- | --- |`);
  for (const e of engines) w(`| ${e} | ${ENGINES[e]} | ${Object.keys(truth[e]).length} |`);
  w();
  w(`Not counted: ${Object.entries(ALIASES).map(([a, s]) => `${a} (a copy of ${s})`).join(", ")}; ${UNREPRODUCIBLE.join(", ")} (no runner, cannot be reproduced).`);
  w();

  return out.join("\n");
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  const args = process.argv.slice(2);
  const dir = args.find((a) => !a.startsWith("--")) ?? ".";
  const analysis = analyse(dir);
  process.stdout.write(
    args.includes("--figures") ? `${JSON.stringify(figures(analysis), null, 2)}\n` : render(analysis),
  );
}
