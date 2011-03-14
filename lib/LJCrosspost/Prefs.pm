package LJCrosspost::Prefs;

use strict;
use base qw( MT::Object );

__PACKAGE__->install_properties( {
    datasource  => 'crosspost',
    primary_key => 'id',
    column_defs => {
        # With this schema it will be possible for blogs to have
        # preferences, authors to have preferences, and (eventually)
        # authors to have per-blog preferences

        # (If this were a real database we could use multi-column foreign
        # keys, and enforce constraints like foreign keys and uniqueness
        # across multiple columns. Unfortunately, this system needs to
        # work with MySQL (worse: MyISAM))
        id                => 'integer not null auto_increment primary key',
        blog_id           => 'integer',
        author_id         => 'integer',
        username          => 'string(255)',
        password          => 'string(32)',
        server            => q{string(255) default 'http://www.livejournal.com'},
        crosspost         => 'boolean default true',
        crosspost_entry   => 'boolean default false',
        location          => 'string(255)',
        music             => 'string(255)',
        picture_keyword   => 'string(255)',
        mood_id           => 'integer',
        mood              => 'string(255)',
        tags              => 'string(1024)',
        security          => 'string(255)',
        comments          => 'boolean default 1',
        comments_email    => 'boolean default 1',
        # <sigh>
        # comments_screen => 'char(1)',
        comments_screen   => q{string(1) default 'N'},
    },

    # In spite of what the MT documentation claims, indexes are not
    # automatically created in RDBMS (it would be stupid if that were
    # the case)
    indexes     => { map { ($_, 1) } qw/id blog_id author_id/ },
    audit       => 0,
    }
);

sub class_label {
    MT->translate("Preferences");
}
sub class_label_plural {
    MT->translate("Preferences");
}

sub byBlogOrAuthor {
    my ($class, $blog, $author) = @_;

    my $blog_id = ref $blog ? $blog->id : $blog;
    my $author_id = ref $author ? $author->id : $author;

    # I need to figure out how to construct my own WHERE & ORDER BY
    # clauses, since this could be done in a single query:
    #   WHERE	(author_id = ? OR author_id IS NULL)
    #		AND (blog_id = ? OR blog_id IS NULL)
    # ORDER BY	blog_id DESC, author_id DESC
    # (of course, for all I know, MySQL probably returns NULLs in a
    # non-standard order, since everything else it does is so half-assed)

    $blog_id = $blog_id ? $blog_id : undef;
    $author_id = $author_id ? $author_id : undef;

    if ($blog_id && $author_id) {
        my $prefs = $class->load({ blog_id => $blog_id,
                                   author_id => $author_id});
        return $prefs if $prefs;
    }

    if ($blog_id) {
        my $prefs = $class->load({ blog_id => $blog_id },
                                 { null => {author_id => 1}});
        return $prefs if $prefs;
    }

    if ($author_id) {
        my $prefs = $class->load({ author_id => $author_id},
                                 { null => {blog_id => 1}});
        return $prefs if $prefs;
    }

    # try with undefs
    return $class->load({}, {null => {blog_id => 1,  author_id => 1}});
}




1;