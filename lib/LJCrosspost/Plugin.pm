# LiveJournal Crosspost Plugin for Movable Type
# Author: Erik Ogan, erik@ogan.net
# Copyright (C) 2011 Stealthy Monkeys Consulting
# This file is licensed under the Artistic License, or the same
# terms as Perl itself.
package LJCrosspost::Plugin;

use strict;

# Upgrade!
use MT 5;

#############################################################
=head2 LJCrosspostURL

This tag outputs the LiveJournal URL for a given entry

=cut
sub url {
    my ($ctx) = @_;
    my $cfg = $ctx->{config};
    return $cfg->Server;
}

#############################################################
=head2 LJCrosspostLink

This tag outputs a formatted link to the LiveJournal post for a given
entry

=cut
sub link {
    my ($ctx) = @_;
    my $cfg = $ctx->{config};
    return $cfg->Server;
}

1;