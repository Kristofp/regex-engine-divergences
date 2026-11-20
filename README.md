# regex-engine-divergences

**The same regular expression can return different answers in different
programming languages — and when it does, there is usually no error, no
warning, nothing.** This repository measures how often. It contains 626
small test patterns, each executed on the real regex engines of 16
languages, plus every result they returned. Where a language offers a
second engine, and for the GNU builds of the shell tools, those answers
are recorded too and compared separately.

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

| What you get back                 | Languages                                           |
| --------------------------------- | --------------------------------------------------- |
| `["line1\r", "line2\r", "line3"]` | C#, Elixir, Go, Perl, PHP, PostgreSQL, Python, Rust |
| `["line1", "line2", "line3"]`     | JavaScript, Dart                                    |
| `["line1\r\nline2\r\nline3"]`     | Ruby, R                                             |

Three different answers. No errors, no warnings, no deprecation notices.

Build that in a browser console and ship it in Python: every value you
extract now ends in an invisible `\r` — the kind of bug that surfaces
weeks later as "these two identical-looking strings don't compare equal".
Ship it in Ruby and you get the whole input back as one match, because
**Ruby's `m` flag doesn't mean multiline** — it means "dot matches
newlines", and Ruby's `^`/`$` work per-line already. Same letter,
different meaning, nothing reported. R's default engine, TRE, hands back
the whole input too.

## The one with no excuse

Two characters: `\h`. In Ruby it means "a hex digit" (0–9, a–f). In Perl
and PHP the very same `\h` means "a horizontal space". Opposite meanings —
and both sides happily return matches:

| Pattern | Text            | Ruby finds         | Perl / PHP find |
| ------- | --------------- | ------------------ | --------------- |
| `\h+`   | `DEAD 00FF xyz` | `["DEAD", "00FF"]` | the two spaces  |

## How often do they disagree?

Of the 626 test patterns, 620 have a recorded answer. **322 ran on two or
more engines**; the other 298 probe one language's own feature and ran
only there, so they have nothing to be
compared with. Every figure in this section and in `DIVERGENCES.md` is out
of those 322. Each language counts once, with the engine it uses out of
the box.

| Outcome                         |   Count | What that means for you                                   |
| ------------------------------- | ------: | --------------------------------------------------------- |
| Everyone agrees                 |      34 | Same matches in every language. All good.                 |
| **Different answers, silently** |  **41** | Two languages both "work" — and return different matches. |
| **Nothing matches, silently**   | **224** | A valid pattern finds nothing somewhere. No error.        |
| Rejected, loudly                |      23 | At least one language refuses the pattern with an error.  |

(In `DIVERGENCES.md` these are Class A, Class B and Class C.)

The loud failures are the good ones — your build breaks, you fix it, you
move on. The silent rows are why this repo exists: 265 patterns where a
language hands you a wrong answer and nothing anywhere reports a problem.

Two things to keep in mind. The patterns were written to find
differences — edge cases, known quirks, one feature at a time — so these
are counts from a test set built to find trouble, not a real-world
failure rate. And **178 of the 224 silent no-matches are BSD grep**, the
shell tool macOS ships, which lacks the feature and says nothing. Discount
those and 110 patterns still differ, 87 of them silently. `\p{L}+` means
"one or more letters, in any alphabet"; run it on `Hello 世界 café` and
eight languages find the three words while JavaScript and Dart find
**zero**, because Unicode property escapes need the `u` flag and are
otherwise read as a literal `p`. Valid pattern, no error, no matches,
one-character fix that nothing tells you about. (Python's `re` at least
refuses it with an error.)

## What's in here

```
constructs.json      626 test patterns — pattern, subject, flags, category, level
ground-truth/        one JSON per engine or tool, keyed by pattern id
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

Sixteen headline targets, each executed on its own runtime, one per
language: the engine that language uses with no extra library or option.

| Target     | Engine                      |
| ---------- | --------------------------- |
| JavaScript | V8                          |
| Dart       | Dart VM                     |
| Python     | CPython `re`                |
| Ruby       | Onigmo                      |
| Perl       | Perl                        |
| Java       | `java.util.regex`           |
| C#         | .NET                        |
| PHP        | PCRE2                       |
| MySQL      | ICU (MySQL 8)               |
| Go         | RE2                         |
| Rust       | `regex` crate               |
| Elixir     | PCRE via Erlang OTP         |
| Swift      | ICU                         |
| R          | TRE (base R's default)      |
| PostgreSQL | Spencer ARE                 |
| Shell      | BSD grep (what macOS ships) |

Also executed, and compared with their language's default in a section
of their own rather than counted above: R with `perl = TRUE` (PCRE2),
Python's `regex` module, Rust's `fancy-regex`, JavaScript through Regex+,
BSD sed and awk, and GNU grep (BRE, `-E`, `-P`), GNU sed (BRE, `-E`) and
GNU awk. Counting them in the headline would let one language with nine
shell tools outvote the rest.

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

**Engine versions are pinned, and drift is re-checked.** The whole
corpus was last regenerated on 2026-11-20, on the engine versions
RegexPilot 1.5 ships (among them CPython 3.14.10, Ruby 4.0.10 and
Perl 5.44.0). If a newer engine version changes a recorded answer, that is exactly the
kind of finding this corpus exists to capture; please open an issue.

## Reproducing

```bash
node generate-divergences.mjs > DIVERGENCES.md
```

That reads only the committed JSON — no dependencies, no network.
Regenerating the ground truth itself needs every runtime above; `runners/`
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
own test suite. There is no CI: the ground truth is regenerated on the
maintainer's machine by the runners in `runners/`.

Snapshot taken from commit `bb3934a0` (`bb3934a05bfcb7617898ef24d8c6733815e6095e`).

Updates land here as new snapshots rather than as edits, so a figure quoted
from this repo always has a commit behind it. Corrections are still very
welcome as issues or PRs — they are applied upstream and flow back in the
next snapshot.
