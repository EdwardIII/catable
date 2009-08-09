package App::Catable::Controller::Blog;

use strict;
use warnings;
use base 'Catalyst::Controller::HTML::FormFu';

=head1 NAME

App::Catable::Controller::Blog - For multiple blogs

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 load_blog

Private action /blog/load_blog/*

Takes the blog name and returns the Row object for that blog.

    my $blog = $c->forward( $c->action_for( '/blog/load_blog/' . $blog_name) );

See also C<blog> in C<App::Catable::Controller::Root>.

=cut

sub load_blog : Private Args(1){
    my ($self, $c, $blog_name) = @_;
   
    my $blog = 
        $c->model('BlogDB')->resultset('Blog')->single({ url => $blog_name});

    $c->log->debug( sprintf " load_blog found blog ID %d", 
                              $c->stash->{blog}->id );

    return $blog;
}

=head2 $self->create($c)

Creates a new blog. Accepts no arguments and ends the chain.

=cut

sub create : Local Args(0) FormConfig
{
    my ($self, $c) = @_;

    my $form = $c->stash->{form};

    $c->stash->{template} = "blog/create.tt2";
    $c->stash->{'submitted'} = 0;

    if ($form->submitted_and_valid)
    {
        my $params = $form->params;

        $c->model('BlogDB')->resultset('Blog')
            ->create(
                {
                    (map 
                        { $_ => $params->{$_} }
                        (qw(url title))
                    ),
                    theme => "catable",
                    owner => $c->user->id(),
                }
            );

        $c->stash->{'submitted'} = 1;
        $c->stash->{'url'} = $params->{'url'};
    }

    return;
}

1;

__END__

=head1 AUTHOR

Alastair Douglas L<http://www.grammarpolice.co.uk/>

=head1 LICENSE

This library is distributed under the MIT/X11 License: 

L<http://www.opensource.org/licenses/mit-license.php>

=cut

