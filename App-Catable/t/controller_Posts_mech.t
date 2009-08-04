#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 14;

# Lots of stuff to get Test::WWW::Mechanize::Catalyst to work with
# the testing model.

use vars qw($schema);
BEGIN 
{ 
    $ENV{CATALYST_CONFIG} = "t/var/catable.yml";
    use App::Catable::Model::BlogDB; 

    use lib 't/lib';
    use AppCatableTestSchema;

    $schema = AppCatableTestSchema->init_schema(no_populate => 0);
}

use Test::WWW::Mechanize::Catalyst 'App::Catable';

{
    my $mech = Test::WWW::Mechanize::Catalyst->new;

    $mech->get("http://localhost/blog/usersblog/posts/add");

    #TEST
    is( $mech->status, 402, "Cannot add post when not logged in" );

    login( $mech, "altreus", "password" );

    $mech->get("http://localhost/blog/usersblog/posts/add");

    #TEST
    is( $mech->status, 402, "This is not my blog!" );

    logout( $mech );
    login( $mech, "user", "password" );

    # TEST
    $mech->get_ok("http://localhost/blog/usersblog/posts/add");

    # TEST
    $mech->submit_form_ok(
        { 
            fields =>
            {
                body => "<p>Kit Kit Catty Skooter</p>",
                title => "Grey and White Cat",
            },
            button => "preview",
        },
        "Submitting the preview form",
    );

    # TEST
    $mech->submit_form_ok(
        {
            button => "submit",
        },
        "Submitting the submit form",    
    );

    # TEST
    $mech->get_ok("http://localhost/blog/usersblog/posts/list/");

    # TEST
    like(
        $mech->content, 
        qr/Grey and White Cat/, 
        "Contains the submitted body",
    );
}

{
    sleep(1);
    my $mech = Test::WWW::Mechanize::Catalyst->new;

    login( $mech, "user", "password" );

    # TEST
    $mech->get_ok("http://localhost/blog/usersblog/posts/add");

    # TEST
    $mech->submit_form_ok(
        { 
            fields =>
            {
                body => 
    qq{<p><a href="http://www.shlomifish.org/">Shlomif Lopmonyotron</a></p>},
                title => "Link to Shlomif Homepage",
                tags => "perl, catable, catalyst, cats",
            },
            button => "preview",
        },
        "Submitting the preview form",
    );

    # TEST
    is ($mech->value("tags"),
        "perl, catable, catalyst, cats",
        "Keywords is OK on submitted form.",
    );

    # TEST
    $mech->submit_form_ok(
        {
            button => "submit",
        },
        "Submitting the submit form",    
    );

    # TEST
    $mech->follow_link_ok(
        {
            text_regex => qr{New Post},
        },
        "Following the link to the /show URL homepage"
    );

    my $post_uri = $mech->uri();

    # TEST
    ok ($mech->find_link(
            url => "http://www.shlomifish.org/",
            text_regex => qr{Lopmonyotron},
        ),
        "Link to the page."
    );

    # TEST
    $mech->follow_link_ok(
        {
            url => "http://localhost/blog/usersblog/posts/tag/cats",
            text => "cats",
        },
        "Following the link to the cats tag",
    );

    # TEST
    $mech->follow_link_ok(
        {
            url => "$post_uri",
            text_regex => qr{Link to Shlomif Homepage},
        },
        "Link exists back to the post.",
    );

    # TEST
    is(
        ($mech->uri() . ""),
        "$post_uri",
        "Same URL as before",
    );
}

sub login {
    my $mech     = shift;
    my $username = shift;
    my $password = shift;

    $mech->get( "http://localhost/login" );
    
    $mech->submit_form(
        fields =>
        {
            user => $username,
            pass => $password,
        },
        button => "submit",
    );
}

sub logout {
    my $mech = shift;

    $mech->get( "http://localhost/logout" );
}
