# regex-engine-divergences

**The same regular expression can return different answers in different
programming languages — and when it does, there is usually no error, no
warning, nothing.** This repository measures how often. It contains 539
small test patterns, each executed on the real regex engines of 16
languages, plus every result they returned.

Not emulated, not approximated, not read from documentation. Every result
in `ground-truth/` was produced by running the actual runtime: CPython,
MRI Ruby, a GraalVM-built JVM, .NET, PCRE2, RE2, PostgreSQL's Spencer
engine, Erlang OTP, ICU, and seven more. The scripts that produced them
are in `runners/`.

---

## Start here

This is `^.+$` with the multiline flag — "give me every line" — run on
three lines of text that came out of a Windows file, where lines end in
`\r\n`:

| What you get back                 | Languages                                  |
| --------------------------------- | ------------------------------------------ |
| `["line1\r", "line2\r", "line3"]` | C#, Elixir, Go, Perl, PHP, Python, R, Rust |
| `["line1", "line2", "line3"]`     | JavaScript, Dart                           |
| `["line1\r\nline2\r\nline3"]`     | Ruby                                       |
| _rejects the pattern_             | PostgreSQL                                 |

Three different answers plus an error. No warnings, no deprecation notices.

Build that in a browser console and ship it in Python: every value you
extract now ends in an invisible `\r` — the kind of bug that surfaces
weeks later as "these two identical-looking strings don't compare equal".
Ship it in Ruby and you get the whole input back as one match, because
**Ruby's `m` flag doesn't mean multiline** — it means "dot matches
newlines", and Ruby's `^`/`$` work per-line already. Same letter,
different meaning, nothing reported.

## The one with no excuse

Two characters: `\h`. In Ruby it means "a hex digit" (0–9, a–f). In Perl
and PHP the very same `\h` means "a horizontal space". Opposite meanings —
and both sides happily return matches:

| Pattern | Text            | Ruby finds         | Perl / PHP find |
| ------- | --------------- | ------------------ | --------------- |
| `\h+`   | `DEAD 00FF xyz` | `["DEAD", "00FF"]` | the two spaces  |

## How often do they disagree?

Of the 539 test patterns, **534 ran on more than one engine** — the other
5 have no recorded answer anywhere and are counted in nothing below.
Every figure in this section and in `DIVERGENCES.md` is out of 534,
never 539.

| Outcome                         |   Count | What that means for you                                   |
| ------------------------------- | ------: | --------------------------------------------------------- |
| Everyone agrees                 |     270 | Same matches in every language. All good.                 |
| **Different answers, silently** |  **21** | Two languages both "work" — and return different matches. |
| **Nothing matches, silently**   | **160** | A valid pattern finds nothing somewhere. No error.        |
| Rejected, loudly                |      83 | At least one language refuses the pattern with an error.  |

(In `DIVERGENCES.md` these are Class A, Class B and Class C.)

The loud failures are the good ones — your build breaks, you fix it, you
move on. The silent rows are why this repo exists: 181 patterns, one in
three, where a language hands you a wrong answer and nothing anywhere
reports a problem.

**On the silent no-matches**: 135 of the 160 are POSIX shell tools, which
genuinely lack the feature — discount those. The remaining 25 do not
discount so easily. `\p{L}+` means "one or more letters, in any
alphabet"; run it on `Hello 世界 café` and nine languages find the three
words while JavaScript and Dart find **zero** — because Unicode property
escapes need the `u` flag and are otherwise read as a literal `p`. Valid
pattern, no error, no matches, one-character fix that nothing tells you
about.

## What's in here

```
constructs.json      539 test patterns — pattern, subject, flags, category, level
ground-truth/        one JSON per language, keyed by pattern id
runners/             the scripts that produced them (run_ruby.rb, run_java.java, …)
DIVERGENCES.md       generated — every disagreement, classified
generate-divergences.mjs
```

A test pattern:

