#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use v5.10;
use Carp;
use JSON::XS;

use constant FILE_TEST              => 'dns_test';

use constant DNS_SERVER_1           => '8.8.8.8';
use constant DNS_SERVER_2           => 'google-public-dns-a.google.com';

use constant BUFFER_SIZE_1          => '1';
use constant BUFFER_SIZE_2          => '0';
use constant BUFFER_SIZE_3          => '1000000';

use constant NUMBER_OF_RQTS_1       => '1';
use constant NUMBER_OF_RQTS_2       => '20';
use constant NUMBER_OF_RQTS_3       => '100';

#-----------------------------------------------------------------------------#
# Subroutines
#-----------------------------------------------------------------------------#

sub create_domains_file($) {
    my ( $content ) = @_;

    my $rc = open(my $fh, '>', FILE_TEST);

    unless($rc) {
        return 0;
    }

    print $fh $content;
    close($fh) || warn "close failed: $!";

    return 1;
}

sub delete_domains_file {
    my $rc = unlink FILE_TEST;
    unless($rc) {
        say('Unable to delete the file: '.FILE_TEST.' - '.$!);
        return 0;
    }
    return 1;
}

sub execute_dnsburst(;$) {
    my ( $dnsburst_args ) = @_;
    my $cmd = '/usr/bin/perl dnsburst.pl -j '.$dnsburst_args;

    my $ret = `$cmd`;
    unless ($ret) {
        return undef;
    }

    return JSON::XS->new->decode( $ret );
}

sub test1 {
    my $content = "google.com\n";
    $content .= "fewgreeuhyhiojbndgfewf.chjreugvy\n";
    $content .= "1.1.1.1\n";
    $content .= "google.com\n";

    my $rc = create_domains_file($content);
    unless($rc) {
        die('Unable to create domains file');
    }

    my $dnsburst_args = FILE_TEST;
    my $return_value = execute_dnsburst($dnsburst_args);
    my $return_statement = $? >> 8;
    delete_domains_file();

    if ($return_statement != 0) {
        say('[KO] Test 1: return statement = '.$return_statement);
        return 0;
    }

    if ($return_value->{'succeed_requests'} != 3) {
        say('[KO] Test 1: succeed_requests ('.$return_value->{'succeed_requests'}
            .') not equal to 3');
        return 0;
    }

    if ($return_value->{'failed_requests'} != 1) {
        say('[KO] Test 1: failed_requests ('.$return_value->{'failed_requests'}
            .') not equal to 1');
        return 0;
    }

    say('[OK] Test 1');
    return 1;
}

sub test2 {
    my $content = "google.com\n";
    $content .= "fewgreeuhyhiojbndgfewf.chjreugvy\n";
    $content .= "1.1.1.1\n";
    $content .= "google.com\n";

    my $rc = create_domains_file($content);
    unless($rc) {
        die('Unable to create domains file');
    }

    my $dnsburst_args = '-m '.NUMBER_OF_RQTS_1.' '.FILE_TEST;
    my $return_value = execute_dnsburst($dnsburst_args);
    my $return_statement = $? >> 8;
    delete_domains_file();

    if ($return_statement != 0) {
        say('[KO] Test 2: return statement = '.$return_statement);
        return 0;
    }

    if ($return_value->{'succeed_requests'} != 3) {
        say('[KO] Test 2: succeed_requests ('.$return_value->{'succeed_requests'}
            .') not equal to 3');
        return 0;
    }

    if ($return_value->{'failed_requests'} != 1) {
        say('[KO] Test 2: failed_requests ('.$return_value->{'failed_requests'}
            .') not equal to 1');
        return 0;
    }

    say('[OK] Test 2');
    return 1;
}

