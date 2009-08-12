package App::Catable::Controller::Posts;

use strict;
use warnings;
use base 'Catalyst::Controller::HTML::FormFu';

use DateTime;
use HTML::Scrubber;

=head1 NAME

App::Catable::Controller::Posts - Catalyst Posts Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 add

Add a post to *any* blog that the user is able to add a post to. 

http://localhost:3000/posts/add

=cut

sub add : Local FormConfig
{
    my ($self, $c) = @_;

    my $form = $c->stash->{form};

    if( not exists $c->stash->{blog} ) {
        # Add all blogs this user owns to the list.
        # TODO: Perhaps this could be checkboxes instead?
        $form->get_field({name => "post_blog"})
            ->options(
                [
                    map { +{ label => $_->title(), value => $_->url(), } }
                    ($c->model("BlogDB::Blog")->search({owner => $c->user->id()}))
                ],
            );

        $form->process($c->req);
    }

    $c->stash->{template} = 'posts/add.tt2';

    if ($form->submitted_and_valid && $c->req->params->{submit})
    {
        my $params = $form->params;

        if( exists $params->{post_blog} ) {
            $c->stash->{blog} =
                $c->model("BlogDB::Blog")
                  ->find({title => $c->req->params->{'post_blog'}})
                  ;
        }
        $c->detach('add_submit', [$form]);
    }

    return;
}

=head2 list

Displays a list of posts:

http://localhost:3000/posts/list

=cut

=begin Removed

sub list : Chained('/blog/load_blog') PathPart('posts/list') Args(0) {
    my ($self, $c) = @_;

    $c->log->debug( sprintf "Blog ID %d", $c->stash->{blog}->id );
    my @posts = $c->model('BlogDB')->resultset('Post')
        ->search( { can_be_published => 1,
                    pubdate => { "<=" => \"DATETIME('NOW')" },
                  } );

    $c->log->debug( sprintf "Found %d posts", scalar @posts );

    $c->stash->{posts} = \@posts;
    $c->stash->{template} = 'posts/list.tt2';

    return;
}

=end Removed

=cut

=head2 list

