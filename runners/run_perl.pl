use JSON::PP;
use strict;
use warnings;

# Pre-expand `\Q...\E` literal blocks into explicitly escaped regex text.
# Perl's `\Q...\E` is a string-interpolation construct, not a regex
# primitive — it's processed while parsing a regex LITERAL, not when a
# variable containing `\Q` bytes is interpolated into `/$p/`. Since the
# pattern arrives here as a runtime scalar decoded from JSON (never typed
# literally between two `/`), `\Q...\E` would otherwise reach the regex
# compiler as unrecognized escapes — reproduced directly: `perl -e 'my $p =
# "\\Qa)b\\E"; "a)b" =~ /$p/'` dies "Unmatched ) in regex", while the
# textually-identical literal `perl -e '"a)b" =~ /\Qa)b\E/'` matches fine.
# Without this, the runner would measure "Perl via naive interpolation"
# instead of real Perl, and mismeasure every `\Q` pattern as rejected —
# found 2026-08-25 chasing a false positive for `[\cz-A]` that led to
# testing `\Qa)b\E` in the same fixture. `quotemeta` gives identical
# semantics. `sidecars/perl/regexpilot_perl_engine.pl`'s own
# `expand_quote_blocks` carries the identical fix (and the identical
# reasoning) for exactly this reason — the real Perl sidecar receives
# patterns the same way this runner does, so it hit this first. Mirrored
# here verbatim so ground truth reflects what the sidecar actually does,
# not an artifact of this runner's own interpolation.
sub expand_quote_blocks {
    my ($pattern) = @_;
    $pattern =~ s/\\Q(.*?)\\E/quotemeta($1)/ges;
    $pattern =~ s/\\Q(.*)\z/quotemeta($1)/es;
    return $pattern;
}

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
        my $p = expand_quote_blocks($e->{pattern});
        $p = "(?$mods)$p" if $mods;
        my $text = $e->{testText};
        # Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
        # and matches the bridge's behavior.
        my @matches;
        # NO pos() MANIPULATION. Perl's own /g already refuses to repeat a
        # zero-width match at the same position, so a bare loop terminates:
        # `"abc" =~ /x*/g` runs 4 times and stops.
        #
        # Assigning pos() is what breaks that. It resets the "empty match
        # already made here" flag, so `pos($t) = $+[0]` — even to the value
        # pos ALREADY has — loops forever. The runaway this guard was added
        # to survive was caused by the guard's own mechanism.
        #
        # And the guard is not merely unnecessary, it CHANGES THE ANSWER.
        # Skipping to $+[0]+1 after an empty match discards any non-empty
        # match starting at the same offset. Measured against native perl:
        #
        #   (|a|b) on "ab"   perl: []@0 [a]@0 []@1 [b]@1 []@2   guard: 3 empties
        #   a*?    on "aab"  perl: []@0 [a]@0 []@1 [a]@1 []@2 []@3
        #
        # An earlier version of this loop recorded those three empties as
        # PERL'S ANSWER. Do not reintroduce a pos() assignment here: if this
        # ever appears to hang, the cause is a pos() write, not perl.
        while ($text =~ /$p/g) {
            push @matches, { match => $&, index => int($-[0]) };
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