```json
{
  "id": "edge-ruby-h-hex",
  "category": "flavor-specific",
  "level": 2,
  "description": "Ruby \\h = hex digit [0-9a-fA-F]; PCRE2 \\h = horizontal whitespace",
  "pattern": "\\h+",
  "testText": "DEAD 00FF xyz",
  "flags": "g"
}
```

A language's answer:

```json
{
  "edge-ruby-h-hex": {
    "matches": [{ "match": "DEAD", "index": 0 }],
    "error": null
  }
}
```

## Engines

Sixteen targets, each executed on its own runtime:

| Target     | Engine              |
| ---------- | ------------------- |
| JavaScript | V8                  |
| Dart       | Dart VM             |
| Python     | CPython `re`        |
| Ruby       | Onigmo              |
| Perl       | Perl                |
| Java       | `java.util.regex`   |
| C#         | .NET                |
| PHP        | PCRE2               |
| MySQL      | PCRE2 + UCP         |
| Go         | RE2                 |
| Rust       | `regex` crate       |
| Elixir     | PCRE via Erlang OTP |
| Swift      | ICU                 |
| R          | TRE                 |
| PostgreSQL | Spencer ARE         |
| Shell      | POSIX BRE/ERE       |

## Honest limits

**Coverage is uneven by design.** A pattern written to probe Elixir's `\w`
is not run against every other engine. Per-engine counts are at the bottom
of `DIVERGENCES.md`. Nothing is extrapolated: a language either has a
recorded answer, or it is absent from that comparison.

**Five targets are excluded because they were never independently run.**
TypeScript's results were copied from JavaScript; Kotlin, Scala, Groovy
and Clojure from Java, on the grounds that they share an engine. That
reasoning is plausible and it is _not_ verified — Dart was assumed
identical to JavaScript on exactly the same argument, and disagreed on 5
of 247 entries once it was actually executed. Rather than report copies as
independent agreement, they are left out.

**Comparison is on matched text, not positions.** Some runners report
positions in UTF-16 units and others in bytes, so positions are not yet
comparable across languages. The matched text is.

**One engine's data was dropped** — a stale `re2.json` with no runner in
the current generator. Go covers the same RE2 engine and is reproducible.

**Version drift is re-checked opportunistically.** Most recently
(2026-08-19): all 273 recorded Ruby answers were re-run on system Ruby
4.0.6 and came back byte-identical — matches, indices and error messages.
If a newer engine version changes a recorded answer, that is exactly the
kind of finding this corpus exists to capture; please open an issue.

## Reproducing

```bash
node generate-divergences.mjs > DIVERGENCES.md
```

That reads only the committed JSON — no dependencies, no network.
Regenerating the ground truth itself needs all 16 runtimes; `runners/`
documents each.

## Contributing

New test patterns are welcome, especially ones that produce a
different-answers-silently result. Open a PR adding to `constructs.json`
with recorded output from at least two languages and the exact commands
you ran.

Corrections matter more than additions. If a recorded answer is wrong,
that is a bug — tell us which language, which version, and what you got
instead.

## License

MIT. Use it in your own test suite, your own docs, your own tooling.

## Where this came from

This is the test corpus of [RegexPilot](https://regexpilot.com), a macOS
regex editor that bundles these engines and runs your pattern through the
real one instead of approximating it in JavaScript. The corpus exists
because shipping that claim meant proving it. A readable summary of the
data lives at
[regexpilot.com/divergences](https://regexpilot.com/divergences).

The data stands on its own, which is why it is here under MIT.

## Provenance

This repository is a **published snapshot**. The canonical copy of
`constructs.json`, `ground-truth/` and `runners/` lives in RegexPilot's
own test suite, where it is executed by CI on every change.

Snapshot taken from commit `c748f760` (`c748f760d5afc2b4dea33ef85a6d4b5b71d87e43`).

Updates land here as new snapshots rather than as edits, so a figure quoted
from this repo always has a commit behind it. Corrections are still very
welcome as issues or PRs — they are applied upstream and flow back in the
next snapshot.
