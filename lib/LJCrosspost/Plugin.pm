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
    my ($ctx, $args, $cond) = @_;

    my $entry = $ctx->stash('entry');

    my $id = $entry->lj_id;
    my $anum = $entry->lj_anum;

    my $cached = { cached_ok => 1};

    my $prefs = LJCrosspost::Prefs->byBlogOrAuthor( $ctx->stash('blog'),
                                                    $entry->author);
    my $username = $prefs->username;
    my $url = $prefs->server;

    $url =~ s{/?$}{/users/$username};

    if ($anum && $id) {
        $url .= '/' . ($id * 256 + $anum) . ".html"
    }

    return $url;
}

#############################################################
=head2 LJCrosspostLink

This tag outputs a formatted link to the LiveJournal post for a given
entry

=cut
sub link {
    my ($ctx, $args, $cond) = @_;

    my $plugin = MT::Plugin::LJCrosspost->instance;
    my $tmpl = $plugin->load_tmpl('link.tmpl');

    my $text = $args->{text} || 'Crossposted';
    $ctx->var('crosspost_link_text', $text);

    return $tmpl->build( $ctx );
}

#############################################################
=head2 IfLJCrossposted?

A conditional block that is only evaluated if the post has been crossposted.

=cut
sub if_crossposted {
    my ($ctx, $args, $cond) = @_;

    my $entry = $ctx->stash('entry');

    return 1 if ($entry->lj_crosspost && $entry->lj_id && $entry->lj_anum);
    return 0;
}


#############################################################
=head2 LJCut

Add an <lj:cut> tag to the data sent to LiveJournal

=cut
sub ljcut {
    my ($ctx, $args, $cond) = @_;
    my $entry = $ctx->stash('entry');
    # We should die if called outside the correct context, no?

    my $cuttext = $entry->lj_cut_text;
    $cuttext = $cuttext ? qq{ text="$cuttext"} : '';

    my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');

    return "<lj:cut$cuttext>"
        # This might be able to be replaced with a simple call to slurp()
        . $builder->build($ctx,$tokens,$cond)
        . "</lj:cut>";
}


1;