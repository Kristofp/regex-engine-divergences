// Regex corpus runner for Node.js (native RegExp / ECMAScript engine)
// stdin:  JSON array of {id, pattern, testText, flags}
// stdout: JSON object of {id: {matches: [{match, index}], error}}
// exit code: always 0 — per-pattern errors go in the error field
const entries = JSON.parse(require("fs").readFileSync("/dev/stdin", "utf8"));
const results = {};
for (const e of entries) {
  try {
    const flagStr = e.flags || "";
    // Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
    // and matches the bridge's behavior. Ensure 'g' is present so matchAll works.
    const effectiveFlags = flagStr.includes("g") ? flagStr : flagStr + "g";
    const rx = new RegExp(e.pattern, effectiveFlags);
    const matches = [];
    for (const m of e.testText.matchAll(rx)) {
      matches.push({ match: m[0], index: m.index });
    }
    results[e.id] = { matches, error: null };
  } catch (err) {
    results[e.id] = { matches: [], error: err.message };
  }
}
process.stdout.write(JSON.stringify(results));
