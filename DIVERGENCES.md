# Where regex engines disagree

Generated from `constructs.json` + `ground-truth/` — do not edit by hand.

**626** constructs, **16** engines. **620** constructs have an answer;
**298** of them ran on one engine only (most probe one language's own
feature) and have nothing to be compared with. The other **322** ran on two or
more engines, and every figure below is out of those:

- **34** (11%) — every engine agrees
- **41** (13%) — **Class A**: engines return *different* matches, silently
- **224** (70%) — **Class B**: at least one engine matches *nothing*, silently
- **23** (7%) — **Class C**: at least one engine rejects the pattern, loudly

Class C is the safe case: the engine tells you. Classes A and B are the
ones that reach production, because nothing anywhere reports a problem.

178 of the 224 Class B constructs are silent only in `shell` (BSD grep),
which lacks the feature and says nothing. Discount those and
110 constructs still diverge, 87 of them silently.

Each language is counted once, with the engine it uses out of the box. The
engines and tools you can opt into instead are compared with that default
in [Alternative engines and tools](#alternative-engines-and-tools).

The constructs were written to find differences: edge cases, known quirks,
one feature at a time. The shares above describe this corpus, not how often
an everyday regex breaks when it moves between languages.

## Class A — different matches, no error

A pattern that returns one answer in the engine you tested it in, and a
different answer in the engine you shipped it to.

### `anchor-start`

Start of line anchor ^

| | |
| --- | --- |
| pattern | `^hello` |
| subject | `hello world\nhello again\nbye` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["hello","hello"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, shell, swift |
| `["hello"]` | r-tre |

### `l2-anchor-group`

Start anchor with capturing group in multiline

| | |
| --- | --- |
| pattern | `^(\w+)` |
| subject | `hello world\nfoo bar\nbaz` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["hello","foo","baz"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["hello"]` | r-tre |
| _no matches_ | shell |

### `l2-anchor-alternation`

Start anchor with alternation in multiline

| | |
| --- | --- |
| pattern | `^(foo\|bar)` |
| subject | `foo first\nbar second\nbaz third` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["foo","bar"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["foo"]` | r-tre |
| _no matches_ | shell |

### `l2-multiline-anchor-group`

Multiline anchors with key=value capture groups

| | |
| --- | --- |
| pattern | `^(\w+)\s*=\s*(.+)$` |
| subject | `key1 = value1\nkey2 = value2\nkey3=value3` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["key1 = value1","key2 = value2","key3=value3"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, rust, swift |
| `["key1 = value1\nkey2 = value2\nkey3=value3"]` | r-tre, ruby |
| _no matches_ | shell |

### `l2-dotall-multiline`

Dot-all + multiline flags combined

| | |
| --- | --- |
| pattern | `^.+$` |
| subject | `line1\nline2\nline3` |
| flags | `gms` |

| Result | Engines |
| --- | --- |
| `["line1\nline2\nline3"]` | csharp, dart, elixir, go, java, javascript, perl, php, python, r-tre, ruby, rust, swift |
| `["line1","line2","line3"]` | postgresql |
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
| `["abc123","test456"]` | csharp, dart, elixir, java, javascript, mysql, perl, php, postgresql, python, swift |
| _rejects the pattern_ | r-tre |
| `["abc123","hello","test456"]` | ruby |
| _no matches_ | shell |

### `l2-flag-combo-im`

Case-insensitive + multiline flag combination

| | |
| --- | --- |
| pattern | `^hello` |
| subject | `HELLO world\nhello there\nHeLLo again` |
| flags | `gim` |

| Result | Engines |
| --- | --- |
| `["HELLO","hello","HeLLo"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, shell, swift |
| `["HELLO"]` | r-tre |

### `l2-class-escape-in-class`

Shorthand escape inside character class

| | |
| --- | --- |
| pattern | `[\d\s]+` |
| subject | `abc 123 def 456` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `[" 123 "," 456"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["d"]` | r-tre |
| _no matches_ | shell |

### `l2-dot-star-group-anchor`

Dot star with capture and end anchor

| | |
| --- | --- |
| pattern | `^.*(\w+)$` |
| subject | `hello world\nfoo bar` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["hello world","foo bar"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, rust, swift |
| `["hello world\nfoo bar"]` | r-tre, ruby |
| _no matches_ | shell |

### `l2-group-star-anchor-end`

Repeated group before end anchor

| | |
| --- | --- |
| pattern | `(?:\d+\.)+\d+$` |
| subject | `1.2.3.4\n10.20.30` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["1.2.3.4","10.20.30"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["10.20.30"]` | r-tre |
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
| `["YES","no","MAYBE"]` | csharp, elixir, go, java, javascript, mysql, perl, php, python, r-tre, ruby, rust, swift |
| `["YES","no"]` | dart |
| _rejects the pattern_ | postgresql |
| _no matches_ | shell |

### `l2-digit-class-quantifier-group`

Digit class in group with quantifier — phone number pattern

| | |
| --- | --- |
| pattern | `(\d{3})[-.\s]?(\d{3})[-.\s]?(\d{4})` |
| subject | `555-123-4567 555.987.6543 555 111 2222` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["555-123-4567","555.987.6543","555 111 2222"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["555-123-4567","555.987.6543"]` | r-tre |
| _no matches_ | shell |

### `l2-escape-sequence-in-class`

Multiple escape sequences in character class

| | |
| --- | --- |
| pattern | `[\w\d\s]+` |
| subject | `hello 123 world!!! foo` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["hello 123 world"," foo"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["w","d"]` | r-tre |
| _no matches_ | shell |

### `l2-dot-class-alternation`

Dot, character class, and alternation combined

| | |
| --- | --- |
| pattern | `(?:.+@[\w.]+\|\bN/A\b)` |
| subject | `user@test.com N/A foo@bar.org hello` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["user@test.com N/A foo@bar.org"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["N/A"]` | r-tre |
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
| _no matches_ | dart, javascript, shell |
| _rejects the pattern_ | postgresql, python |
| `["Hello","caf"]` | elixir |

### `l2-double-negated-class`

Double negation — negated class containing negated escape

| | |
| --- | --- |
| pattern | `[^\W]+` |
| subject | `hello world! 123` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["hello","world","123"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["hello world! 123"]` | r-tre |
| _no matches_ | shell |

### `l2-log-line`

Log line pattern with timestamp, level, message

| | |
| --- | --- |
| pattern | `^(\d{4}-\d{2}-\d{2})\s+(\w+)\s+(.+)$` |
| subject | `2026-04-12 INFO Starting up\n2026-04-12 ERROR Something failed` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["2026-04-12 INFO Starting up","2026-04-12 ERROR Something failed"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, rust, swift |
| `["2026-04-12 INFO Starting up\n2026-04-12 ERROR Something failed"]` | r-tre, ruby |
| _no matches_ | shell |

### `l2-url-parts`

URL pattern with protocol, host, path groups

| | |
| --- | --- |
| pattern | `(https?)://([\w.-]+)(/[\w./]*)?` |
| subject | `http://example.com/path https://www.test.org` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["http://example.com/path","https://www.test.org"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["https://www."]` | r-tre |
| _no matches_ | shell |

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
| _no matches_ | dart, javascript, shell |
| _rejects the pattern_ | postgresql, python |
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
| `["123","456"]` | elixir, java, r-tre, ruby |

### `edge-r-dot-newline`

R dot vs newline without s flag

| | |
| --- | --- |
| pattern | `.+` |
| subject | `line1\nline2` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["line1","line2"]` | perl, php, python |
| `["line1\nline2"]` | r-tre |

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
| `["hello world","foo bar"]` | csharp, dart, elixir, java, javascript, perl, php, python, ruby |
| _rejects the pattern_ | go, postgresql, r-tre, rust, shell |
| `["world foo"]` | swift |

### `l3-branch-reset-conditional`

Branch reset + conditional backref (Perl 5.44 tests the reset group 1 in either branch: 2 matches)

| | |
| --- | --- |
| pattern | `(?\|(\d+)\|(\w+))(?(1)=num\|=word)` |
| subject | `123=num abc=word` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["123=num","abc=word"]` | perl |
| `["123=num"]` | php |

### `l3-nested-noncap-quant-lazy`

Nested non-capturing groups with mixed greedy/lazy quantifiers

| | |
| --- | --- |
| pattern | `(?:(?:\w+?)\s){2,3}` |
| subject | `a bb ccc dddd eeeee` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["a bb ccc "]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["a bb ","ccc dddd "]` | r-tre |
| _no matches_ | shell |

### `l3-real-csv-quoted`

CSV field: quoted (with escaped quotes) or unquoted

| | |
| --- | --- |
| pattern | `(?:"(?:[^"]\|"")*"\|[^,"\r\n]*)` |
| subject | `hello,\"wo,rld\",\"say \"\"hi\"\"\"` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["hello","","\"wo,rld\"","","\"say \"\"hi\"\"\"",""]` | csharp, dart, elixir, java, javascript, perl, php, postgresql, python, ruby, swift |
| `["hello","\"wo,rld\"","\"say \"\"hi\"\"\""]` | go, rust |
| _no matches_ | shell |

### `l3-real-phone-intl`

International phone number with optional country code

| | |
| --- | --- |
| pattern | `(?:\+\d{1,3}[-.\s]?)?(?:\(\d{1,4}\)[-.\s]?)?\d{3,4}[-.\s]?\d{3,4}` |
| subject | `+1-555-1234 (020) 555-6789` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["+1-555-1234","(020) 555-6789"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["+1-555-1234","555-6789"]` | r-tre |
| _no matches_ | shell |

### `l3-real-content-type`

HTTP Content-Type with optional charset parameter

| | |
| --- | --- |
| pattern | `(\w+/\w+)(?:;\s*charset=([\w-]+))?` |
| subject | `text/html; charset=utf-8 app/json` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["text/html; charset=utf-8","app/json"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["text/html","app/json"]` | r-tre |
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
| `["","a","","b",""]` | elixir, perl |

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
| _no matches_ | dart, javascript, shell |
| _rejects the pattern_ | postgresql, python |
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
| `["line1\r","line2\r","line3"]` | csharp, elixir, go, perl, php, postgresql, python, rust |
| `["line1","line2","line3"]` | dart, javascript |
| `["line1\r\nline2\r\nline3"]` | r-tre, ruby |

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

### `l3-edge-multiline-first-line`

Multiline ^ matches each line start

| | |
| --- | --- |
| pattern | `^\w+` |
| subject | `hello\nworld\nfoo` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["hello","world","foo"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["hello"]` | r-tre |
| _no matches_ | shell |

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

### `lib-windows-path`

Windows drive-letter path with backslash separators

| | |
| --- | --- |
| pattern | `[A-Za-z]:\\(?:[^\\/:*?"<>\|\r\n]+\\)*[^\\/:*?"<>\|\r\n]*` |
| subject | `open C:\\Users\\kris\\notes.txt now` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["C:\\Users\\kris\\notes.txt now"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["C:\\Use"]` | r-tre |
| _no matches_ | shell |

### `lib-line-comment-double-slash`

C-style line comment to end of line

| | |
| --- | --- |
| pattern | `//[^\n]*` |
| subject | `let x = 1; // set x\nlet y = 2; // and y` |
| flags | `g` |

| Result | Engines |
| --- | --- |
| `["// set x","// and y"]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| `["// set x\nlet y = 2; // a"]` | r-tre |
| `["// set x","// a"]` | shell |

### `lib-blank-or-whitespace-line`

Blank or whitespace-only line

| | |
| --- | --- |
| pattern | `^[ \t]*$` |
| subject | `one\n\n   \ntwo` |
| flags | `gm` |

| Result | Engines |
| --- | --- |
| `["","   "]` | csharp, dart, elixir, go, java, javascript, mysql, perl, php, postgresql, python, ruby, rust, swift |
| _no matches_ | r-tre |
| `["   "]` | shell |

## Class B — silently matches nothing

Every engine that produced matches agrees with the others. The engines
listed as returning nothing raise no error — the pattern is accepted and
simply finds nothing.

| Engine | Constructs silently matching nothing |
| --- | --- |
| shell | 214 |
| r-tre | 23 |
| dart | 20 |
| javascript | 11 |
| postgresql | 8 |
| swift | 4 |
| php | 3 |
| csharp | 1 |
| python | 1 |

<details><summary>All Class B constructs</summary>

| Construct | Pattern | Matches nothing in | Everyone else |
| --- | --- | --- | --- |
| `char-class-range` | `[a-z]+` | shell | `["ello","orld","foo"]` |
| `char-class-negated` | `[^0-9]+` | shell | `["abc","def","ghi"]` |
| `char-escape-d` | `\d+` | shell | `["123","456"]` |
| `char-escape-D` | `\D+` | shell | `["abc","def"]` |
| `char-escape-w` | `\w+` | shell | `["hello","world","123"]` |
| `char-escape-W` | `\W+` | shell | `[" ","! "]` |
| `char-escape-s` | `\s+` | shell | `[" ","\t"]` |
| `char-escape-S` | `\S+` | shell | `["hello","world","123"]` |
| `char-escape-X` | `\X` | dart, r-tre, shell | `["a","é"," ","ñ"," ","o"]` |
| `char-escape-R` | `\R` | dart, r-tre, shell | `["\r\n","\n"]` |
| `char-unicode-prop` | `\p{L}+` | dart, javascript, shell | `["Hello","世界","café"]` |
| `char-unicode-prop-neg` | `\P{L}+` | dart, javascript, shell | `[" "," 123 "]` |
| `anchor-end` | `world$` | r-tre | `["world","world"]` |
| `anchor-start-string` | `\Ahello` | dart, r-tre, shell | `["hello"]` |
| `anchor-end-string` | `end\Z` | dart, postgresql, r-tre, shell | `["end"]` |
| `anchor-end-string-only` | `end\z` | dart, r-tre, shell | `["end"]` |
| `anchor-match-start` | `\G\w+` | dart, r-tre, shell | `["abc"]` |
| `anchor-match-reset` | `foo\Kbar` | dart, r-tre, shell, swift | `["bar","bar"]` |
| `group-capturing` | `(foo)(bar)` | shell | `["foobar","foobar"]` |
| `group-named` | `(?<word>\w+)` | shell | `["hello","world"]` |
| `group-noncapturing` | `(?:foo\|bar)baz` | shell | `["foobaz","barbaz"]` |
| `group-atomic` | `(?>ab\|a)b` | shell | `["abb"]` |
| `group-scoped-flags` | `(?i:hello) world` | shell | `["HELLO world","Hello world"]` |
| `lookahead-positive` | `foo(?=bar)` | shell | `["foo"]` |
| `lookahead-negative` | `foo(?!bar)` | shell | `["foo","foo"]` |
| `lookbehind-positive` | `(?<=foo)bar` | shell | `["bar"]` |
| `lookbehind-negative` | `(?<!foo)bar` | shell | `["bar","bar"]` |
| `backref-named` | `(?<ch>a\|b)\k<ch>` | shell | `["aa","bb"]` |
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
| `l2-nested-named-groups` | `(?<outer>(?<inner>\d+)\w+)` | shell | `["123abc","456def"]` |
| `l2-alternation-in-group` | `(cat\|dog)\s+food` | shell | `["cat food","dog food"]` |
| `l2-quantified-class` | `[a-z]{3,5}` | shell | `["abc","abcde","abcde"]` |
| `l2-negated-class-quantifier` | `[^aeiou]+` | shell | `["h","ll"," w","rld"]` |
| `l2-dot-greedy` | `a.+b` | shell | `["axyzb axxb ab"]` |
| `l2-dot-lazy` | `a.+?b` | shell | `["axb","axxb"]` |
| `l2-lookahead-capture` | `(\w+)(?=\s)` | shell | `["hello","world"]` |
| `l2-lookbehind-capture` | `(?<=\s)(\w+)` | shell | `["world","test"]` |
| `l2-nested-lookaround` | `(?=.*(?<=\d))\w+` | shell | `["abc1"]` |
| `l2-alternation-in-lookbehind` | `(?<=cat\|dog)\w+` | shell | `["fish","wood"]` |
| `l2-scoped-flags-class` | `(?i:[a-z])+` | shell | `["Hello","WORLD"]` |
| `l2-scoped-flags-dot` | `(?s:a.b)` | shell | `["a\nb","axb"]` |
| `l2-atomic-quantifier` | `(?>a+)b` | shell | `["aab","ab"]` |
| `l2-unicode-prop-quantifier` | `\p{L}+` | dart, javascript, shell | `["Hello","世界","café"]` |
| `l2-unicode-prop-anchor` | `^\p{Lu}` | dart, javascript, shell | `["H","W"]` |
| `l2-digit-boundary` | `\b\d+\b` | shell | `["123","456"]` |
| `l2-multiple-captures` | `(\d{2})-(\d{2})-(\d{4})` | shell | `["01-15-2026","12-31-1999"]` |
| `l2-nested-quantifiers` | `(a+)+b` | shell | `["aab","ab"]` |
| `l2-nongreedy-in-group` | `<(.+?)>` | shell | `["<a>","<br>","<div>"]` |
| `l2-class-special-chars` | `[\w.-]+@[\w.-]+` | r-tre, shell | `["user@example.com","test@foo.bar.org"]` |
| `l2-escaped-special` | `\$\d+\.\d{2}` | shell | `["$19.99","$100.00"]` |
| `l2-multiple-named-groups` | `(?<first>\w+)\s+(?<last>\w+)` | shell | `["John Smith","Jane Doe"]` |
| `l2-lookahead-alternation` | `(?=foo\|bar)\w+` | shell | `["foobar","barfoo"]` |
| `l2-lookbehind-quantifier` | `(?<=\d{2})\w+` | shell | `["abc","xyz"]` |
| `l2-possessive-class` | `[a-z]++\d` | shell | `["abc1","xyz2"]` |
| `l2-possessive-in-group` | `(?>a+)b` | shell | `["aab","ab"]` |
| `l2-match-reset-capture` | `foo\K(\w+)` | dart, r-tre, shell, swift | `["bar","baz"]` |
| `l2-unicode-case-insensitive` | `(?i)\p{L}+` | shell | `["Hello","WORLD","café"]` |
| `l2-capturing-star` | `(ab)*c` | shell | `["c","abc","ababc"]` |
| `l2-capturing-optional` | `(Mr\|Mrs\|Ms)?\.?\s*(\w+)` | shell | `["Mr. Smith"," Mrs",". Jones"," Alice"]` |
| `l2-named-group-star` | `(?<seg>[a-z]+\.)*(?<tld>[a-z]+)` | shell | `["www.example.com","foo.bar.org","test"]` |
| `l2-noncapturing-plus` | `(?:ab)+` | shell | `["ab","abab","ababab"]` |
| `l2-noncapturing-optional` | `https?://(?:www\.)?\w+\.\w+` | shell | `["http://example.com","https://www.test.org"]` |
| `l2-noncapturing-exact` | `(?:ha){3}` | shell | `["hahaha"]` |
| `l2-noncapturing-range` | `(?:ab){2,4}` | shell | `["abab","ababab","abababab"]` |
| `l2-noncapturing-lazy` | `(?:ab)+?x` | shell | `["abx","ababx","abababx"]` |
| `l2-anchor-lookbehind` | `(?<=\d)\w*$` | shell | `["23xyz","end"]` |
| `l2-nested-alternation` | `(a\|b(c\|d))e` | shell | `["ae","bce","bde"]` |
| `l2-flag-combo-is` | `hello.world` | shell | `["hello\nworld","HELLO\nWORLD"]` |
| `l2-unicode-group` | `(\p{L}+)\s+(\p{N}+)` | dart, javascript, shell | `["hello 123","世界 456"]` |
| `l2-word-boundary-group` | `\b(\w{4})\b` | shell | `["over","lazy","dogs"]` |
| `l2-digit-boundary-group` | `\b(\d+)\b` | shell | `["42","100","50"]` |
| `l2-space-boundary-class` | `\S+\s+\S+` | shell | `["hello world","foo bar"]` |
| `l2-capturing-alternation-backref` | `\b(\w+)\s+\1\b` | postgresql | `["the the","quick quick","fox fox"]` |
| `l2-lookahead-anchor-end` | `\w+(?!\.)$` | shell | `["world"]` |
| `l2-lookbehind-anchor-start` | `^(?<=^)(\w+)` | shell | `["hello","world"]` |
| `l2-double-lookahead` | `(?=.*[A-Z])(?=.*\d)\w+` | shell | `["Hello1","hello","abc","A1b"]` |
| `l2-neg-lookahead-neg-lookbehind` | `(?<!\d)\w+(?!\d)` | shell | `["abc","1xyz","def2","ghi"]` |
| `l2-class-union` | `[0-9a-fA-F]+` | shell | `["deadBEEF","0","1A3F"]` |
| `l2-class-literal-special` | `[\]\-^]+` | r-tre, shell | `["]--^"]` |
| `l2-group-alternation-quantifier` | `(?:ab\|cd){2}` | shell | `["abab","cdcd","abcd","cdab"]` |
| `l2-named-group-quantifier` | `(?<hex>[0-9a-f]){2,4}` | shell | `["ab","abcd","abcd","ef"]` |
| `l2-nested-three-groups` | `((a(b))c)` | shell | `["abc","abc"]` |
| `l2-alternation-different-lengths` | `(?:January\|Feb\|March\|Apr)` | shell | `["January","Feb","March","Apr"]` |
| `l2-group-backref-named` | `(?<quote>['"]).*?\k<quote>` | shell | `["'hello'","\"world\""]` |
| `l2-anchor-class-quantifier` | `^[A-Z][a-z]+$` | r-tre, shell | `["Hello","Test"]` |
| `l2-boundary-capture-quantifier` | `\b(\w{3,})\b` | shell | `["the","one","who","tests"]` |
| `l2-unicode-script` | `\p{Cyrillic}+` | dart, javascript, shell | `["Мир","Привет"]` |
| `l2-unicode-category-number` | `\p{N}+` | dart, javascript, shell | `["123","٤٥٦"]` |
| `l2-lookahead-quantified-group` | `(?=\d)(?:\d{3}-?){2}\d{4}` | shell | `["555-123-4567","5551234567"]` |
| `l2-lookbehind-alternation` | `(?<=Mr\.\|Mrs\.)\s*\w+` | shell | `[" Smith"," Jones"]` |
| `l2-capture-lazy-range` | `(<(\w+?)>)` | shell | `["<div>","<span>","<a>"]` |
| `l2-alternation-capture-star` | `(\d{1,3}\.){3}\d{1,3}` | shell | `["192.168.1.1","10.0.0.255","999.999.999.999"]` |
| `l2-complex-email` | `([\w.+-]+)@([\w-]+)\.([a-z]{2,})` | r-tre, shell | `["user@example.com","test+tag@foo.org"]` |
| `l2-hex-color` | `#(?:[0-9a-f]{6}\|[0-9a-f]{3})` | shell | `["#ff0000","#abc","#123"]` |
| `l2-word-nonword-alternation` | `(?:\w+\|\W+)` | shell | `["hello","!!! ","world","??? ","foo"]` |
| `l2-named-groups-alternation` | `(?:(?<year>\d{4})-(?<month>\d{2})\|(?<month2>\d{2})/(?<year2>\d{4}))` | shell | `["2026-04","04/2026"]` |
| `l2-greedy-vs-lazy-star` | `<(.*?)>` | shell | `["<div class=\"x\">","<span>","</div>"]` |
| `l2-noncapturing-nested-alternation` | `(?:(?:un\|re)(?:do\|make))` | shell | `["undo","redo","unmake","remake"]` |
| `l2-lookahead-boundary` | `\b(?=\w{5,})(\w+)\b` | shell | `["quick","brown"]` |
| `l2-neg-lookahead-class` | `\d+(?![\d.])` | shell | `["14","42","0","7"]` |
| `l2-lookbehind-class` | `(?<=[A-Z])\w+` | shell | `["ello","orld","BC"]` |
| `l2-capture-class-range-lazy` | `([a-z]{2,5}?)` | shell | `["ab","cd","ef","gh","ij"]` |
| `l2-lookahead-capture-backref` | `(?=(\w{3}))\w` | shell | `["a","b","c","d"]` |
| `l2-neg-lookbehind-capture` | `(?<!\d)(\w+)` | shell | `["abc","1xyz","def","2ghi","jkl"]` |
| `l2-anchor-neg-lookahead` | `^(?!#)(.+)$` | shell | `["code line","more code"]` |
| `l2-boundary-alternation-capture` | `\b(cat\|dog\|bird)s?\b` | shell | `["cats","dogs","bird"]` |
| `l2-nested-quantifier-class` | `([a-z]+\d+)+` | shell | `["abc123def456","xyz789"]` |
| `l2-optional-capture-in-sequence` | `(\w+)\s*(=)\s*(\w+)(?:\s*;)?` | shell | `["x = 5;","y = 10;","z = 15"]` |
| `l2-class-negated-quantifier-anchor` | `^[^#\n]+$` | r-tre, shell | `["code line","more code"]` |
| `l2-multiple-flag-scopes` | `(?i:hello)\s+(?i:world)` | shell | `["HELLO WORLD","hello world","HeLLo WoRLd"]` |
| `l2-lookahead-class-quantifier` | `(?=.*\d)[\w]{8,}` | shell | `["password1","abcdefgh","abc12345"]` |
| `l2-capture-unicode-named` | `(?<letters>\p{L}+)(?<digits>\p{N}+)` | dart, javascript, shell | `["abc123","hello456"]` |
| `l2-lookbehind-neg-class` | `(?<=[a-z])[^a-z]+` | shell | `[" 123 "," 456"]` |
| `l2-anchor-backref` | `^(\w).*\1$` | r-tre | `["abcda","xyzzx"]` |
| `l2-time-pattern` | `(\d{1,2}):(\d{2})(?::(\d{2}))?` | shell | `["9:30","14:00:59","7:45:01"]` |
| `l2-csv-field` | `(?:"([^"]*)"\|([^,]+))` | shell | `["\"hello\"","world","\"foo,bar\"","baz"]` |
| `l2-version-number` | `(\d+)\.(\d+)(?:\.(\d+))?` | shell | `["1.0","2.3.4","10.20.30","1.2"]` |
| `l2-quantifier-zero-max` | `a{0,3}b` | shell | `["b","ab","aab","aaab","aaab"]` |
| `l2-non-backtracking-group` | `(?>\d+)\.` | shell | `["123.","456."]` |
| `l2-lookahead-lookahead` | `(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{6,}` | shell | `["Hello1 HELLO hello Hello12"]` |
| `l2-lookbehind-lookahead` | `(?<=\[)\w+(?=\])` | shell | `["hello","test","foo"]` |
| `l2-lookahead-optional-capture` | `(?=(\d+)?)\w+` | shell | `["abc","123","def456"]` |
| `l2-boundary-neg-lookahead` | `\b(?!the\b)\w+\b` | shell | `["quick","brown","fox","jumps","over","lazy","dog"]` |
| `l2-named-group-alternation-backref` | `(?<delim>[\|/])\w+\k<delim>` | shell | `["\|hello\|","/world/"]` |
| `l2-class-dot-alternation-quantifier` | `(?:[a-z]+\.)+(?:com\|org\|net)` | shell | `["www.example.com","foo.bar.org","test.net"]` |
| `l2-possessive-group-class` | `(?>\w+)\s` | shell | `["hello ","world ","foo "]` |
| `edge-python-Z-trailing-newline` | `end\Z` | python | `["end"]` |
| `edge-java-intersection` | `[a-z&&[^aeiou]]+` | php | `["h","ll","w","rld","r","g","x"]` |
| `edge-csharp-class-subtraction` | `[a-z-[aeiou]]+` | php | `["h","ll","w","rld","r","g","x"]` |
| `edge-csharp-connector-boundary` | `\bx` | csharp, php | `["x"]` |
| `l3-atomic-alternation-quantifier` | `(?>(?:ab\|cd)+)ef` | shell | `["ababef","cdcdef","abef"]` |
| `l3-nested-lookaround-capture` | `(?<=(?=\d)\w)x` | shell | `["x","x"]` |
| `l3-scoped-flag-lookahead-class` | `(?i:(?=[a-z])\w+)` | shell | `["Hello","WORLD","foo"]` |
| `l3-named-group-flag-backref` | `(?<w>(?i:\w+))\s+\k<w>` | shell | `["Hello Hello","world world"]` |
| `l3-unicode-prop-lookaround-quantifier` | `(?<=\p{L})\d+(?=\p{L})` | dart, javascript, shell | `["123","45","6"]` |
| `l3-multiple-lookaround` | `(?<=\d)(?=\w)(?!_)\w+` | shell | `["abc","def"]` |
| `l3-quantified-alt-lookbehind` | `(?<=(?:Mr\|Mrs\|Dr)\.\s)\w+` | shell | `["Smith","Jones","Who"]` |
| `l3-class-boundary-group-quantifier` | `\b([A-Z][a-z]+){2,}\b` | shell | `["JavaScript","RegexPilot","FooBarBaz"]` |
| `l3-lookahead-lazy-quant-class` | `(?=[A-Z])\w+?\d` | shell | `["Hello3","X9"]` |
| `l3-lookbehind-negated-class-anchor` | `(?<=@)[^.]+$` | shell | `["domain"]` |
| `l3-group-alternation-escape` | `(?<sep>\t\|\s)\w+\k<sep>` | shell | `[" hello ","\tworld\t"]` |
| `l3-nested-quantifiers-group` | `^(?:\w+\s?)+$` | shell | `["hello world foo"]` |
| `l3-lookahead-capture-quantified` | `(?=(\d{2,4}))\d+` | shell | `["12345","67","890"]` |
| `l3-lookbehind-unicode-capture` | `(?<=\p{Lu})(\p{Ll}+)` | dart, javascript, shell | `["ello","orld","afé"]` |
| `l3-dot-flag-group-quant` | `(?s:(.{3,5})\s)` | shell | `["ab\ncd ","efgh\n"]` |
| `l3-noncap-nested-alternation` | `(?:(?:(?:a\|b)c\|de)f\|gh)` | shell | `["acf","bcf","def","gh"]` |
| `l3-word-boundary-class-backref` | `\b([a-z]+)\s+\1\b` | postgresql | `["the the","cat cat","fox fox"]` |
| `l3-lookahead-boundary-quantifier` | `\b(?=[A-Z])\w{3,}\b` | shell | `["Hello","World","JavaScript"]` |
| `l3-capture-lazy-alternation` | `((?:foo\|bar)+?)(baz)` | shell | `["foobarbaz","foobaz"]` |
| `l3-negated-lookahead-class-quant` | `\b(?!un)[a-z]+ed\b` | shell | `["fixed","played","coded"]` |
| `l3-multiple-named-groups-backref` | `(?<first>\w+):(?<second>\w+)=\k<first>-\k<second>` | shell | `["ab:cd=ab-cd","xy:zz=xy-zz"]` |
| `l3-possessive-class-anchor` | `^[a-z]++\d$` | shell | `["abc3"]` |
| `l3-lookahead-lookbehind-capture` | `(?<=\()([^)]+)(?=\))` | shell | `["hello","world"]` |
| `l3-alternation-anchor-escape` | `(?:^\d+$\|^\w+\s\w+$)` | shell | `["12345"]` |
| `l3-flag-multiline-lookahead` | `^(?=\S)\w+` | shell | `["hello","foo"]` |
| `l3-conditional-named-group-quant` | `(?<tag><)?\w+(?(tag)>)` | shell | `["<html>","plain","<div>"]` |
| `l3-unicode-script-lookahead-quant` | `\p{Script=Latin}+(?=\s)` | dart, javascript, shell | `["hello","world","café"]` |
| `l3-capture-inside-lookahead-reuse` | `(?=(cat\|dog))\w+s` | shell | `["cats","dogs"]` |
| `l3-negated-lookbehind-class-boundary` | `(?<!\d)[a-z]+\b` | shell | `["abc","ef","ghi","kl","mno"]` |
| `l3-flag-x-comment-group` | `(?x: (\d+) \s+ (\w+) )` | shell | `["42 answer","7 lucky"]` |
| `l3-escape-quant-group-anchor` | `^(\d{1,3}\.){3}\d{1,3}$` | shell | `["192.168.1.1"]` |
| `l3-lookahead-negated-class-escape` | `(?=.*\d)[^\s]+` | shell | `["abc","12x","foo3"]` |
| `l3-named-alt-quantifier-anchor` | `^(?<proto>https?\|ftp)://\S+$` | shell | `["https://example.com"]` |
| `l3-lookbehind-dot-quantifier` | `(?<=\.).{1,5}(?=\.)` | shell | `["hello","b.xy"]` |
| `l3-capture-nested-quantifiers` | `((\w+)\s?)+` | shell | `["hello world foo"]` |
| `l3-real-email-lookahead` | `(?=[^@]*[A-Z])[\w.+-]+@[\w-]+\.[\w.]+` | shell | `["User@test.com","bad@x.co","Ok@y.io"]` |
| `l3-real-url-optional` | `(?:https?://)?(?:[\w-]+\.)+[a-z]{2,}(?:/[\w./-]*)?(?:\?[\w=&]*)?` | r-tre, shell | `["https://foo.com/p?a=1","bar.io"]` |
| `l3-real-date-validation` | `(?:0[1-9]\|[12]\d\|3[01])[-/](?:0[1-9]\|1[0-2])[-/](?:19\|20)\d{2}` | shell | `["25/12/2024","01-01-1999","31/06/2025"]` |
| `l3-real-ipv4-octet` | `(?:(?:25[0-5]\|2[0-4]\d\|[01]?\d?\d)\.){3}(?:25[0-5]\|2[0-4]\d\|[01]?\d?\d)` | shell | `["192.168.1.1","255.0.0.0","10.0.0.1"]` |
| `l3-real-html-attr` | `(\w+)=["']([^"']*)["']` | shell | `["class=\"foo\"","id='bar'","x=\"z\""]` |
| `l3-real-css-color` | `#(?:[0-9a-fA-F]{3}){1,2}\b` | shell | `["#fff","#aabbcc","#123","#DEAD00"]` |
| `l3-real-json-string` | `"(?:[^"\\]\|\\.)*"` | shell | `["\"hello\"","\"say \\\"hi\\\"\"","\"a\\nb\""]` |
| `l3-real-password-strength` | `(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[!@#$%]).{8,}` | shell | `["Str0ng!Pass weakpass S1mple!"]` |
| `l3-real-log-named-groups` | `(?<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\s+(?<level>INFO\|WARN\|ERROR)\s+(?<msg>.+)` | shell | `["2024-01-15T10:30:00 ERROR fail"]` |
| `l3-real-semver` | `(\d+)\.(\d+)\.(\d+)(?:-(\w+(?:\.\w+)*))?(?:\+(\w+(?:\.\w+)*))?` | shell | `["1.2.3","4.5.6-beta.1","7.8.9+build"]` |
| `l3-real-time-12h` | `(?:0?[1-9]\|1[0-2]):[0-5]\d\s?(?:AM\|PM\|am\|pm)` | shell | `["2:30 PM","12:00am","9:15 AM"]` |
| `l3-real-markdown-link` | `\[([^\]]+)\]\(([^)]+)\)` | r-tre, shell | `["[click](http://x.co)","[go](y.io)"]` |
| `l3-real-hex-color-named` | `#(?<r>[0-9a-f]{2})(?<g>[0-9a-f]{2})(?<b>[0-9a-f]{2})\b` | shell | `["#ff00cc","#aabb11","#123456"]` |
| `l3-real-camel-to-words` | `(?<=[a-z])(?=[A-Z])` | shell | `["","",""]` |
| `l3-real-duplicate-words` | `\b(\w+)\s+\1\b` | postgresql | `["the the","fox fox"]` |
| `l3-real-xml-tag` | `<(\w+)(\s+\w+="[^"]*")*\s*/?>` | shell | `["<div class=\"x\">","<br/>","<img src=\"y\"/>"]` |
| `l3-real-uuid` | `[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}` | shell | `["550e8400-e29b-41d4-a716-446655440000"]` |
| `l3-edge-zero-width-quantified` | `(?:(?=\d))+\d+` | shell | `["123","456"]` |
| `l3-edge-overlapping-capture` | `(?=(a+))\1b` | swift | `["aab"]` |
| `l3-edge-nested-quantifier` | `(a+)+b` | shell | `["aab"]` |
| `l3-edge-alternation-capture-counts` | `(a)(b)\|(c)` | shell | `["ab"]` |
| `l3-edge-case-folding-eszett` | `stra(ss\|ß)e` | shell | `["strasse","straße"]` |
| `l3-edge-possessive-no-backtrack` | `"[^"]*+"x` | shell | `["\"hello\"x"]` |
| `l3-edge-K-with-captures` | `a\K(b)(c)` | dart, r-tre, shell, swift | `["bc"]` |
| `l3-edge-variable-lookbehind` | `(?<=\w{1,10})x` | shell | `["x","x"]` |
| `l3-edge-greedy-vs-lazy-capture` | `"(.*?)".*"(.*)"` | shell | `["\"first\" and \"second\""]` |
| `l3-edge-nested-class-escape` | `[\]\[^-]+` | r-tre, shell | `["]","[","^","-"]` |
| `l3-edge-lookahead-at-end` | `\w+(?=\s*$)` | shell | `["world"]` |
| `l3-edge-catastrophic-avoided` | `(x+x+)+y` | shell | `["xxxy"]` |
| `lib-mac-address` | `(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}` | shell | `["00:1B:44:11:3A:B7","3D-F2-C9-A6-B3-4F"]` |
| `lib-base64-string` | `(?:[A-Za-z0-9+/]{4})+(?:[A-Za-z0-9+/]{2}==\|[A-Za-z0-9+/]{3}=)?` | shell | `["SGVsbG8gV29ybGQ=","plus"]` |
| `lib-jwt-token` | `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` | shell | `["eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.dBjftJeZ4CVP"]` |
| `lib-url-slug` | `^[a-z0-9]+(?:-[a-z0-9]+)*$` | shell | `["my-first-blog-post"]` |
| `lib-file-extension` | `\.([A-Za-z0-9]+)$` | shell | `[".gz"]` |
| `lib-unix-file-path` | `/(?:[\w.-]+/)*[\w.-]+` | r-tre, shell | `["/usr/local/bin/tool","/etc/hosts"]` |
| `lib-us-zip-code` | `\b\d{5}(?:-\d{4})?\b` | postgresql, shell | `["90210","12345-6789"]` |
| `lib-uk-postcode` | `[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2}` | shell | `["SW1A 1AA","EC1A1BB"]` |
| `lib-git-commit-sha` | `\b[0-9a-f]{7,40}\b` | postgresql, shell | `["5aead204","c58b423f1efc9d2a4b7e"]` |
| `lib-html-comment` | `<!--[\s\S]*?-->` | r-tre, shell | `["<!-- hidden -->","<!-- two -->"]` |
| `lib-query-string-param` | `[?&]([^=&]+)=([^&#]*)` | shell | `["?q=regex","&page=2","&sort=desc"]` |
| `lib-trailing-whitespace` | `[ \t]+$` | r-tre, shell | `["   ","\t"]` |
| `lib-scientific-notation` | `-?\d+(?:\.\d+)?[eE][+-]?\d+` | shell | `["6.022e23","-1.6E-19"]` |
| `lib-hashtag-and-mention` | `[#@][A-Za-z0-9_]+` | shell | `["@alice","#regex","#dev_tools"]` |
| `lib-port-number` | `:(?:6553[0-5]\|655[0-2]\d\|65[0-4]\d{2}\|6[0-4]\d{3}\|[1-5]\d{4}\|[1-9]\d{0,3})\b` | postgresql, shell | `[":8080",":5432"]` |
| `lib-data-uri` | `data:([\w/+-]+);base64,([A-Za-z0-9+/=]+)` | r-tre, shell | `["data:image/png;base64,iVBORw0KGgo="]` |
| `lib-iban` | `[A-Z]{2}\d{2}[A-Z0-9]{11,30}` | shell | `["BE68539007547034","DE89370400440532013000"]` |
| `lib-isbn-13` | `97[89](?:-?\d){10}` | shell | `["978-0-13-235088-4","9780132350884"]` |
| `lib-cron-expression` | `^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$` | shell | `["*/5 0 * * 1-5"]` |
| `lib-snake-case-identifier` | `\b[a-z]+(?:_[a-z0-9]+)+\b` | postgresql, shell | `["user_id","total_count_2"]` |

</details>

## Class C — rejected outright

Listed for completeness. These are safe: the engine refuses the pattern,
so you find out at once rather than in production.

<details><summary>All Class C constructs</summary>

| Construct | Pattern | Rejected by |
| --- | --- | --- |
| `backref-numbered` | `(a\|b)\1` | shell |
| `cond-named` | `(?<x>a)?(?(x)b\|c)` | perl, python |
| `l2-group-backref` | `(a\|b)\1+` | shell |
| `l2-backref-in-alternation` | `(a)\1\|(b)\2` | shell |
| `l2-named-backref-conditional` | `(?<x>a)?(?(x)yes\|no)` | perl, python |
| `l2-lookahead-backref` | `(?=(\w+)).*\1` | postgresql, r-tre, shell |
| `l2-multiple-backrefs` | `(\w)(\w)\2\1` | shell |
| `l2-backref-in-quantified-group` | `(['"])(\w+)\1` | shell |
| `l2-triple-capture-backref` | `(\w)(\w)(\w)\1` | shell |
| `l2-backref-alternation-group` | `(\w)(?:\1{2}\|\w{2})` | shell |
| `l2-html-tag-pair` | `<(\w+)>[^<]*</\1>` | shell |
| `edge-python-duplicate-name-error` | `(?P<a>x)(?P<a>y)` | php, python |
| `edge-ruby-absent-operator` | `(?~abc)` | php |
| `edge-ruby-duplicate-names` | `(?<a>.)(?<a>.)` | php |
| `edge-php-duplicate-J` | `(?J)(?<n>a)\|(?<n>b)` | perl |
| `l3-backref-alternation-anchor` | `^(a\|b)\1$` | go, rust, shell |
| `l3-nested-groups-multi-capture` | `((a)(b(c)))\1\2\3\4` | go, rust, shell |
| `l3-atomic-backref-anchor` | `^(?>(.))\1$` | dart, postgresql, r-tre, shell |
| `l3-alternation-backref-lazy` | `(a\|b)\w+?\1` | go, rust, shell |
| `l3-edge-backref-nonparticipating` | `(a)?(b)\1` | go, rust, shell |
| `l3-edge-atomic-no-backtrack` | `(?>a+)ab` | dart, postgresql, r-tre |
| `l3-edge-empty-capture-backref` | `(a?)b\1` | go, rust, shell |
| `l3-edge-quantifier-on-anchor` | `\b+\w+` | dart, elixir, javascript, mysql, php, swift |

</details>

## Alternative engines and tools

Executed like every other column, but not counted above: each is an engine
or tool you opt into, compared here with its language's default on the
constructs both answered. "Silently" means neither side reports an error.

| Column | What it is | Compared with | Compared | Differ | Differ silently |
| --- | --- | --- | --- | --- | --- |
| js-regex-plus | JavaScript through Regex+ | javascript | 271 | 0 | 0 |
| python-regex | Python `regex` module | python | 285 | 35 | 1 |
| r | R with `perl = TRUE` (PCRE2) | r-tre | 278 | 150 | 47 |
| rust-fancy-regex | Rust `fancy-regex` crate | rust | 231 | 40 | 0 |
| shell-awk | BWK awk (macOS awk) | shell | 290 | 216 | 68 |
| shell-awk-gnu | GNU awk (gawk) | shell | 290 | 259 | 77 |
| shell-gnu | GNU grep | shell | 290 | 86 | 0 |
| shell-gnu-ere | GNU grep -E | shell | 290 | 260 | 78 |
| shell-gnu-pcre | GNU grep -P | shell | 290 | 271 | 250 |
| shell-sed | BSD sed | shell | 290 | 8 | 8 |
| shell-sed-gnu | GNU sed | shell | 290 | 1 | 1 |
| shell-sed-gnu-ere | GNU sed -E | shell | 290 | 235 | 80 |

### Shell: BSD and GNU

Shell is measured as the BSD tools macOS ships and, separately, as their
GNU builds. The same tool, BSD against GNU:

| Tool | BSD column | GNU column | Compared | Differ | Differ silently |
| --- | --- | --- | --- | --- | --- |
| grep | shell | shell-gnu | 290 | 86 | 0 |
| sed | shell-sed | shell-sed-gnu | 290 | 9 | 9 |
| awk | shell-awk | shell-awk-gnu | 290 | 68 | 24 |

GNU grep and gawk print a warning such as `stray \ before d` for an escape
they do not know, and still match nothing. That warning is recorded as an
error, so those rows count as loud. BSD grep matches nothing without a word.

## Engine coverage

Not every construct is exercised on every engine — many are written to
probe one flavor's specific behaviour.

| Engine | What it is | Constructs exercised |
| --- | --- | --- |
| csharp | C# (.NET) | 306 |
| dart | Dart | 294 |
| elixir | Elixir (PCRE via Erlang OTP) | 284 |
| go | Go (RE2) | 208 |
| java | Java (java.util.regex) | 298 |
| javascript | JavaScript (V8) | 299 |
| mysql | MySQL (ICU) | 264 |
| perl | Perl | 328 |
| php | PHP (PCRE2) | 333 |
| postgresql | PostgreSQL (Spencer ARE) | 282 |
| python | Python (re) | 285 |
| r-tre | R (TRE) | 278 |
| ruby | Ruby (Onigmo) | 312 |
| rust | Rust (regex crate) | 231 |
| shell | Shell (BSD grep) | 290 |
| swift | Swift (ICU) | 275 |

Not counted: typescript (a copy of javascript), scala (a copy of java), kotlin (a copy of java), groovy (a copy of java), clojure (a copy of java); re2 (no runner, cannot be reproduced).