sub test3 {
    my $content = "google.com\n";
    $content .= "fewgreeuhyhiojbndgfewf.chjreugvy\n";
    $content .= "1.1.1.1\n";
    $content .= "google.com\n";

    my $rc = create_domains_file($content);
    unless($rc) {
        die('Unable to create domains file');
    }

    my $dnsburst_args = '-m '.NUMBER_OF_RQTS_2.' '.FILE_TEST;
    my $return_value = execute_dnsburst($dnsburst_args);
    my $return_statement = $? >> 8;
    delete_domains_file();

    if ($return_statement != 0) {
        say('[KO] Test 3: return statement = '.$return_statement);
        return 0;
    }

    if ($return_value->{'succeed_requests'} != 60) {
        say('[KO] Test 3: succeed_requests ('.$return_value->{'succeed_requests'}
            .') not equal to 60');
        return 0;
    }

    if ($return_value->{'failed_requests'} != 20) {
        say('[KO] Test 3: failed_requests ('.$return_value->{'failed_requests'}
            .') not equal to 20');
        return 0;
    }

    say('[OK] Test 3');
    return 1;
}

sub test4 {
    my $content = "google.com\n";

    my $rc = create_domains_file($content);
    unless($rc) {
        die('Unable to create domains file');
    }

    my $dnsburst_args = '-m '.NUMBER_OF_RQTS_2.' -s '.DNS_SERVER_1.' '.FILE_TEST;
    my $return_value = execute_dnsburst($dnsburst_args);
    my $return_statement = $? >> 8;
    delete_domains_file();

    if ($return_statement != 0) {
        say('[KO] Test 4: return statement = '.$return_statement);
        return 0;
    }

    if ($return_value->{'succeed_requests'} != 20) {
        say('[KO] Test 4: succeed_requests ('.$return_value->{'succeed_requests'}
            .') not equal to 10');
        return 0;
    }

    if ($return_value->{'failed_requests'} != 0) {
        say('[KO] Test 4: failed_requests ('.$return_value->{'failed_requests'}
            .') not equal to 0');
        return 0;
    }

    say('[OK] Test 4');
    return 1;
}

sub test5 {
    my $content = "google.com\n";

    my $rc = create_domains_file($content);
    unless($rc) {
        die('Unable to create domains file');
    }

    my $dnsburst_args = '-m '.NUMBER_OF_RQTS_2.' -s '.DNS_SERVER_2.' '.FILE_TEST;
    my $return_value = execute_dnsburst($dnsburst_args);
    my $return_statement = $? >> 8;
    delete_domains_file();

    if ($return_statement != 0) {
        say('[KO] Test 5: return statement = '.$return_statement);
        return 0;
    }

    if ($return_value->{'succeed_requests'} != 20) {
        say('[KO] Test 5: succeed_requests ('.$return_value->{'succeed_requests'}
            .') not equal to 10');
        return 0;
    }

    if ($return_value->{'failed_requests'} != 0) {
        say('[KO] Test 5: failed_requests ('.$return_value->{'failed_requests'}
            .') not equal to 0');
        return 0;
    }

    say('[OK] Test 5');
    return 1;
}

sub test6 {
    my $content = "google.com\n";
    $content .= "fewgreeuhyhiojbndgfewf.chjreugvy\n";
    $content .= "1.1.1.1\n";
    $content .= "google.com\n";

    my $rc = create_domains_file($content);
    unless($rc) {
        die('Unable to create domains file');
    }

    my $dnsburst_args = '-m '.NUMBER_OF_RQTS_3.' -b '.BUFFER_SIZE_3.' '.FILE_TEST;
    my $return_value = execute_dnsburst($dnsburst_args);
    my $return_statement = $? >> 8;
    delete_domains_file();

    if ($return_statement != 0) {
        say('[KO] Test 6: return statement = '.$return_statement);
        return 0;
    }

    if ($return_value->{'succeed_requests'} != 20) {
        say('[KO] Test 6: succeed_requests ('.$return_value->{'succeed_requests'}
            .') not equal to 10');
        return 0;
    }

    if ($return_value->{'failed_requests'} != 0) {
        say('[KO] Test 6: failed_requests ('.$return_value->{'failed_requests'}
            .') not equal to 0');
        return 0;
    }

    say('[OK] Test 6');
    return 1;
}

#-----------------------------------------------------------------------------#
# Main
#-----------------------------------------------------------------------------#

# Test 1
my $rc = 0;
$rc += test1();
$rc += test2();
$rc += test3();
$rc += test4();
$rc += test5();
$rc += test6();

if ($rc == 5) {
    exit 0;
} else {
    exit 1;
}