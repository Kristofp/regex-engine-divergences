# Where regex engines disagree

Generated from `constructs.json` + `ground-truth/` — do not edit by hand.

- **539** constructs, **16** engines, **534** constructs exercised by at least one engine
- **270** (51%) — every engine agrees
- **21** (4%) — **Class A**: engines return *different* matches, silently
- **160** (30%) — **Class B**: at least one engine matches *nothing*, silently
- **83** (16%) — **Class C**: at least one engine rejects the pattern, loudly

Class C is the safe case: the engine tells you. Classes A and B are the
ones that reach production, because nothing anywhere reports a problem.

## Class A — different matches, no error

A pattern that returns one answer in the engine you tested it in, and a
different answer in the engine you shipped it to.

### `l2-multiline-anchor-group`

Multiline anchors with key=value capture groups

| | |
| --- | --- |
| pattern | `^(\w+)\s*=\s*(.+)$` |
| subject | `key1 = value1\nkey2 = value2\nkey3=value3` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["key1 = value1","key2 = value2","key3=value3"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, python, r, rust, swift |
| _rejects the pattern_ | postgresql |
| `["key1 = value1\nkey2 = value2\nkey3=value3"]` | ruby |
| _no matches_ | shell |

### `l2-anchor-lookahead`

Start anchor with positive lookahead

| | |
| --- | --- |
| pattern | `^(?=.*\d)(\w+)` |
| subject | `abc123\nhello\ntest456` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["abc123","test456"]` | csharp, dart, elixir, java, javascript, mysql, perl, php, python, r, swift |
| _rejects the pattern_ | postgresql, shell |
| `["abc123","hello","test456"]` | ruby |

### `l2-dot-star-group-anchor`

Dot star with capture and end anchor

| | |
| --- | --- |
| pattern | `^.*(\w+)$` |
| subject | `hello world\nfoo bar` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["hello world","foo bar"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, python, r, rust, swift |
| _rejects the pattern_ | postgresql |
| `["hello world\nfoo bar"]` | ruby |
| _no matches_ | shell |

### `l2-scoped-flag-i-alternation`

Case-insensitive scoped flag with alternation

| | |
| --- | --- |
| pattern | `(?i:yes\|no\|maybe)` |
| subject | `YES no MAYBE perhaps` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["YES","no","MAYBE"]` | csharp, elixir, go, java, javascript, mysql, perl, php, python, r, ruby, rust, swift |
| `["YES","no"]` | dart |
| _rejects the pattern_ | postgresql |
| _no matches_ | shell |

### `l2-unicode-group-boundary`

Unicode property with word boundary and group

| | |
| --- | --- |
| pattern | `\b(\p{L}+)\b` |
| subject | `Hello 世界 café 123` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["Hello","世界","café"]` | csharp, perl, php, ruby, rust |
| _rejects the pattern_ | postgresql, python, shell |
| _no matches_ | dart, javascript |
| `["Hello","caf"]` | elixir |

### `l2-log-line`

Log line pattern with timestamp, level, message

| | |
| --- | --- |
| pattern | `^(\d{4}-\d{2}-\d{2})\s+(\w+)\s+(.+)$` |
| subject | `2026-04-12 INFO Starting up\n2026-04-12 ERROR Something failed` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["2026-04-12 INFO Starting up","2026-04-12 ERROR Something failed"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, python, r, rust, swift |
| _rejects the pattern_ | postgresql, shell |
| `["2026-04-12 INFO Starting up\n2026-04-12 ERROR Something failed"]` | ruby |

### `l2-unicode-digit-boundary`

Unicode digit property with word boundary

| | |
| --- | --- |
| pattern | `\b\p{Nd}+\b` |
| subject | `abc 123 def ٤٥٦ ghi` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["123","٤٥٦"]` | csharp, perl, php, ruby, rust |
| _rejects the pattern_ | postgresql, python, shell |
| _no matches_ | dart, javascript |
| `["123"]` | elixir |

### `edge-elixir-unicode-w`

Elixir \\w with Unicode text — Erlang :unicode enables UTF-8 but NOT UCP, so \\w stays ASCII

| | |
| --- | --- |
| pattern | `\w+` |
| subject | `café naïve über` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["café","naïve","über"]` | csharp, perl, php, python |
| `["caf","na","ve","ber"]` | elixir, java, ruby |

### `edge-elixir-unicode-d`

Elixir \\d on non-ASCII digits — Arabic-Indic digits matched by UCP engines but not ASCII-only

| | |
| --- | --- |
| pattern | `\d+` |
| subject | `123 ١٢٣ 456` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["123","١٢٣","456"]` | csharp, perl, php, python |
| `["123","456"]` | elixir, java, r, ruby |

### `edge-r-word-boundary-unicode`

R \\b word boundary on accented text — locale-dependent

| | |
| --- | --- |
| pattern | `\b\w+\b` |
| subject | `café naïve test` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["café","naïve","test"]` | perl, php, python |
| `["caf","na","ve","test"]` | r |

### `edge-python-w-unicode-default`

Python \\w matches Unicode by default (Python 3), PCRE2 needs UCP flag

| | |
| --- | --- |
| pattern | `\w+` |
| subject | `naïve café über` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["naïve","café","über"]` | perl, php, python |
| `["na","ve","caf","ber"]` | java |

### `edge-ruby-h-hex`

Ruby \\h = hex digit [0-9a-fA-F]; PCRE2 \\h = horizontal whitespace — SILENT semantic clash

| | |
| --- | --- |
| pattern | `\h+` |
| subject | `DEAD 00FF xyz` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `[" "," "]` | perl, php |
| `["DEAD","00FF"]` | ruby |

### `edge-ruby-H-nonhex`

Ruby \\H = non-hex; PCRE2 \\H = non-horizontal-whitespace — SILENT semantic clash

| | |
| --- | --- |
| pattern | `\H+` |
| subject | `xyz DEAD 123` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["xyz","DEAD","123"]` | perl, php |
| `["xyz "," "]` | ruby |

### `edge-java-boundary-unicode`

Java \\b with Unicode — uses Character.isLetterOrDigit including accented chars

| | |
| --- | --- |
| pattern | `\b\w+\b` |
| subject | `café naïve test` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["caf","na","ve","test"]` | java |
| `["café","naïve","test"]` | php |

### `l3-lookahead-backref-group`

Lookahead captures a group, then backref uses it

| | |
| --- | --- |
| pattern | `(?=(\w+))\1\s(\w+)` |
| subject | `hello world foo bar` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["hello world","foo bar"]` | csharp, dart, elixir, java, javascript, perl, php, python, r, ruby |
| _rejects the pattern_ | go, postgresql, rust, shell |
| `["world foo"]` | swift |

### `l3-real-csv-quoted`

CSV field: quoted (with escaped quotes) or unquoted

| | |
| --- | --- |
| pattern | `(?:"(?:[^"]\|"")*"\|[^,"\r\n]*)` |
| subject | `hello,\"wo,rld\",\"say \"\"hi\"\"\"` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["hello","","\"wo,rld\"","","\"say \"\"hi\"\"\"",""]` | csharp, dart, elixir, java, javascript, php, postgresql, python, ruby, swift |
| `["hello","\"wo,rld\"","\"say \"\"hi\"\"\""]` | go, rust |
| _rejects the pattern_ | perl |
| _no matches_ | shell |

### `l3-edge-empty-alternation`

Empty alternation branch — empty string matches

| | |
| --- | --- |
| pattern | `(\|a\|b)` |
| subject | `ab` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["","",""]` | csharp, dart, go, java, javascript, ruby, rust, swift |
| `["","a","","b",""]` | elixir |
| _rejects the pattern_ | perl |

