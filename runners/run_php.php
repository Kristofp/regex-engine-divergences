<?php
// preg_* emits E_WARNING on an invalid pattern, and that warning carries the
// ONLY specific description of what was wrong — `preg_last_error()` returns
// PREG_INTERNAL_ERROR for every compile failure alike.
//
// This used to be `error_reporting(0)`, which kept the warning off stdout (it
// would corrupt the JSON the orchestrator parses) but also THREW AWAY the
// reason. Measured 2026-09-11: 2,821 of the php column's 7,000 entries — 40%
// — were recorded as the single string "PCRE internal error", which says only
// "something was wrong" about 2,821 different things.
//
// A handler captures the warning text instead of printing it: stdout stays
// clean AND the reason survives. Returning true tells PHP the warning is
// handled, so nothing reaches the output stream.
$lastWarning = null;
set_error_handler(function ($severity, $message) use (&$lastWarning) {
    // `preg_match_all(): ` prefixes every one of these and adds nothing.
    $lastWarning = preg_replace('/^preg_[a-z_]+\(\): /', '', $message);
    return true;
});
error_reporting(E_ALL);
$input = file_get_contents('php://stdin');
$entries = json_decode($input, true);
$results = [];

$errorNames = [
    PREG_NO_ERROR => null,
    PREG_INTERNAL_ERROR => 'PCRE internal error',
    PREG_BACKTRACK_LIMIT_ERROR => 'Backtrack limit exceeded',
    PREG_RECURSION_LIMIT_ERROR => 'Recursion limit exceeded',
    PREG_BAD_UTF8_ERROR => 'Bad UTF-8',
    PREG_BAD_UTF8_OFFSET_ERROR => 'Bad UTF-8 offset',
    PREG_JIT_STACKLIMIT_ERROR => 'JIT stack limit exceeded',
];

foreach ($entries as $e) {
    try {
        $flags = $e['flags'] ?? '';
        $mods = '';
        if (strpos($flags, 'i') !== false) $mods .= 'i';
        if (strpos($flags, 'm') !== false) $mods .= 'm';
        if (strpos($flags, 's') !== false) $mods .= 's';
        if (strpos($flags, 'x') !== false) $mods .= 'x';
        $mods .= 'u'; // always UTF-8
        $pattern = '/' . str_replace('/', '\\/', $e['pattern']) . '/' . $mods;
        // Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
        // and matches the bridge's behavior.
        $matches = [];
        // NOT `@preg_match_all`: the `@` operator suppresses the warning before
        // the handler above can see it, which would put the reason back in the
        // bin. The handler is what keeps stdout clean.
        $lastWarning = null;
        $ret = preg_match_all($pattern, $e['testText'], $m, PREG_OFFSET_CAPTURE);
        $err = preg_last_error();
        if ($err !== PREG_NO_ERROR) {
            // Prefer the warning's own words; fall back to the generic name so a
            // runtime limit (backtrack/recursion, which carries no warning) is
            // still reported rather than swallowed.
            $generic = $errorNames[$err] ?? "PCRE error $err";
            $results[$e['id']] = [
                'matches' => [],
                'error' => $lastWarning !== null ? $lastWarning : $generic,
            ];
            continue;
        }
        if ($ret !== false) {
            foreach ($m[0] as $match) {
                $matches[] = ['match' => $match[0], 'index' => $match[1]];
            }
        }
        // Check for compile errors (preg_match returns false on invalid pattern)
        if ($ret === false && preg_last_error() === PREG_NO_ERROR) {
            $results[$e['id']] = [
                'matches' => [],
                'error' => $lastWarning !== null ? $lastWarning : 'Pattern compilation failed',
            ];
            continue;
        }
        $results[$e['id']] = ['matches' => $matches, 'error' => null];
    } catch (\Throwable $ex) {
        $results[$e['id']] = ['matches' => [], 'error' => $ex->getMessage()];
    }
}
echo json_encode($results);
