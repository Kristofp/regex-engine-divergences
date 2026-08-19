// Swift reference runner — NSRegularExpression (ICU-backed), macOS only.
//
// stdin:  JSON array of {id, pattern, testText, flags}
// stdout: JSON object of {id: {matches: [{match, index}], error}}
//
// Swift has two regex engines:
//   1. `NSRegularExpression` (Foundation, ICU-backed) — what `swift run`
//      exposes on macOS and what the Swift sidecar uses at runtime. THIS
//      is what we want ground truth for.
//   2. `Regex<Output>` (Swift 5.7+, `_RegexParser`) — different syntax
//      and semantics (RegexBuilder DSL).
//
// We deliberately pick NSRegularExpression to match the sidecar, and
// report `index` as UTF-16 code-unit offset (NSRegularExpression's
// native unit) to match the sidecar's offset convention. The test
// harness normalizes units on the JS side.

import Foundation

struct Entry: Codable {
    let id: String
    let pattern: String
    let testText: String
    let flags: String?
}

struct MatchResult: Codable {
    let match: String
    let index: Int
}

struct RunResult: Codable {
    let matches: [MatchResult]
    let error: String?
}

func optionsFromFlags(_ flags: String) -> NSRegularExpression.Options {
    var opts: NSRegularExpression.Options = []
    if flags.contains("i") { opts.insert(.caseInsensitive) }
    if flags.contains("m") { opts.insert(.anchorsMatchLines) }
    if flags.contains("s") { opts.insert(.dotMatchesLineSeparators) }
    if flags.contains("x") { opts.insert(.allowCommentsAndWhitespace) }
    return opts
}

let data = FileHandle.standardInput.readDataToEndOfFile()
guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
    FileHandle.standardError.write("failed to decode input\n".data(using: .utf8)!)
    exit(1)
}

var results: [String: RunResult] = [:]

for e in entries {
    let flags = e.flags ?? ""
    do {
        let rx = try NSRegularExpression(pattern: e.pattern, options: optionsFromFlags(flags))
        let text = e.testText
        let nsrange = NSRange(text.startIndex..., in: text)
        var matches: [MatchResult] = []
        // Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
        // and matches the bridge's behavior.
        rx.enumerateMatches(in: text, options: [], range: nsrange) { result, _, _ in
            guard let r = result else { return }
            let range = r.range
            if let swiftRange = Range(range, in: text) {
                matches.append(MatchResult(match: String(text[swiftRange]), index: range.location))
            }
        }
        results[e.id] = RunResult(matches: matches, error: nil)
    } catch {
        results[e.id] = RunResult(matches: [], error: error.localizedDescription)
    }
}

let out = try JSONEncoder().encode(results)
FileHandle.standardOutput.write(out)
