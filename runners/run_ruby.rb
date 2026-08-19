require 'json'

entries = JSON.parse($stdin.read)
results = {}
entries.each do |e|
  begin
    opts = 0
    flags = e['flags'] || ''
    opts |= Regexp::IGNORECASE if flags.include?('i')
    # Ruby's MULTILINE option = DotAll. Ruby-native letter is 'm'; PCRE
    # letter for DotAll is 's'. Accept BOTH so our flag-matrix tests
    # (which pass Ruby-native 'm') AND the construct corpus (which uses
    # PCRE-style 's') both work correctly.
    opts |= Regexp::MULTILINE if flags.include?('m') || flags.include?('s')
    opts |= Regexp::EXTENDED if flags.include?('x')
    rx = Regexp.new(e['pattern'], opts)
    matches = []
    # Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
    # and matches the bridge's behavior.
    e['testText'].scan(rx) do
      m = Regexp.last_match
      matches << { 'match' => m[0], 'index' => m.begin(0) }
    end
    results[e['id']] = { 'matches' => matches, 'error' => nil }
  rescue => ex
    results[e['id']] = { 'matches' => [], 'error' => ex.message }
  end
end
puts JSON.generate(results)