### `l3-edge-unicode-boundary`

Unicode word boundary on mixed-script text

| | |
| --- | --- |
| pattern | `\b\p{L}+\b` |
| subject | `hello мир 世界 café` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["hello","мир","世界","café"]` | csharp, perl, php, ruby, rust |
| _rejects the pattern_ | postgresql, python, shell |
| _no matches_ | dart, javascript |
| `["hello","caf"]` | elixir |

### `l3-edge-crlf-multiline`

Multiline dot-star with CRLF line endings

| | |
| --- | --- |
| pattern | `^.+$` |
| subject | `line1\r\nline2\r\nline3` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["line1\r","line2\r","line3"]` | csharp, elixir, go, perl, php, python, r, rust |
| `["line1","line2","line3"]` | dart, javascript |
| _rejects the pattern_ | postgresql |
| `["line1\r\nline2\r\nline3"]` | ruby |

### `l3-edge-backref-in-class-literal`

Backref syntax inside class treated as octal/literal

| | |
| --- | --- |
| pattern | `[\1]` |
| subject | `\u0001 1 a` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["\u0001"]` | csharp, dart, elixir, javascript, perl, php, python, ruby |
| _rejects the pattern_ | go, java, postgresql, rust |
| `["1"]` | shell, swift |

### `class-difference`

Character class difference [a--b] — ICU subtracts, Java/Ruby read -- as a literal dash

| | |
| --- | --- |
| pattern | `[a-z--[aeiou]]+` |
| subject | `abcd` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["bcd"]` | mysql, rust, swift |
| `["abcd"]` | java, ruby |

## Class B — silently matches nothing

Every engine that produced matches agrees with the others. The engines
listed as returning nothing raise no error — the pattern is accepted and
simply finds nothing.

| Engine | Constructs silently matching nothing |
| --- | --- |
| shell | 135 |
| dart | 20 |
| javascript | 11 |
| swift | 4 |
| php | 2 |
| postgresql | 1 |
| python | 1 |
| csharp | 1 |

<details><summary>All Class B constructs</summary>

