import json, sys, re

entries = json.load(sys.stdin)
results = {}
for e in entries:
    try:
        f = 0
        flags_str = e.get("flags", "")
        if "i" in flags_str:
            f |= re.IGNORECASE
        if "m" in flags_str:
            f |= re.MULTILINE
        if "s" in flags_str:
            f |= re.DOTALL
        if "x" in flags_str:
            f |= re.VERBOSE
        rx = re.compile(e["pattern"], f)
        # Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
        # and matches the bridge's behavior.
        matches = [
            {"match": m.group(), "index": m.start()}
            for m in rx.finditer(e["testText"])
        ]
        results[e["id"]] = {"matches": matches, "error": None}
    except Exception as ex:
        results[e["id"]] = {"matches": [], "error": str(ex)}
json.dump(results, sys.stdout)
