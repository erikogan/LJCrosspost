# LiveJournal Crosspost Plugin for Movable Type
# Author: Erik Ogan, erik@ogan.net
# Copyright (C) 2011 Stealthy Monkeys Consulting
# This file is licensed under the Artistic License, or the same
# terms as Perl itself.
package LJCrosspost::Plugin;

use strict;

# Upgrade!
use MT 5;

use LJCrosspost::Prefs;

our $clientversion = "$^O-LJCrosspost/0.1.0.$MT::VERSION";

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
=cut

#############################################################
=head3 MT::App::CMS::template_source.edit_entry

Hack the edit_entry template to add LJ metadata & options

=cut

sub entry_source {
    my ($cb, $app, $tmpl) = @_;
    #my $plugin = $cb->plugin;

    my $tmplDir = '../../plugins/LJCrosspost/tmpl';

    # Using included templates is slightly less kludgy

    $$tmpl =~ s{^(\s+?)<mtapp:setting\n(\s+?)id="keywords".*?</mtapp:setting>\n}
	{$&\n$1<mt:if name=lj_crossposting_on><mt:include name="$tmplDir/entry_metadata.tmpl"/></mt:if>\n}sm;

    $$tmpl =~ s{^(\s+?)<mtapp:setting\n(\s+?)id="basename".*?</mtapp:setting>\n}
	{$&\n$1<mt:if name=lj_crossposting_on><mt:include name="$tmplDir/entry_publishing.tmpl"/></mt:if>\n}sm;
}

#############################################################
=head3 MT::App::CMS::template_param.edit_entry

Populate the edit_entry template with values from LJCrosspost::Prefs as
well as data from LJ (lists of friend groups, moods, etc)

=cut
sub entry_param {
    my ($cb, $app, $param, $tmpl) = @_;

    return  unless $param->{object_type} eq 'entry';

    my $plugin = $cb->plugin;

    my $prefs = LJCrosspost::Prefs->byBlogOrAuthor( $param->{blog_id},
                                                    $param->{author_id} );


    if ( $prefs->crosspost && $prefs->server
         && $prefs->username && $prefs->password) {
        my $xmlrpc;

        my $login;
        eval {
            local $SIG{__DIE__} = undef;
            local $SIG{__WARN__} = undef;
            ($xmlrpc, my @challenge) = _getRPCchallenge($prefs);

            $login = $xmlrpc->call('LJ.XMLRPC.login',
                {
                    @challenge,
                    getmoods      => 0,
                    getpickws     => 1,
                    getpickwurls  => 1,
                    clientversion => $clientversion,
                }
            );
        };

        if ($@) {
            MT->error("Livejournal Error: $@");
            return;
        }

        if ($login->fault) {
            return MT->error("LJ XMLRPC ERROR: [" . $login->faultcode . "] "
                . $login->faultstring);
            return;
        }

        my $result = $login->result;

        unless($result) {
            MT->error("XML-RPC error: $!");
        }

        # They come back in id order, which isn't alphabetical
        $param->{moods}
            = [ sort { $a->{name} cmp $b->{name} }
                @{$result->{moods}} ];
        $param->{lj_username} = $prefs->username;

        my %pics;

        for (my $i = 0 ; $i < @{$result->{pickws}} ; $i++) {
            $pics{$result->{pickws}[$i]} = $result->{pickwurls}[$i];
        }

        $param->{lj_userpics} = [ map { { keyword => $_, url => $pics{$_} } }
                                    sort keys %pics];
        $param->{lj_friendgroups} = $result->{friendgroups};

        $param->{lj_security} = $prefs->security
            unless exists $param->{lj_security} && defined $param->{lj_security};

        if ($param->{lj_security} =~ s/(custom):(\d+)/$1/) {
            my $bits = $2;

            for (my $i = 1 ; $i < 32 ; $i++) {
                $param->{"custom_sec_$i"}++
                if ($bits & (1 << $i));
            }
        }

        $param->{"lj_security_$param->{lj_security}"}++;

        $param->{lj_crossposting_on} = $prefs->crosspost;
        $param->{lj_crosspost} = $prefs->crosspost_entry
            unless defined $param->{lj_crosspost};

        foreach my $default (qw {location music picture_keyword mood_id
                                 mood comments comments_email
                                 comments_screen}) {
            $param->{$default} = $prefs->$default
            unless exists $param->{$default};
        }
    }
    $param;
}


#############################################################
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

#############################################################
=head3 build_file_filter

This is where the magic happens.

=cut

