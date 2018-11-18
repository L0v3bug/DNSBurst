#!/usr/bin/perl -w -
use strict;
use warnings;
use utf8;
use Data::Dumper;
use v5.10;
use Carp;
use Net::DNS;
use Getopt::Std;
use Time::Piece;
use Benchmark;
use Time::HiRes;
use JSON::XS;

use constant PROGRAM_NAME               => 'dnsburst';
use constant PROGRAM_VERSION            => '1.0';

use constant VERBOSE_DEACTIVATE         => 0;
use constant VERBOSE_ACTIVE             => 1;
use constant RECURSION_OK               => 1;
use constant RECURSION_NOK              => 0;
use constant LOG_DEBUG                  => 'DBG';
use constant LOG_INFO                   => 'INF';
use constant LOG_WARNING                => 'WAR';
use constant LOG_ERROR                  => 'ERR';
use constant SLEEP                      => 0.1;
use constant ROUND_FLOAT                => 5;

use constant DEFAULT_VERBOSITY          => VERBOSE_DEACTIVATE;
use constant DEFAULT_TIME_OUT           => 10;
use constant DEFAULT_JOBS               => 10;
use constant DEFAULT_RQTS_BY_DOMAIN     => 1;


$Getopt::Std::STANDARD_HELP_VERSION = 1;

our $verbosity  = DEFAULT_VERBOSITY;

#-----------------------------------------------------------------------------#
# Subroutines
#-----------------------------------------------------------------------------#

sub check_arguments($) {
    my ( $args ) = @_;
    my $nb_files = scalar @$args;

    for ( my $i = 0; $i < $nb_files; $i++ ) {
        my $file = @$args[$i];

        unless ( -e $file ) {
            log_error('The file: '.$file.', do not exists');
            splice( @$args, $i, 1 );
            next;
        }

        if ( -d $file ) {
            log_error('The file: '.$file.', is a directory');
            splice( @$args, $i, 1 );
            next;
        }

        unless ( -r $file ) {
            log_error('The file: '.$file.', is not readable');
            splice( @$args, $i, 1 );
            next;
        }

        if ( -z $file ) {
            log_error('The file: '.$file.', is empty');
            splice( @$args, $i, 1 );
            next;
        }
    }

    if ( $nb_files == scalar @$args or scalar @$args > 0 ) {
        return 1;
    } else {
        return 0;
    }
}

sub _timestamp {
    my $time = localtime();
    return $time->strftime("%H:%M:%S %d-%m-%Y");
}

sub _log($$) {
    my ( $msg, $lvl ) = @_;

    if ( $verbosity == VERBOSE_DEACTIVATE ) {
        return;
    }

    my $timestamp = _timestamp();

    say STDERR ( $timestamp.' '.PROGRAM_NAME.' ['.$lvl.'] '.$msg ) ;
}

sub log_debug($) {
    my ( $msg ) = @_;
    _log($msg, LOG_DEBUG);
}

sub log_info($) {
    my ( $msg ) = @_;
    _log($msg, LOG_INFO);
}

sub log_warning($) {
    my ( $msg ) = @_;
    _log($msg, LOG_WARNING);
}

sub log_error($) {
    my ( $msg ) = @_;
    _log($msg, LOG_ERROR);
}

sub _str_is_ip_address($) {
    my ( $str ) = @_;

    if ( $str =~ /^(\d{1,3}\.){3}(\d{1,3})$/m ) {
        return 1;
    }

    return 0;
}

sub abort {
    usage();
    exit 1;
}

# Called when supplying --help option
sub HELP_MESSAGE {
    usage();
}

# Called when supplying --version or --help option
sub VERSION_MESSAGE {
    info_version();
}

sub info_version {
    say( 'Version: '.PROGRAM_VERSION );
}

sub usage {
    say( 'Usage: '.PROGRAM_NAME.' [OPTIONS] [FILE...]');
    say( 'Test DNS server performance.' );
    say( '' );
    say( 'OPTIONS:' );
    say( '   -b <buffer size>' );
    say( '         specify the buffer size which will contain all the '
         .'running' );
    say( '         sockets (by default: '.DEFAULT_JOBS.')' );
    say( '   -h, --help' );
    say( '         display this help and exit' );
    say( '   -i' );
    say( '         force the dns in iterative mode, (by default it\'s ' );
    say( '         recursive)' );
    say( '   -j' );
    say( '         display the output statistics formated in json' );
    say( '   -m <number of requests>' );
    say( '         send multiple dns requests to the domain(s)' );
    say( '   -s <DNS server ip or name>' );
    say( '         use this server to resolve the domain name' );
    say( '   -t <timeout in seconds>' );
    say( '         change the resolution timeout (by default: '
         .DEFAULT_TIME_OUT.')' );
    say( '   -v' );
    say( '         active verbose mode' );
    say( '   --version' );
    say( '         display '.PROGRAM_NAME.' version' );
}

