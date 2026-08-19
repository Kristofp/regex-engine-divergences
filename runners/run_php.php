<?php
// Suppress warnings to stdout — preg_* functions emit E_WARNING on
// invalid patterns, which corrupts the JSON output the orchestrator
// expects. Errors are caught via preg_last_error() instead.
error_reporting(0);
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
        $ret = @preg_match_all($pattern, $e['testText'], $m, PREG_OFFSET_CAPTURE);
        $err = preg_last_error();
        if ($err !== PREG_NO_ERROR) {
            $results[$e['id']] = ['matches' => [], 'error' => $errorNames[$err] ?? "PCRE error $err"];
            continue;
        }
        if ($ret !== false) {
            foreach ($m[0] as $match) {
                $matches[] = ['match' => $match[0], 'index' => $match[1]];
            }
        }
        // Check for compile errors (preg_match returns false on invalid pattern)
        if ($ret === false && preg_last_error() === PREG_NO_ERROR) {
            $results[$e['id']] = ['matches' => [], 'error' => 'Pattern compilation failed'];
            continue;
        }
        $results[$e['id']] = ['matches' => $matches, 'error' => null];
    } catch (\Throwable $ex) {
        $results[$e['id']] = ['matches' => [], 'error' => $ex->getMessage()];
    }
}
echo json_encode($results);
