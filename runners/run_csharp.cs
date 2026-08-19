using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.RegularExpressions;

var input = Console.In.ReadToEnd();
var entries = JsonSerializer.Deserialize<List<Dictionary<string, string>>>(input)!;
var results = new Dictionary<string, object>();

foreach (var e in entries) {
    try {
        var opts = RegexOptions.None;
        var flags = e.ContainsKey("flags") ? e["flags"] : "";
        if (flags.Contains('i')) opts |= RegexOptions.IgnoreCase;
        if (flags.Contains('m')) opts |= RegexOptions.Multiline;
        if (flags.Contains('s')) opts |= RegexOptions.Singleline;
        if (flags.Contains('x')) opts |= RegexOptions.IgnorePatternWhitespace;
        var rx = new Regex(e["pattern"], opts);
        var matches = new List<object>();
        // Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
        // and matches the bridge's behavior.
        foreach (Match m in rx.Matches(e["testText"])) {
            matches.Add(new { match = m.Value, index = m.Index });
        }
        results[e["id"]] = new { matches, error = (string?)null };
    } catch (Exception ex) {
        results[e["id"]] = new { matches = new List<object>(), error = ex.Message };
    }
}
Console.Write(JsonSerializer.Serialize(results));
