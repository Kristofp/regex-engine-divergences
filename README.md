# regex-engine-divergences

**539 regex constructs, executed on 16 real engines. Of the 534 with a
recorded answer, 264 behave differently somewhere — and only 83 tell
you.**

Not emulated, not approximated, not inferred. Every result in `ground-truth/`
was produced by running the actual runtime: CPython, MRI Ruby, a GraalVM-built
JVM, .NET, PCRE2, RE2, PostgreSQL's Spencer engine, Erlang OTP, ICU, and seven
more. The scripts that produced them are in `runners/`.

---

## Start here

This is `^.+$` with the multiline flag, on `line1\r\nline2\r\nline3`:

| Result                            | Engines                                    |
| --------------------------------- | ------------------------------------------ |
| `["line1\r", "line2\r", "line3"]` | C#, Elixir, Go, Perl, PHP, Python, R, Rust |
| `["line1", "line2", "line3"]`     | JavaScript, Dart                           |
| `["line1\r\nline2\r\nline3"]`     | Ruby                                       |
| _rejects the pattern_             | PostgreSQL                                 |

Three different answers plus an error. No warnings, no deprecation notices.

Build that in a browser console and ship it in Python: every field now carries
an invisible trailing `\r`. Ship it in Ruby and you get the whole input back as
one match — because **Ruby's `m` flag means dotall, not multiline**, and Ruby's
`^`/`$` are line anchors already. Same letter, different meaning, nothing
reported.

## The one with no excuse

`\h` is Ruby's hex-digit shorthand and PCRE2's horizontal-whitespace shorthand:

| Pattern | Subject         | Ruby               | Perl / PHP   |
| ------- | --------------- | ------------------ | ------------ |
| `\h+`   | `DEAD 00FF xyz` | `["DEAD", "00FF"]` | `[" ", " "]` |

Opposite meanings. Both succeed. Both return matches.

## The three ways engines disagree

Lumping these together undersells the problem, so `DIVERGENCES.md` splits them:

Of the 539 constructs, **534 are exercised by at least one engine** — the
remaining 5 have no recorded answer anywhere and are counted in nothing
below. Every figure in this section and in `DIVERGENCES.md` is out of 534,
never 539.

|             |   Count | What happens                                              |
| ----------- | ------: | --------------------------------------------------------- |
| Agreement   |     270 | Every engine returns the same matches.                    |
| **Class A** |  **21** | Engines return **different matches**. No error anywhere.  |
| **Class B** | **160** | At least one engine matches **nothing at all**. No error. |
| Class C     |      83 | At least one engine **rejects the pattern**.              |

Class C is fine — your build breaks, you fix it, you move on.

Classes A and B are why this repo exists: 181 constructs, a third of the corpus,
where you get a wrong answer and nothing anywhere reports a problem.

**On Class B**: 135 of the 160 are POSIX shell tools, which genuinely lack the
construct — discount those. The remaining 25 do not discount so easily.
`\p{L}+` against `Hello 世界 café` returns three matches on nine engines and
**zero** on JavaScript and Dart, because Unicode property escapes need the `u`
flag and are otherwise read as a literal `p`. Valid pattern, no error, no
matches, one-character fix that nothing tells you about.

## What's in here

```
constructs.json      539 cases — pattern, subject, flags, category, level
ground-truth/        one JSON per engine, keyed by construct id
runners/             the scripts that produced them (run_ruby.rb, run_java.java, …)
DIVERGENCES.md       generated — every disagreement, classified
generate-divergences.mjs
```

A construct:

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

An engine's answer:

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

**Coverage is uneven by design.** A construct written to probe Elixir's `\w` is
not run against every other engine. Per-engine counts are at the bottom of
`DIVERGENCES.md`. Nothing is extrapolated: an engine either has a recorded
answer, or it is absent from that comparison.

**Five targets are excluded because they were never independently run.**
TypeScript's results were copied from JavaScript; Kotlin, Scala, Groovy and
Clojure from Java, on the grounds that they share an engine. That reasoning is
plausible and it is _not_ verified — Dart was aliased to JavaScript on exactly
the same argument, and disagreed on 5 of 247 entries once it was actually
executed. Rather than report copies as independent agreement, they are left out.

**Comparison is on matched substrings, not offsets.** Some runners report
UTF-16 code-unit offsets and others report byte offsets, so offsets are not yet
comparable across engines. Match text is.

**One engine's data was dropped** — a stale `re2.json` with no runner in the
current generator. Go covers the same RE2 engine and is reproducible.

## Reproducing

```bash
node generate-divergences.mjs > DIVERGENCES.md
```

That reads only the committed JSON — no dependencies, no network. Regenerating
the ground truth itself needs all 16 runtimes; `runners/` documents each.

## Contributing

New constructs are welcome, especially ones that produce a **Class A** result.
Open a PR adding to `constructs.json` with recorded output from at least two
engines and the exact commands you ran.

Corrections matter more than additions. If a recorded answer is wrong, that is a
bug — tell us which engine, which version, and what you got instead.

## License

MIT. Use it in your own test suite, your own docs, your own tooling.

## Where this came from

This is the test corpus of [RegexPilot](https://regexpilot.com), a macOS regex
editor that bundles these engines and runs your pattern through the real one
instead of approximating it in JavaScript. The corpus exists because shipping
that claim meant proving it.

The data stands on its own, which is why it is here under MIT.

## Provenance

This repository is a **published snapshot**. The canonical copy of
`constructs.json`, `ground-truth/` and `runners/` lives in RegexPilot's
own test suite, where it is executed by CI on every change.

Snapshot taken from commit `44dbaf06` (`44dbaf06d006b506153ab80bf860f7df7402774f`).

Updates land here as new snapshots rather than as edits, so a figure quoted
from this repo always has a commit behind it. Corrections are still very
welcome as issues or PRs — they are applied upstream and flow back in the
next snapshot.