| Construct | Pattern | Matches nothing in | Everyone else |
| --- | --- | --- | --- |
| `char-class-range` | `[a-z]+` | shell | `["ello","orld","foo"]` |
| `char-class-negated` | `[^0-9]+` | shell | `["abc","def","ghi"]` |
| `char-escape-w` | `\w+` | shell | `["hello","world","123"]` |
| `char-escape-W` | `\W+` | shell | `[" ","! "]` |
| `char-escape-s` | `\s+` | shell | `[" ","\t"]` |
| `char-escape-S` | `\S+` | shell | `["hello","world","123"]` |
| `char-escape-X` | `\X` | dart | `["a","é"," ","ñ"," ","o"]` |
| `char-escape-R` | `\R` | dart | `["\r\n","\n"]` |
| `char-unicode-prop` | `\p{L}+` | dart, javascript | `["Hello","世界","café"]` |
| `char-unicode-prop-neg` | `\P{L}+` | dart, javascript | `[" "," 123 "]` |
| `anchor-start-string` | `\Ahello` | dart | `["hello"]` |
| `anchor-end-string` | `end\Z` | dart, postgresql | `["end"]` |
| `anchor-end-string-only` | `end\z` | dart | `["end"]` |
| `anchor-match-start` | `\G\w+` | dart | `["abc"]` |
| `anchor-match-reset` | `foo\Kbar` | dart, swift | `["bar","bar"]` |
| `group-capturing` | `(foo)(bar)` | shell | `["foobar","foobar"]` |
| `group-named` | `(?<word>\w+)` | shell | `["hello","world"]` |
| `group-noncapturing` | `(?:foo\|bar)baz` | shell | `["foobaz","barbaz"]` |
| `group-atomic` | `(?>ab\|a)b` | shell | `["abb"]` |
| `group-scoped-flags` | `(?i:hello) world` | shell | `["HELLO world","Hello world"]` |
| `lookahead-positive` | `foo(?=bar)` | shell | `["foo"]` |
| `lookahead-negative` | `foo(?!bar)` | shell | `["foo","foo"]` |
| `lookbehind-positive` | `(?<=foo)bar` | shell | `["bar"]` |
| `lookbehind-negative` | `(?<!foo)bar` | shell | `["bar","bar"]` |
| `quant-plus` | `a+` | shell | `["a","aa","aaa"]` |
| `quant-optional` | `colou?r` | shell | `["color","colour"]` |
| `quant-exact` | `a{3}` | shell | `["aaa","aaa"]` |
| `quant-range` | `a{2,4}` | shell | `["aa","aaa","aaaa","aaaa"]` |
| `quant-min` | `a{2,}` | shell | `["aa","aaa","aaaa"]` |
| `quant-lazy` | `a+?` | shell | `["a","a","a","a","a","a"]` |
| `quant-possessive` | `a++b` | shell | `["aab","ab"]` |
| `choice-simple` | `cat\|dog` | shell | `["cat","dog"]` |
| `choice-triple` | `red\|green\|blue` | shell | `["red","blue","green"]` |
| `l2-quantified-group` | `(abc){2,3}` | shell | `["abcabc","abcabcabc"]` |
| `l2-nested-groups` | `(a(b)c)` | shell | `["abc","abc"]` |
| `l2-alternation-in-group` | `(cat\|dog)\s+food` | shell | `["cat food","dog food"]` |
| `l2-quantified-class` | `[a-z]{3,5}` | shell | `["abc","abcde","abcde"]` |
| `l2-negated-class-quantifier` | `[^aeiou]+` | shell | `["h","ll"," w","rld"]` |
| `l2-dot-greedy` | `a.+b` | shell | `["axyzb axxb ab"]` |
| `l2-dot-lazy` | `a.+?b` | shell | `["axb","axxb"]` |
| `l2-anchor-group` | `^(\w+)` | shell | `["hello","foo","baz"]` |
| `l2-anchor-alternation` | `^(foo\|bar)` | shell | `["foo","bar"]` |
| `l2-lookahead-capture` | `(\w+)(?=\s)` | shell | `["hello","world"]` |
| `l2-lookbehind-capture` | `(?<=\s)(\w+)` | shell | `["world","test"]` |
| `l2-alternation-in-lookbehind` | `(?<=cat\|dog)\w+` | shell | `["fish","wood"]` |
| `l2-scoped-flags-class` | `(?i:[a-z])+` | shell | `["Hello","WORLD"]` |
| `l2-scoped-flags-dot` | `(?s:a.b)` | shell | `["a\nb","axb"]` |
| `l2-atomic-quantifier` | `(?>a+)b` | shell | `["aab","ab"]` |
| `l2-unicode-prop-quantifier` | `\p{L}+` | dart, javascript | `["Hello","世界","café"]` |
| `l2-unicode-prop-anchor` | `^\p{Lu}` | dart, javascript | `["H","W"]` |
| `l2-nested-quantifiers` | `(a+)+b` | shell | `["aab","ab"]` |
| `l2-nongreedy-in-group` | `<(.+?)>` | shell | `["<a>","<br>","<div>"]` |
| `l2-class-special-chars` | `[\w.-]+@[\w.-]+` | shell | `["user@example.com","test@foo.bar.org"]` |
| `l2-multiple-named-groups` | `(?<first>\w+)\s+(?<last>\w+)` | shell | `["John Smith","Jane Doe"]` |
| `l2-lookahead-alternation` | `(?=foo\|bar)\w+` | shell | `["foobar","barfoo"]` |
| `l2-possessive-in-group` | `(?>a+)b` | shell | `["aab","ab"]` |
| `l2-match-reset-capture` | `foo\K(\w+)` | dart, swift | `["bar","baz"]` |
| `l2-dotall-multiline` | `^.+$` | shell | `["line1\nline2\nline3"]` |
| `l2-capturing-star` | `(ab)*c` | shell | `["c","abc","ababc"]` |
| `l2-capturing-optional` | `(Mr\|Mrs\|Ms)?\.?\s*(\w+)` | shell | `["Mr. Smith"," Mrs",". Jones"," Alice"]` |
| `l2-named-group-star` | `(?<seg>[a-z]+\.)*(?<tld>[a-z]+)` | shell | `["www.example.com","foo.bar.org","test"]` |
| `l2-noncapturing-plus` | `(?:ab)+` | shell | `["ab","abab","ababab"]` |
| `l2-noncapturing-optional` | `https?://(?:www\.)?\w+\.\w+` | shell | `["http://example.com","https://www.test.org"]` |
| `l2-noncapturing-exact` | `(?:ha){3}` | shell | `["hahaha"]` |
| `l2-noncapturing-range` | `(?:ab){2,4}` | shell | `["abab","ababab","abababab"]` |
| `l2-noncapturing-lazy` | `(?:ab)+?x` | shell | `["abx","ababx","abababx"]` |
| `l2-nested-alternation` | `(a\|b(c\|d))e` | shell | `["ae","bce","bde"]` |
| `l2-flag-combo-is` | `hello.world` | shell | `["hello\nworld","HELLO\nWORLD"]` |
| `l2-unicode-group` | `(\p{L}+)\s+(\p{N}+)` | dart, javascript | `["hello 123","世界 456"]` |
| `l2-word-boundary-group` | `\b(\w{4})\b` | shell | `["over","lazy","dogs"]` |
| `l2-space-boundary-class` | `\S+\s+\S+` | shell | `["hello world","foo bar"]` |
| `l2-lookahead-anchor-end` | `\w+(?!\.)$` | shell | `["world"]` |
| `l2-lookbehind-anchor-start` | `^(?<=^)(\w+)` | shell | `["hello","world"]` |
| `l2-class-union` | `[0-9a-fA-F]+` | shell | `["deadBEEF","0","1A3F"]` |
| `l2-class-escape-in-class` | `[\d\s]+` | shell | `[" 123 "," 456"]` |
| `l2-group-alternation-quantifier` | `(?:ab\|cd){2}` | shell | `["abab","cdcd","abcd","cdab"]` |
| `l2-named-group-quantifier` | `(?<hex>[0-9a-f]){2,4}` | shell | `["ab","abcd","abcd","ef"]` |
| `l2-nested-three-groups` | `((a(b))c)` | shell | `["abc","abc"]` |
| `l2-alternation-different-lengths` | `(?:January\|Feb\|March\|Apr)` | shell | `["January","Feb","March","Apr"]` |
| `l2-anchor-class-quantifier` | `^[A-Z][a-z]+$` | shell | `["Hello","Test"]` |
| `l2-boundary-capture-quantifier` | `\b(\w{3,})\b` | shell | `["the","one","who","tests"]` |
| `l2-unicode-script` | `\p{Cyrillic}+` | dart, javascript | `["Мир","Привет"]` |
| `l2-unicode-category-number` | `\p{N}+` | dart, javascript | `["123","٤٥٦"]` |
| `l2-lookbehind-alternation` | `(?<=Mr\.\|Mrs\.)\s*\w+` | shell | `[" Smith"," Jones"]` |
| `l2-capture-lazy-range` | `(<(\w+?)>)` | shell | `["<div>","<span>","<a>"]` |
| `l2-complex-email` | `([\w.+-]+)@([\w-]+)\.([a-z]{2,})` | shell | `["user@example.com","test+tag@foo.org"]` |
| `l2-hex-color` | `#(?:[0-9a-f]{6}\|[0-9a-f]{3})` | shell | `["#ff0000","#abc","#123"]` |
| `l2-word-nonword-alternation` | `(?:\w+\|\W+)` | shell | `["hello","!!! ","world","??? ","foo"]` |
| `l2-greedy-vs-lazy-star` | `<(.*?)>` | shell | `["<div class=\"x\">","<span>","</div>"]` |
| `l2-noncapturing-nested-alternation` | `(?:(?:un\|re)(?:do\|make))` | shell | `["undo","redo","unmake","remake"]` |
| `l2-lookahead-boundary` | `\b(?=\w{5,})(\w+)\b` | shell | `["quick","brown"]` |
| `l2-lookbehind-class` | `(?<=[A-Z])\w+` | shell | `["ello","orld","BC"]` |
| `l2-capture-class-range-lazy` | `([a-z]{2,5}?)` | shell | `["ab","cd","ef","gh","ij"]` |
| `l2-lookahead-capture-backref` | `(?=(\w{3}))\w` | shell | `["a","b","c","d"]` |
| `l2-anchor-neg-lookahead` | `^(?!#)(.+)$` | shell | `["code line","more code"]` |
| `l2-boundary-alternation-capture` | `\b(cat\|dog\|bird)s?\b` | shell | `["cats","dogs","bird"]` |
| `l2-escape-sequence-in-class` | `[\w\d\s]+` | shell | `["hello 123 world"," foo"]` |
| `l2-optional-capture-in-sequence` | `(\w+)\s*(=)\s*(\w+)(?:\s*;)?` | shell | `["x = 5;","y = 10;","z = 15"]` |
| `l2-class-negated-quantifier-anchor` | `^[^#\n]+$` | shell | `["code line","more code"]` |
| `l2-dot-class-alternation` | `(?:.+@[\w.]+\|\bN/A\b)` | shell | `["user@test.com N/A foo@bar.org"]` |
| `l2-multiple-flag-scopes` | `(?i:hello)\s+(?i:world)` | shell | `["HELLO WORLD","hello world","HeLLo WoRLd"]` |
| `l2-capture-unicode-named` | `(?<letters>\p{L}+)(?<digits>\p{N}+)` | dart, javascript | `["abc123","hello456"]` |
| `l2-lookbehind-neg-class` | `(?<=[a-z])[^a-z]+` | shell | `[" 123 "," 456"]` |
| `l2-double-negated-class` | `[^\W]+` | shell | `["hello","world","123"]` |
| `l2-csv-field` | `(?:"([^"]*)"\|([^,]+))` | shell | `["\"hello\"","world","\"foo,bar\"","baz"]` |
| `l2-url-parts` | `(https?)://([\w.-]+)(/[\w./]*)?` | shell | `["http://example.com/path","https://www.test.org"]` |
| `l2-quantifier-zero-max` | `a{0,3}b` | shell | `["b","ab","aab","aaab","aaab"]` |
| `l2-lookbehind-lookahead` | `(?<=\[)\w+(?=\])` | shell | `["hello","test","foo"]` |
| `l2-boundary-neg-lookahead` | `\b(?!the\b)\w+\b` | shell | `["quick","brown","fox","jumps","over","lazy","dog"]` |
| `l2-class-dot-alternation-quantifier` | `(?:[a-z]+\.)+(?:com\|org\|net)` | shell | `["www.example.com","foo.bar.org","test.net"]` |
| `l2-possessive-group-class` | `(?>\w+)\s` | shell | `["hello ","world ","foo "]` |
| `edge-python-Z-trailing-newline` | `end\Z` | python | `["end"]` |
| `edge-java-intersection` | `[a-z&&[^aeiou]]+` | php | `["h","ll","w","rld","r","g","x"]` |
| `edge-csharp-class-subtraction` | `[a-z-[aeiou]]+` | php | `["h","ll","w","rld","r","g","x"]` |
| `edge-csharp-connector-boundary` | `\bx` | csharp | `["x"]` |
| `l3-atomic-alternation-quantifier` | `(?>(?:ab\|cd)+)ef` | shell | `["ababef","cdcdef","abef"]` |
| `l3-scoped-flag-lookahead-class` | `(?i:(?=[a-z])\w+)` | shell | `["Hello","WORLD","foo"]` |
| `l3-unicode-prop-lookaround-quantifier` | `(?<=\p{L})\d+(?=\p{L})` | dart, javascript | `["123","45","6"]` |
| `l3-quantified-alt-lookbehind` | `(?<=(?:Mr\|Mrs\|Dr)\.\s)\w+` | shell | `["Smith","Jones","Who"]` |
| `l3-class-boundary-group-quantifier` | `\b([A-Z][a-z]+){2,}\b` | shell | `["JavaScript","RegexPilot","FooBarBaz"]` |
| `l3-lookbehind-negated-class-anchor` | `(?<=@)[^.]+$` | shell | `["domain"]` |
| `l3-nested-quantifiers-group` | `^(?:\w+\s?)+$` | shell | `["hello world foo"]` |
| `l3-lookbehind-unicode-capture` | `(?<=\p{Lu})(\p{Ll}+)` | dart, javascript | `["ello","orld","afé"]` |
| `l3-dot-flag-group-quant` | `(?s:(.{3,5})\s)` | shell | `["ab\ncd ","efgh\n"]` |
| `l3-noncap-nested-alternation` | `(?:(?:(?:a\|b)c\|de)f\|gh)` | shell | `["acf","bcf","def","gh"]` |
| `l3-lookahead-boundary-quantifier` | `\b(?=[A-Z])\w{3,}\b` | shell | `["Hello","World","JavaScript"]` |
| `l3-capture-lazy-alternation` | `((?:foo\|bar)+?)(baz)` | shell | `["foobarbaz","foobaz"]` |
| `l3-negated-lookahead-class-quant` | `\b(?!un)[a-z]+ed\b` | shell | `["fixed","played","coded"]` |
| `l3-lookahead-lookbehind-capture` | `(?<=\()([^)]+)(?=\))` | shell | `["hello","world"]` |
| `l3-flag-multiline-lookahead` | `^(?=\S)\w+` | shell | `["hello","foo"]` |
| `l3-conditional-named-group-quant` | `(?<tag><)?\w+(?(tag)>)` | shell | `["<html>","plain","<div>"]` |
| `l3-unicode-script-lookahead-quant` | `\p{Script=Latin}+(?=\s)` | dart, javascript | `["hello","world","café"]` |
| `l3-capture-inside-lookahead-reuse` | `(?=(cat\|dog))\w+s` | shell | `["cats","dogs"]` |
| `l3-nested-noncap-quant-lazy` | `(?:(?:\w+?)\s){2,3}` | shell | `["a bb ccc "]` |
| `l3-named-alt-quantifier-anchor` | `^(?<proto>https?\|ftp)://\S+$` | shell | `["https://example.com"]` |
| `l3-lookbehind-dot-quantifier` | `(?<=\.).{1,5}(?=\.)` | shell | `["hello","b.xy"]` |
| `l3-capture-nested-quantifiers` | `((\w+)\s?)+` | shell | `["hello world foo"]` |
| `l3-real-email-lookahead` | `(?=[^@]*[A-Z])[\w.+-]+@[\w-]+\.[\w.]+` | shell | `["User@test.com","bad@x.co","Ok@y.io"]` |
| `l3-real-url-optional` | `(?:https?://)?(?:[\w-]+\.)+[a-z]{2,}(?:/[\w./-]*)?(?:\?[\w=&]*)?` | shell | `["https://foo.com/p?a=1","bar.io"]` |
| `l3-real-html-attr` | `(\w+)=["']([^"']*)["']` | shell | `["class=\"foo\"","id='bar'","x=\"z\""]` |
| `l3-real-css-color` | `#(?:[0-9a-fA-F]{3}){1,2}\b` | shell | `["#fff","#aabbcc","#123","#DEAD00"]` |
| `l3-real-json-string` | `"(?:[^"\\]\|\\.)*"` | shell | `["\"hello\"","\"say \\\"hi\\\"\"","\"a\\nb\""]` |
| `l3-real-markdown-link` | `\[([^\]]+)\]\(([^)]+)\)` | shell | `["[click](http://x.co)","[go](y.io)"]` |
| `l3-real-hex-color-named` | `#(?<r>[0-9a-f]{2})(?<g>[0-9a-f]{2})(?<b>[0-9a-f]{2})\b` | shell | `["#ff00cc","#aabb11","#123456"]` |
| `l3-real-camel-to-words` | `(?<=[a-z])(?=[A-Z])` | shell | `["","",""]` |
| `l3-real-xml-tag` | `<(\w+)(\s+\w+="[^"]*")*\s*/?>` | shell | `["<div class=\"x\">","<br/>","<img src=\"y\"/>"]` |
| `l3-real-uuid` | `[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}` | shell | `["550e8400-e29b-41d4-a716-446655440000"]` |
| `l3-real-content-type` | `(\w+/\w+)(?:;\s*charset=([\w-]+))?` | shell | `["text/html; charset=utf-8","app/json"]` |
| `l3-edge-overlapping-capture` | `(?=(a+))\1b` | swift | `["aab"]` |
| `l3-edge-nested-quantifier` | `(a+)+b` | shell | `["aab"]` |
| `l3-edge-alternation-capture-counts` | `(a)(b)\|(c)` | shell | `["ab"]` |
| `l3-edge-case-folding-eszett` | `stra(ss\|ß)e` | shell | `["strasse","straße"]` |
| `l3-edge-possessive-no-backtrack` | `"[^"]*+"x` | shell | `["\"hello\"x"]` |
| `l3-edge-K-with-captures` | `a\K(b)(c)` | dart, swift | `["bc"]` |
| `l3-edge-variable-lookbehind` | `(?<=\w{1,10})x` | shell | `["x","x"]` |
| `l3-edge-greedy-vs-lazy-capture` | `"(.*?)".*"(.*)"` | shell | `["\"first\" and \"second\""]` |
| `l3-edge-nested-class-escape` | `[\]\[^-]+` | shell | `["]","[","^","-"]` |
| `l3-edge-lookahead-at-end` | `\w+(?=\s*$)` | shell | `["world"]` |
| `l3-edge-multiline-first-line` | `^\w+` | shell | `["hello","world","foo"]` |
| `l3-edge-catastrophic-avoided` | `(x+x+)+y` | shell | `["xxxy"]` |

