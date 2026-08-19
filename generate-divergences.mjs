#!/usr/bin/env node
// Generates DIVERGENCES.md from constructs.json + ground-truth/*.json.
// Zero dependencies. Run: node generate-divergences.mjs [corpusDir] > DIVERGENCES.md

import { readFileSync, readdirSync } from "node:fs";
import { join, basename } from "node:path";

const dir = process.argv[2] ?? ".";
const constructs = JSON.parse(readFileSync(join(dir, "constructs.json"), "utf8"));
const gtDir = join(dir, "ground-truth");

const truth = Object.fromEntries(
  readdirSync(gtDir)
    .filter((f) => f.endsWith(".json"))
    .map((f) => [basename(f, ".json"), JSON.parse(readFileSync(join(gtDir, f), "utf8"))]),
);

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
const ALIASES = {
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
const UNREPRODUCIBLE = ["re2"];

const engines = Object.keys(truth)
  .filter((e) => !(e in ALIASES) && !UNREPRODUCIBLE.includes(e))
  .sort();

/** Signature for one engine's answer: the ordered list of matched substrings. */
const signature = (r) =>
  r.error ? "ERROR" : JSON.stringify(r.matches.map((m) => m.match));

/** Group engines by identical answer for one construct. */
function group(id) {
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
function classify(groups) {
  const answers = groups.filter(([sig]) => sig !== "ERROR");
  const nonEmpty = answers.filter(([sig]) => sig !== "[]");
  if (nonEmpty.length >= 2) return "A";
  if (nonEmpty.length === 1 && answers.length > 1) return "B";
  if (groups.some(([sig]) => sig === "ERROR") && answers.length >= 1) return "C";
  return "agree";
}

const buckets = { A: [], B: [], C: [], agree: [] };
for (const c of constructs) {
  const groups = group(c.id);
  if (groups.length === 0) continue; // never exercised
  buckets[classify(groups)].push({ c, groups });
}

// ── formatting helpers ────────────────────────────────────────────────────────
const tested = buckets.A.length + buckets.B.length + buckets.C.length + buckets.agree.length;
const pct = (n) => ((n / tested) * 100).toFixed(0);
// Backticks survive markdown tables; a literal pipe does not.
const code = (s) => "`" + String(s).replaceAll("|", "\\|") + "`";
const show = (s) => JSON.stringify(s).slice(1, -1);
// Descriptions are free text and routinely contain \h, \b, \w — markdown eats
// a lone backslash, so escape it rather than silently rendering "h" for "\h".
const prose = (s) => s.replaceAll("\\", "\\\\");
const answer = (sig) =>
  sig === "ERROR" ? "_rejects the pattern_" : sig === "[]" ? "_no matches_" : code(sig);

const out = [];
const w = (s = "") => out.push(s);

w("# Where regex engines disagree");
w();
w(`Generated from \`constructs.json\` + \`ground-truth/\` — do not edit by hand.`);
w();
w(`- **${constructs.length}** constructs, **${engines.length}** engines, **${tested}** constructs exercised by at least one engine`);
w(`- **${buckets.agree.length}** (${pct(buckets.agree.length)}%) — every engine agrees`);
w(`- **${buckets.A.length}** (${pct(buckets.A.length)}%) — **Class A**: engines return *different* matches, silently`);
w(`- **${buckets.B.length}** (${pct(buckets.B.length)}%) — **Class B**: at least one engine matches *nothing*, silently`);
w(`- **${buckets.C.length}** (${pct(buckets.C.length)}%) — **Class C**: at least one engine rejects the pattern, loudly`);
w();
w("Class C is the safe case: the engine tells you. Classes A and B are the");
w("ones that reach production, because nothing anywhere reports a problem.");
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
  for (const [e, n] of [...tally].sort((a, b) => b[1] - a[1])) w(`| ${e} | ${n} |`);
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

w("## Engine coverage");
w();
w("Not every construct is exercised on every engine — many are written to");
w("probe one flavor's specific behaviour.");
w();
w(`| Engine | Constructs exercised |`);
w(`| --- | --- |`);
for (const e of engines) w(`| ${e} | ${Object.keys(truth[e]).length} |`);
w();

process.stdout.write(out.join("\n"));