sub _basic_dns_resolution($) {
    my ( $domain ) = @_;

    unless ( $domain ) {
        return undef;
    }

    my $resolver = new Net::DNS::Resolver;
    my $query = $resolver->search( $domain, 'A' );
    my @answers = $query->answer;

    return $answers[0]->address;
}

sub create_resolver(;$$$) {
    my ( $server, $timeout, $recurse ) = @_;
    my $resolver = undef;

    $resolver = new Net::DNS::Resolver();
    $resolver->{tcp_timeout} = $timeout;
    $resolver->{udp_timeout} = $timeout;
    $resolver->{recurse} = $recurse;
    $resolver->{debug} = 0;

    unless ( $server ) {
        return $resolver;
    }

    my @name_server = ();
    if ( _str_is_ip_address( $server ) ) {
        push @name_server, $server;
    } else {
        my @server_ip = _basic_dns_resolution( $server );
        push @name_server, @server_ip;
    }

    $resolver->{nameservers} = \@name_server;

    return $resolver;
}

sub _calcul_stats($) {
    my ( $stats ) = @_;

    my $av_tm_rqt_r = 0;
    my $av_tm_rqt_u = 0;
    my $av_tm_rqt_s = 0;
    my $av_rqt_tm_u = 0;
    my $per_succeed = 0;
    my $per_failed = 0;

    my $tt_reel = $stats->{'total_time'}->[0];
    my $tt_user = $stats->{'total_time'}->[1];
    my $tt_system = $stats->{'total_time'}->[2];
    my $success_rqt = $stats->{'success_count'};
    my $fail_rqt = $stats->{'error_count'};

    if ( $stats->{'total_requests'} ) {
        $av_tm_rqt_r = $tt_reel / $stats->{'total_requests'};
        $av_tm_rqt_u = $tt_user / $stats->{'total_requests'};
        $av_tm_rqt_s = $tt_system / $stats->{'total_requests'};
        $per_succeed = ($success_rqt / $stats->{'total_requests'})*100;
        $per_failed = ($fail_rqt / $stats->{'total_requests'})*100;
    }

    if ( $stats->{'total_time'}->[0] ) {
        $av_rqt_tm_u = $stats->{'total_requests'} / $tt_reel;
    }

    return {
        'sended_requests' => $stats->{'total_requests'},
        'domain_requested' => $stats->{'domain_requests'},
        'total_time' => {
            'real' => $tt_reel,
            'user' => $tt_user,
            'system' => $tt_system
        },
        'average_time_for_request' => {
            'real' => $av_tm_rqt_r,
            'user' => $av_tm_rqt_u,
            'system' => $av_tm_rqt_s
        },
        'average_requests_second' => $av_rqt_tm_u,
        'succeed_requests' => $success_rqt,
        'failed_requests' => $fail_rqt,
        'succeed_requests_percent' => $per_succeed,
        'failed_requests_percent' =>$per_failed
    };
}

sub _human_readable_stats($) {
    my ( $stats ) = @_;

    say( 'Stats:' );
    say( 'Sended requests: '.$stats->{'sended_requests'} );
    say( 'Domain requested: '.$stats->{'domain_requested'} );
    say( 'Total Time: ' );
    say( '    real:   '.$stats->{'total_time'}->{'real'} );
    say( '    user:   '.$stats->{'total_time'}->{'user'} );
    say( '    system: '.$stats->{'total_time'}->{'system'} );
    say( '' );
    say( 'Average time for a requests: ' );
    say( '    real:   '.$stats->{'average_time_for_request'}->{'real'} );
    say( '    user:   '.$stats->{'average_time_for_request'}->{'user'} );
    say( '    system: '.$stats->{'average_time_for_request'}->{'system'} );
    say( 'Average emitted requests per second: '
         .$stats->{'average_requests_second'} );
    say( 'Success requests: '.$stats->{'succeed_requests_percent'}
         .'% ('.$stats->{'succeed_requests'}.'/'
         .$stats->{'sended_requests'}.')' );
    say( 'Failed requests: '.$stats->{'failed_requests_percent'}
         .'% ('.$stats->{'failed_requests'}.'/'
         .$stats->{'sended_requests'}.')' );
}

sub display_stats($$) {
    my ( $stats, $display_in_json ) = @_;
    my $calculated_stats = _calcul_stats( $stats );

    if ($display_in_json) {
        print JSON::XS->new->encode( $calculated_stats );
    } else {
        _human_readable_stats( $calculated_stats );
    }
}

sub _dns_rqt($$$) {
    my ( $resolver, $buffer, $domain_to_request ) = @_;
    my $packet = $resolver->bgsend( $domain_to_request );
    push @$buffer, $packet;
}