</details>

## Class C — rejected outright

Listed for completeness. These are safe: the engine refuses the pattern,
so you find out at once rather than in production.

<details><summary>All Class C constructs</summary>

| Construct | Pattern | Rejected by |
| --- | --- | --- |
| `char-escape-d` | `\d+` | shell |
| `char-escape-D` | `\D+` | shell |
| `anchor-start` | `^hello` | postgresql |
| `anchor-end` | `world$` | postgresql |
| `backref-numbered` | `(a\|b)\1` | postgresql, shell |
| `backref-named` | `(?<ch>a\|b)\k<ch>` | postgresql, python, shell |
| `cond-named` | `(?<x>a)?(?(x)b\|c)` | perl, python |
| `l2-nested-named-groups` | `(?<outer>(?<inner>\d+)\w+)` | postgresql, python, shell |
| `l2-group-backref` | `(a\|b)\1+` | postgresql, shell |
| `l2-nested-lookaround` | `(?=.*(?<=\d))\w+` | shell |
| `l2-digit-boundary` | `\b\d+\b` | shell |
| `l2-multiple-captures` | `(\d{2})-(\d{2})-(\d{4})` | shell |
| `l2-escaped-special` | `\$\d+\.\d{2}` | shell |
| `l2-backref-in-alternation` | `(a)\1\|(b)\2` | postgresql, shell |
| `l2-named-backref-conditional` | `(?<x>a)?(?(x)yes\|no)` | perl, python |
| `l2-lookbehind-quantifier` | `(?<=\d{2})\w+` | shell |
| `l2-possessive-class` | `[a-z]++\d` | csharp, dart, postgresql, shell |
| `l2-unicode-case-insensitive` | `(?i)\p{L}+` | dart, javascript, postgresql, python, shell |
| `l2-lookahead-backref` | `(?=(\w+)).*\1` | postgresql, shell |
| `l2-anchor-lookbehind` | `(?<=\d)\w*$` | postgresql, shell |
| `l2-multiple-backrefs` | `(\w)(\w)\2\1` | postgresql, shell |
| `l2-flag-combo-im` | `^hello` | postgresql |
| `l2-digit-boundary-group` | `\b(\d+)\b` | shell |
| `l2-capturing-alternation-backref` | `\b(\w+)\s+\1\b` | postgresql, shell |
| `l2-double-lookahead` | `(?=.*[A-Z])(?=.*\d)\w+` | shell |
| `l2-neg-lookahead-neg-lookbehind` | `(?<!\d)\w+(?!\d)` | shell |
| `l2-class-literal-special` | `[\]\-^]+` | shell |
| `l2-group-backref-named` | `(?<quote>['"]).*?\k<quote>` | postgresql, python, shell |
| `l2-lookahead-quantified-group` | `(?=\d)(?:\d{3}-?){2}\d{4}` | shell |
| `l2-alternation-capture-star` | `(\d{1,3}\.){3}\d{1,3}` | shell |
| `l2-named-groups-alternation` | `(?:(?<year>\d{4})-(?<month>\d{2})\|(?<month2>\d{2})/(?<year2>\d{4}))` | postgresql, python, shell |
| `l2-backref-in-quantified-group` | `(['"])(\w+)\1` | postgresql, shell |
| `l2-neg-lookahead-class` | `\d+(?![\d.])` | shell |
| `l2-group-star-anchor-end` | `(?:\d+\.)+\d+$` | postgresql, shell |
| `l2-triple-capture-backref` | `(\w)(\w)(\w)\1` | postgresql, shell |
| `l2-neg-lookbehind-capture` | `(?<!\d)(\w+)` | shell |
| `l2-digit-class-quantifier-group` | `(\d{3})[-.\s]?(\d{3})[-.\s]?(\d{4})` | shell |
| `l2-nested-quantifier-class` | `([a-z]+\d+)+` | shell |
| `l2-lookahead-class-quantifier` | `(?=.*\d)[\w]{8,}` | shell |
| `l2-backref-alternation-group` | `(\w)(?:\1{2}\|\w{2})` | postgresql, shell |
| `l2-anchor-backref` | `^(\w).*\1$` | postgresql, shell |
| `l2-time-pattern` | `(\d{1,2}):(\d{2})(?::(\d{2}))?` | shell |
| `l2-version-number` | `(\d+)\.(\d+)(?:\.(\d+))?` | shell |
| `l2-html-tag-pair` | `<(\w+)>[^<]*</\1>` | postgresql, shell |
| `l2-non-backtracking-group` | `(?>\d+)\.` | dart, postgresql, shell |
| `l2-lookahead-lookahead` | `(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{6,}` | shell |
| `l2-lookahead-optional-capture` | `(?=(\d+)?)\w+` | shell |
| `l2-named-group-alternation-backref` | `(?<delim>[\|/])\w+\k<delim>` | postgresql, python, shell |
| `edge-python-duplicate-name-error` | `(?P<a>x)(?P<a>y)` | php, python |
| `edge-ruby-absent-operator` | `(?~abc)` | php |
| `edge-ruby-duplicate-names` | `(?<a>.)(?<a>.)` | php |
| `edge-perl-K-lookbehind` | `(?<=a\K)b` | perl |
| `edge-php-duplicate-J` | `(?J)(?<n>a)\|(?<n>b)` | perl |
| `l3-nested-lookaround-capture` | `(?<=(?=\d)\w)x` | ruby, shell |
| `l3-backref-alternation-anchor` | `^(a\|b)\1$` | go, postgresql, rust, shell |
| `l3-named-group-flag-backref` | `(?<w>(?i:\w+))\s+\k<w>` | go, postgresql, python, rust, shell |
| `l3-multiple-lookaround` | `(?<=\d)(?=\w)(?!_)\w+` | go, rust, shell |
| `l3-nested-groups-multi-capture` | `((a)(b(c)))\1\2\3\4` | go, postgresql, rust, shell |
| `l3-lookahead-lazy-quant-class` | `(?=[A-Z])\w+?\d` | go, rust, shell |
| `l3-group-alternation-escape` | `(?<sep>\t\|\s)\w+\k<sep>` | go, postgresql, python, rust, shell |
| `l3-lookahead-capture-quantified` | `(?=(\d{2,4}))\d+` | go, rust, shell |
| `l3-word-boundary-class-backref` | `\b([a-z]+)\s+\1\b` | go, postgresql, rust, shell |
| `l3-multiple-named-groups-backref` | `(?<first>\w+):(?<second>\w+)=\k<first>-\k<second>` | go, postgresql, python, rust, shell |
| `l3-possessive-class-anchor` | `^[a-z]++\d$` | csharp, dart, postgresql, shell |
| `l3-alternation-anchor-escape` | `(?:^\d+$\|^\w+\s\w+$)` | postgresql, shell |
| `l3-atomic-backref-anchor` | `^(?>(.))\1$` | dart, postgresql, shell |
| `l3-negated-lookbehind-class-boundary` | `(?<!\d)[a-z]+\b` | go, rust, shell |
| `l3-flag-x-comment-group` | `(?x: (\d+) \s+ (\w+) )` | dart, go, postgresql, shell |
| `l3-alternation-backref-lazy` | `(a\|b)\w+?\1` | go, postgresql, rust, shell |
| `l3-escape-quant-group-anchor` | `^(\d{1,3}\.){3}\d{1,3}$` | shell |
| `l3-lookahead-negated-class-escape` | `(?=.*\d)[^\s]+` | go, rust, shell |
| `l3-real-date-validation` | `(?:0[1-9]\|[12]\d\|3[01])[-/](?:0[1-9]\|1[0-2])[-/](?:19\|20)\d{2}` | shell |
| `l3-real-ipv4-octet` | `(?:(?:25[0-5]\|2[0-4]\d\|[01]?\d?\d)\.){3}(?:25[0-5]\|2[0-4]\d\|[01]?\d?\d)` | shell |
| `l3-real-password-strength` | `(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[!@#$%]).{8,}` | go, rust, shell |
| `l3-real-log-named-groups` | `(?<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\s+(?<level>INFO\|WARN\|ERROR)\s+(?<msg>.+)` | postgresql, python, shell |
| `l3-real-semver` | `(\d+)\.(\d+)\.(\d+)(?:-(\w+(?:\.\w+)*))?(?:\+(\w+(?:\.\w+)*))?` | shell |
| `l3-real-time-12h` | `(?:0?[1-9]\|1[0-2]):[0-5]\d\s?(?:AM\|PM\|am\|pm)` | shell |
| `l3-real-phone-intl` | `(?:\+\d{1,3}[-.\s]?)?(?:\(\d{1,4}\)[-.\s]?)?\d{3,4}[-.\s]?\d{3,4}` | shell |
| `l3-real-duplicate-words` | `\b(\w+)\s+\1\b` | go, postgresql, rust, shell |
| `l3-edge-zero-width-quantified` | `(?:(?=\d))+\d+` | go, rust, shell |
| `l3-edge-backref-nonparticipating` | `(a)?(b)\1` | go, postgresql, rust, shell |
| `l3-edge-atomic-no-backtrack` | `(?>a+)ab` | dart, postgresql |
| `l3-edge-empty-capture-backref` | `(a?)b\1` | go, postgresql, rust, shell |

</details>

## Engine coverage

Not every construct is exercised on every engine — many are written to
probe one flavor's specific behaviour.

| Engine | Constructs exercised |
| --- | --- |
| csharp | 281 |
| dart | 270 |
| elixir | 260 |
| go | 180 |
| java | 274 |
| javascript | 247 |
| mysql | 240 |
| perl | 302 |
| php | 306 |
| postgresql | 258 |
| python | 257 |
| r | 254 |
| ruby | 273 |
| rust | 201 |
| shell | 266 |
| swift | 251 |