sub publish {
    my ($cb, %args) = @_;

    return 1 unless ($args{ArchiveType} eq 'Individual');

    my $entry = $args{Entry};

    return 1 unless $entry->lj_crosspost;

    my $blog = $args{Blog};

    # This might lead to surprises, since I think this is the original author (arguably a feature)
    my $author = $entry->author;

    my $prefs = LJCrosspost::Prefs->byBlogOrAuthor($blog, $author);

    #open WTF, ">/tmp/xpost.wtf." . $entry->id;
    #use Data::Dumper;
    #print WTF Dumper $prefs;

    # They need to be able to turn it off
    return 1 if (!$prefs->crosspost
        || !($prefs->username && $prefs->password && $prefs->server));

    return 1 if ($entry->lj_crosspost_date >= $entry->modified_on);

    my ($xmlrpc, @challenge);

    eval {
        local $SIG{__DIE__} = undef;
        local $SIG{__WARN__} = undef;
        ($xmlrpc, @challenge) = _getRPCchallenge($prefs);
    };

    return $cb->error($@) if ($@);

    my $plugin = MT::Plugin::LJCrosspost->instance;
    my $tmpl = $plugin->load_tmpl('crosspost.tmpl');
    my $ctx = $args{context};
    my $html = $tmpl->build( $ctx );

    return $cb->error($tmpl->errstr) unless defined $html;
    $html =~ s/^\s+//;
    $html =~ s/\s+$//;

    $html = decode_utf8($html);

    my $security = $entry->lj_security || $prefs->security || 'public';

    my @security;
    if ($security eq 'friends') {
        @security = ( security => 'usemask', allowmask => 1);
    } elsif ( $security =~ s/^custom:(\d+)$/custom/ ) {
        @security = ( security => 'usemask', allowmask => $1);
    } else {
        @security = ( security => $security);
    }

    my ($year, $month, $day, $hour, $minute)
	= $entry->authored_on =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})/;

    my $props = {opt_preformatted => 1};

    my %optMap = (
        location           => 'current_location',
        music              => 'current_music',
        picture_keyword    => 'picture_keyword',
        mood_id            => 'current_moodid',
        mood               => 'current_mood',
        lj_backdate        => 'opt_backdated',
        # <sigh> negative options
        lj_comments        => '!opt_nocomments',
        lj_comments_email  => '!opt_noemail',
        lj_comments_screen => 'opt_screening',
    );

    foreach my $k (keys %optMap) {
        my $value = $entry->$k;
        next unless defined $value && $value !~ /^\s*$/;;
        my $opt = $optMap{$k};
        $value = !$value if ($opt =~ s/^!//);
        $props->{$opt} = decode_utf8($value) if $value;
    }

    $props->{taglist} = join ', ', $prefs->tags, $entry->tags;

    my %post = (
        @challenge,
        @security,
        subject => $entry->title,

        year    => $year,
        mon     => $month,
        day     => $day,
        hour    => $hour,
        min     => $minute,

        event   => $html || q{Where'd the text go?},

        props   => $props,
    );


    my $method;
    my $itemid = $entry->lj_id;
    if ($itemid) {
        $method = "editevent";
        $post{itemid} = $itemid;
    } else {
        $method = 'postevent';
    }

    my $res;

    # The redirect is obscuring the errors --aigh, it's trapping the die, too
    eval {
        local $SIG{__DIE__} = undef;
        local $SIG{__WARN__} = undef;
        $res = $xmlrpc->call("LJ.XMLRPC.$method", \%post);
    };

    return $cb->error("LJ ERROR: $@") if ($@);

    if ($res->fault) {
        return $cb->error("LJ XMLRPC ERROR: [" . $res->faultcode . "] "
            . $res->faultstring);
    }

    #unless ($itemid && $entry->lj_anum) {
        my $result = $res->result;
        $entry->lj_id($result->{itemid});
        $entry->lj_anum($result->{anum});

        require MT::Util;
        my @ts = MT::Util::offset_time_list(time, $blog->id);
        # No function for this??
        my $ts = sprintf '%04d%02d%02d%02d%02d%02d',
        $ts[5]+1900, $ts[4]+1, @ts[3,2,1,0];

        $entry->lj_crosspost_date($ts);

        $entry->save;
    #}

    return 1;
}

sub _getRPCchallenge {
    my $prefs = shift;
    my $server = $prefs->server;
    my $username = $prefs->username;
    my $password = $prefs->password;

    $server =~ s{/$}{};

    require XMLRPC::Lite;
    my $xmlrpc = new XMLRPC::Lite;
    #$xmlrpc->outputxml(1);

    $xmlrpc->proxy("$server/interface/xmlrpc");

    my $res = $xmlrpc->call('LJ.XMLRPC.getchallenge');
    die "XMLRPC error: [" . $res->faultcode . "] " . $res->faultstring
        if ($res->fault);

    my $result = $res->result;

    my $challenge = $result->{challenge};

    require Digest::MD5;
    # Password is already MD5 hex
    my $response = Digest::MD5::md5_hex($challenge . $password);

    return ($xmlrpc,
        ver            => 1,
        auth_method    => 'challenge',
        username       => $username,
        auth_challenge => $challenge,
        auth_response  => $response,
    );
}

1;
