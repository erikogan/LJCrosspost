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

#############################################################
=head2 Event Handlers

=head3 MT::Author::pre_save

Check and transform the LJ password before saving the Author

=cut

sub author_pre_save {
    my ($cb, $app, $obj) = @_;

    # I probably should be poking around in here
    my $q        = $app->{query};

    my $password = $q->param('lj_pass');
    my $verify   = $q->param('lj_pass_verify');

    if (($password || $verify) && $password ne $verify) {
        return $cb->error("The LiveJournal passwords don't match.");
    }

    if ($password) {
        require Digest::MD5;
        $obj->lj_password(Digest::MD5::md5_hex($password));
    }
}

#############################################################
=head3 MT::Entry::pre_save

Transform the LJ custom bitmask before saving the Author

=cut

sub entry_pre_save {
    my ($cb, $app, $obj) = @_;

    # I probably should be poking around in here
    my $q = $app->{query};

    my $security = $obj->lj_security;

    if ($security eq 'custom') {
        my $bitmask = 0;
        my $params = $q->Vars;
        foreach my $k (grep /^custom_sec_\d+$/, keys %$params) {
            $k =~ /^custom_sec_(\d+)$/;
            $bitmask |= (1 << $1) if $params->{"custom_sec_$1"}; # should always be, but test it
        }
        $obj->lj_security("$security:$bitmask");
    }

    my $comments = $q->param('lj_comments');

    if ($comments eq 'on') {
        $obj->lj_comments(1);
        $obj->lj_comments_email(1);
    } elsif ($comments eq 'no_email') {
        $obj->lj_comments(1);
        $obj->lj_comments_email(0);
    } else {
        $obj->lj_comments(0);
        $obj->lj_comments_email(0);
    }

    return 1;
}


1;