sub _dns_answers_ready($$$;$) {
    my ( $resolver, $buffer, $stats, $must_wait_to_be_empty ) = @_;
    my $repeat = 1;

    while ( $repeat or
            ( defined($must_wait_to_be_empty) and
              $must_wait_to_be_empty == 1 and scalar @$buffer > 0 ) ) {
        for ( my $i = 0; $i < scalar @$buffer; $i++ ) {
            my $packet = @$buffer[$i];
            if ( $resolver->bgisready( $packet ) ) {
                $packet = $resolver->bgread($packet);
                splice( @$buffer, $i, 1 );
                $i--;
                $stats->{'answer_count'}++;
                $repeat = 0;
                if ( defined( $packet ) ) {
                    my $code = $packet->header->rcode;
                    if ($code eq 'NOERROR') {
                        $stats->{'success_count'}++;
                    } else {
                        $stats->{'error_count'}++;
                    }
                } else {
                    $stats->{'error_count'}++;
                }
            }
        }

        if ( $repeat ) {
            log_debug( 'Sleep '.SLEEP );
            Time::HiRes::sleep( SLEEP );
        }
    }
}

sub burst($$$) {
    my ( $resolver, $jobs, $rqts_by_domain ) = @_;
    my @jobs_buffer = ();
    my $is_job_start = 0;
    my $t0 = undef;
    my $stats = {
        'total_requests' => 0,
        'domain_requests' => 0,
        'total_time' => 0,
        'answer_count' => 0,
        'error_count' => 0,
        'success_count' => 0,
    };

    foreach my $domain ( <> ) {

        unless ($is_job_start) {
            $is_job_start = 1;
            $t0 = Benchmark->new;
        }

        chomp( $domain );
        unless ( $domain ) {
            log_warning('One of the provided domain is empty');
            next;
        }

        log_info('Domain: '.$domain);
        $stats->{'domain_requests'}++;

        my $remaining_rqts = $rqts_by_domain;
        while ( $remaining_rqts > 0 ) {
            if ( scalar @jobs_buffer < $jobs and $remaining_rqts > 0 ) {
                for ( ; $remaining_rqts > 0 and scalar @jobs_buffer < $jobs;
                        $remaining_rqts-- ) {
                    _dns_rqt( $resolver, \@jobs_buffer, $domain );
                    $stats->{'total_requests'}++;
                }
            } else {
                _dns_answers_ready( $resolver, \@jobs_buffer, $stats );
            }
        }
    }

    _dns_answers_ready( $resolver, \@jobs_buffer, $stats, 1 );

    my $t1 = Benchmark->new;
    $stats->{'total_time'} =  timediff($t1, $t0);

    return $stats;
}

#-----------------------------------------------------------------------------#
# Options
#-----------------------------------------------------------------------------#
my %opts;
my $server = undef;
my $timeout = DEFAULT_TIME_OUT;
my $recurse = RECURSION_OK;
my $jobs = DEFAULT_JOBS;
my $rqts_by_domain = DEFAULT_RQTS_BY_DOMAIN;
my $display_in_json = 0;

getopts( 'hvijb:s:t:m:', \%opts ) or abort();

if ( defined $opts{h} ) {
    usage();
    exit 0;
}

if ( defined $opts{v} ) {
    $verbosity = VERBOSE_ACTIVE;
    log_info('Verbose is now active');
}

if ( defined $opts{j} ) {
    $display_in_json = 1;
    log_info('Display the output statistics formated in JSON');
}

if ( defined $opts{b} ) {
    if ( $opts{b} =~ /^\d+$/m and $opts{b} > 0 ) {
        $jobs = $opts{b};
        log_info('The jobs option has been set to '.$jobs);
    } else {
        log_warning('Wrong value for `-b` option, the default value (buffer='.
        $jobs.') will be used');
    }
}

if ( defined $opts{s} ) {
    $server = $opts{s};
    log_info('The server DNS has been change to: '.$server);
}

if ( defined $opts{i} ) {
    $recurse = RECURSION_NOK;
    log_info('Force the dns in iterative mode');
}

if ( defined $opts{t} ) {
    if ( $opts{t} =~ /^\d+$/m and $opts{t} > 0 ) {
        $timeout = $opts{t};
        log_info('The DNS timeout requests has been set to '.$timeout
                 .' seconds.');
    } else {
        log_warning('Wrong value for `-t` option, the default value '
                    .' (timeout = '.$timeout.') will be used');
    }
}

if ( defined $opts{m} ) {
    if ( $opts{m} =~ /^\d+$/m and $opts{m} > 0 ) {
        $rqts_by_domain = $opts{m};
        log_info('Send '.$rqts_by_domain.' requests to the domain(s) '
                 .'to request');
    } else {
        log_warning('Wrong value for `-m` option, the default value '
                    .'(request by domain = '.$rqts_by_domain.') will be used');
    }
}

unless (check_arguments(\@ARGV)) {
    abort();
}

#-----------------------------------------------------------------------------#
# Main
#-----------------------------------------------------------------------------#

my $resolver = create_resolver( $server, $timeout, $recurse );
my $stats = burst( $resolver, $jobs, $rqts_by_domain );
display_stats( $stats, $display_in_json );