Handles the URL C</posts/list>. In some cases this may be the result
of forwarding (e.g. from C</blog/*>).

If there is a blog in the stash then it will be used to filter the list.
Otherwise it will just list all posts from all blogs.

=cut

sub list : Local
{
    my ($self, $c) = @_;

    my %search_params;

    $search_params{can_be_published} = 1;
    $search_params{pubdate} = { "<=" => \"DATETIME('NOW')" };

    # Add the blog filter if we have a blog.
    $search_params{blog} = $c->stash->{blog}->id
        if exists $c->stash->{blog};
    
    my @posts = $c->model('BlogDB')->resultset('Post')
        ->search( \%search_params );

    $c->log->debug( sprintf "Found %d posts", scalar @posts );

    $c->stash->{posts} = \@posts;
    $c->stash->{template} = 'posts/list.tt2';

    return;
}

=head2 add_submit

This controller method handles the blog post submission. It should
be able to handle submission from either /posts/add or
/blog/*/posts/add, but currently it only handles /blog/*/posts/add.

=cut

sub add_submit : Private {
    my ($self, $c) = @_;

    my $form    = $c->req->args->[0];
    my $params  = $form->params;
    my $blog_id = $c->stash->{blog}->id;

    my $now = DateTime->now();

    # TODO: iterate over blogs when coming from /posts/add
    $c->stash->{new_post}
    = $c->model('BlogDB')->resultset('Post')
        ->create( {
            title => $params->{post_title},
            body => $params->{post_body},
            can_be_published => ($params->{can_be_published} ? 1 : 0),
            pubdate => $now,
            update_date => $now,
            blog => $blog_id
        } );

    
    $c->stash->{template} = 'posts/add-submit.tt2';

    return;
}

=head2 tag

Handles the URL C</posts/tag/*>. Displays all posts with the selected
tag.

May be the result of forwarding, e.g. from C</blog/*/posts/tag/*>. In
the case that there is a blog in the stash, it will be used to narrow
the scope of the search.

=cut

#TODO: Accept multiple tags? AND or OR them together?
#FIXME: Is it CaptureArgs for a reason? do we intend chaining?
sub tag :Local :CaptureArgs(1)  {
    my ($self, $c, $tags_query) = @_;

    my $posts_rs = $c->model("BlogDB::Tag")
                     ->find({label => $tags_query})
                     ->posts;

    if( exists $c->stash->{blog} ) {
        $posts_rs = $posts_rs->find({ blog_id => $c->stash->{blog}->id });
    }

    # TODO: find out how to check there were results.
    if (!$posts_rs)
    {
        $c->res->code( 404 );
        $c->res->body( "Tag '$tags_query' not found." );
        $c->detach;
    }

    $c->stash( posts => [ $posts_rs->all ]);

    $c->stash->{template} = 'posts/list.tt2';
}

=head2 show

Handles the URL C</posts/show/*>

This function forwards to the URL C</blog/*/posts/show/*> by getting
the blog this post belongs to from the post itself. This is to make
it so that the final template picks the correct CSS template for the
blog this post belongs to.

=cut

sub show : Args(1)  {
    my ($self, $c, $post_id) = @_;

    my $post = $c->forward( $c->action_for('/posts/get/' . $post_id) );

    # FIXME: This probably introduces an unnecessary db lookup, as /blog/*
    # will lookup the blog by name, when we already have the blog. Perhaps
    # implement a Private URL for showing a post, and forward to that from
    # both here, and from the handler for /blog/*/posts/show/*
    $c->detach( $c->action_for( sprintf '/blog/%s/posts/show/%d',
                                $post->blog->name,
                                $post->id ) );
}

=head2 show_by_blog

Chains from the '/blog/load_blog' function. This handles the URL 
'/blog/*/post/show/*'.

This is for the direct URL, or for a forwarded request from '/posts/show/*'

=cut

sub show_by_blog :Chained('/blog/load_blog') PathPart('posts/show') CaptureArgs(1) {
    my ($self, $c, $post_id) = @_;

    my $post = $c->stash->{post}
            || $c->forward( $c->action_for('/posts/get/' . $post_id) );

    # Taken from the HTML::Scrubber POD.
    my @default = (
        0   =>    # default rule, deny all tags
        {
            '*'           => 1, # default rule, allow all attributes
            'href'        => qr{^(?!(?:java)?script)}i,
            'src'         => qr{^(?!(?:java)?script)}i,
    #   If your perl doesn't have qr
    #   just use a string with length greater than 1
            'cite'        => '(?i-xsm:^(?!(?:java)?script))',
            'language'    => 0,
            'name'        => 1, # could be sneaky, but hey ;)
            'onblur'      => 0,
            'onchange'    => 0,
            'onclick'     => 0,
            'ondblclick'  => 0,
            'onerror'     => 0,
            'onfocus'     => 0,
            'onkeydown'   => 0,
            'onkeypress'  => 0,
            'onkeyup'     => 0,
            'onload'      => 0,
            'onmousedown' => 0,
            'onmousemove' => 0,
            'onmouseout'  => 0,
            'onmouseover' => 0,
            'onmouseup'   => 0,
            'onreset'     => 0,
            'onselect'    => 0,
            'onsubmit'    => 0,
            'onunload'    => 0,
            'src'         => 0,
            'type'        => 0,
        }
    );

    my @rules = (
        script => 0,
        img => {
            src => qr{^(?!https?://)}i, # only relative image links allowed
            alt => 1,                 # alt attribute allowed
            '*' => 0,                 # deny all other attributes
        },
    );

    my $scrubber = HTML::Scrubber->new(
        allow => [
            qw(
            a p b i u hr br
            ul ol li dl dt dd
            table tr td th
            h1 h2 h3 h4 h5 h6
            )
        ],
        rules => \@rules,
        default => \@default,
    );

    $c->stash (post => $post);
    $c->stash (scrubber => $scrubber);
    return;
}

=head2 load_post

Creates a private URL '/posts/load_post/*'. Returns the post object by ID.

  my $post = $c->forward( '/post/load_post/', [$post_id] );

=cut

sub load_post : Private {
    my ($self, $c, $post_id) = @_;

    my $post = $c->model("BlogDB::Post")->find({id => $post_id });

    if (!$post)
    {
        $c->res->code( 404 );
        # TODO : Possible XSS attack here?
        $c->res->body( "Post '$post_id' not found." );
        $c->detach;
    }

    return $post;
}


=head2 add_comment

Adds a comment to a post. Accepts a form using post.

http://localhost:3000/posts/add-comment

=cut

sub add_comment :Chained('/post') Path('add-comment')
    Args(0){
    my ($self, $c) = @_;

    my $req = $c->request;

    my $title = $req->param('title');
    my $body = $req->param('body');
    my $post_id = $req->param('post_id');

    my $can_be_published = 1;

    my $post = $c->model("BlogDB::Post")->find({id => $post_id });

    if (!$post)
    {
        $c->res->code( 404 );
        # TODO : Possible XSS attack here?
        $c->res->body( "Post '$post_id' not found." );
        $c->detach;
    }

    my $now = DateTime->now();

    my $new_comment = $post->add_comment(
        {
            title => $title,
            body => $body,
            can_be_published => $can_be_published,
            pubdate => $now->clone(),
            update_date => $now->clone(),
        }
    );

    $c->stash (comment => $new_comment);

    $c->stash->{template} = 'posts/add-comment.tt2';

    return;
}

=head2 index 

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->response->body('Matched App::Catable::Controller::Posts in Posts.');
}

=head1 AUTHOR

Shlomi Fish, L<http://www.shlomifish.org/>

=head1 LICENSE

This library is distributed under the MIT/X11 License: 

L<http://www.opensource.org/licenses/mit-license.php>

=cut

1;
