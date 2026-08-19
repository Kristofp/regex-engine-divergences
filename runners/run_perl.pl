use JSON::PP;
use strict;
use warnings;

my $input = do { local $/; <STDIN> };
my $entries = decode_json($input);
my %results;

for my $e (@$entries) {
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 5;  # 5 second per-pattern timeout

        my $flags = $e->{flags} // '';
        my $mods = '';
        $mods .= 'i' if $flags =~ /i/;
        $mods .= 'm' if $flags =~ /m/;
        $mods .= 's' if $flags =~ /s/;
        $mods .= 'x' if $flags =~ /x/;
        my $p = $e->{pattern};
        $p = "(?$mods)$p" if $mods;
        my $text = $e->{testText};
        # Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
        # and matches the bridge's behavior.
        my @matches;
        while ($text =~ /$p/g) {
            push @matches, { match => $&, index => int($-[0]) };
            pos($text) = $+[0] + 1 if $+[0] == $-[0];
        }
        alarm 0;
        $results{$e->{id}} = { matches => \@matches, error => undef };
    };
    if ($@) {
        alarm 0;
        my $err = "$@";
        chomp $err;
        $results{$e->{id}} = { matches => [], error => $err };
    }
}
print encode_json(\%results);
