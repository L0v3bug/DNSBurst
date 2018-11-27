#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;
use v5.10;
use Carp;
use Net::DNS;
use Getopt::Std;
use Time::Piece;
use Benchmark;
use Time::HiRes;
use JSON::XS;
use Sys::Syslog;
use Sys::Syslog qw(:standard :macros);

use constant PROGRAM_NAME               => 'dnsburst';
use constant PROGRAM_VERSION            => '1.0';

use constant RECURSION_OK               => 1;
use constant RECURSION_NOK              => 0;
use constant SLEEP                      => 0.1;
use constant ROUND_FLOAT                => 5;

use constant DEFAULT_TIME_OUT           => 10;
use constant DEFAULT_JOBS               => 10;
use constant DEFAULT_RQTS_BY_DOMAIN     => 1;
use constant DEFAULT_SYSLOG_CONFIG     => "nofatal,ndelay,pid";
use constant DEFAULT_VERBOSITY_LVL     => 4;


$Getopt::Std::STANDARD_HELP_VERSION = 1;

my $priorities_tag = {
    'emerg', => '[EMR]',
    'alert', => '[ALR]',
    'crit', => '[CRI]',
    'err', => '[ERR]',
    'warning', => '[WRN]',
    'notice', => '[NOT]',
    'info', => '[INF]',
    'debug' => '[DBG]'
};

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

sub _log($$) {
    my ( $msg, $lvl ) = @_;
    syslog($lvl, $priorities_tag->{$lvl}.' '.$msg);
}

sub log_debug($) {
    my ( $msg ) = @_;
    _log($msg, 'debug');
}

sub log_info($) {
    my ( $msg ) = @_;
    _log($msg, 'info');
}

sub log_warning($) {
    my ( $msg ) = @_;
    _log($msg, 'warning');
}

sub log_error($) {
    my ( $msg ) = @_;
    _log($msg, 'err');
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
    say( 'Usage: '.PROGRAM_NAME.' [OPTIONS] [FILE...]' );
    say( 'Test DNS server performance.' );
    say( '' );
    say( 'OPTIONS:' );
    say( '   -b <buffer size>' );
    say( '         specify the buffer size which will contain all the '
         .'running' );
    say( '         sockets (by default: '.DEFAULT_JOBS.')' );
    say( '   -e' );
    say( '         write the logs to standard error output as well to '
         .'the system log' );
    say( '   -h, --help' );
    say( '         display this help and exit' );
    say( '   -i' );
    say( '         force the dns in iterative mode (by default it\'s ' );
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
    say( '   -v <log priority mask>' );
    say( '         the logs are managed by syslog sets the log priority mask '
         .'(0 to 7)' );
    say( '         to defined which calls may be logged' );
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
    my ( $info_burst ) = @_;

    my $average_time_rqt_real = 0;
    my $average_time_rqt_user = 0;
    my $average_time_rqt_system = 0;
    my $average_requests_second = 0;
    my $succeed_rqts_percent = 0;
    my $failed_rqts_percent = 0;

    my $total_time_real = $info_burst->{'total_time'}->[0];
    my $total_time_user = $info_burst->{'total_time'}->[1];
    my $total_time_system = $info_burst->{'total_time'}->[2];
    my $succeed_requests = $info_burst->{'succeed_requests'};
    my $failed_requests = $info_burst->{'failed_requests'};

    if ( $info_burst->{'total_requests'} ) {
        $average_time_rqt_real = $total_time_real / $info_burst->{'total_requests'};
        $average_time_rqt_user = $total_time_user / $info_burst->{'total_requests'};
        $average_time_rqt_system = $total_time_system / $info_burst->{'total_requests'};
        $succeed_rqts_percent = ($succeed_requests / $info_burst->{'total_requests'}) * 100;
        $failed_rqts_percent = ($failed_requests / $info_burst->{'total_requests'}) * 100;
    }

    if ( $info_burst->{'total_time'}->[0] ) {
        $average_requests_second = $info_burst->{'total_requests'} / $total_time_real;
    }

    return {
        'sended_requests' => $info_burst->{'total_requests'},
        'domain_requested' => $info_burst->{'domain_requests'},
        'total_time' => {
            'real' => $total_time_real,
            'user' => $total_time_user,
            'system' => $total_time_system
        },
        'average_time_for_request' => {
            'real' => $average_time_rqt_real,
            'user' => $average_time_rqt_user,
            'system' => $average_time_rqt_system
        },
        'average_requests_second' => $average_requests_second,
        'succeed_requests' => $succeed_requests,
        'failed_requests' => $failed_requests,
        'succeed_requests_percent' => $succeed_rqts_percent,
        'failed_requests_percent' =>$failed_rqts_percent
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
    my ( $info_burst, $display_in_json ) = @_;
    my $stats = _calcul_stats( $info_burst );

    if ( $display_in_json ) {
        print JSON::XS->new->encode( $stats );
    } else {
        _human_readable_stats( $stats );
    }
}

sub _dns_rqt($$$) {
    my ( $resolver, $buffer, $domain_to_request ) = @_;
    my $packet = $resolver->bgsend( $domain_to_request );
    push @$buffer, $packet;
}

sub _dns_answers_ready($$$;$) {
    my ( $resolver, $buffer, $info_burst, $must_wait_to_be_empty ) = @_;
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
                $info_burst->{'answer_count'}++;
                $repeat = 0;
                if ( defined( $packet ) ) {
                    my $code = $packet->header->rcode;
                    if ($code eq 'NOERROR') {
                        $info_burst->{'succeed_requests'}++;
                    } else {
                        $info_burst->{'failed_requests'}++;
                    }
                } else {
                    $info_burst->{'failed_requests'}++;
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
    my $info_burst = {
        'total_requests' => 0,
        'domain_requests' => 0,
        'total_time' => 0,
        'answer_count' => 0,
        'failed_requests' => 0,
        'succeed_requests' => 0,
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
        $info_burst->{'domain_requests'}++;

        my $remaining_rqts = $rqts_by_domain;
        while ( $remaining_rqts > 0 ) {
            if ( scalar @jobs_buffer < $jobs and $remaining_rqts > 0 ) {
                for ( ; $remaining_rqts > 0 and scalar @jobs_buffer < $jobs;
                        $remaining_rqts-- ) {
                    _dns_rqt( $resolver, \@jobs_buffer, $domain );
                    $info_burst->{'total_requests'}++;
                }
            } else {
                _dns_answers_ready( $resolver, \@jobs_buffer, $info_burst );
            }
        }
    }

    _dns_answers_ready( $resolver, \@jobs_buffer, $info_burst, 1 );

    my $t1 = Benchmark->new;
    $info_burst->{'total_time'} =  timediff($t1, $t0);

    return $info_burst;
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
my $verbosity_lvl = 0;

getopts( 'hiejv:b:s:t:m:', \%opts ) or abort();

if ( defined $opts{e} ) {
    openlog(PROGRAM_NAME, DEFAULT_SYSLOG_CONFIG.',perror', LOG_USER);
} else {
    openlog(PROGRAM_NAME, DEFAULT_SYSLOG_CONFIG, LOG_USER);
}

if ( defined $opts{v} ) {
    $verbosity_lvl = $opts{v};

    unless ($opts{v} =~ /^\d+$/m) {
        $verbosity_lvl = DEFAULT_VERBOSITY_LVL;
    } elsif ( $verbosity_lvl < 0 ) {
        $verbosity_lvl = 0;
    } elsif ( $verbosity_lvl > 7 ) {
        $verbosity_lvl = 7;
    }

    setlogmask((LOG_UPTO($verbosity_lvl)));

    log_error('Verbose level set to: '.$verbosity_lvl);
} else {
    setlogmask((LOG_UPTO(DEFAULT_VERBOSITY_LVL)));
}

if ( defined $opts{h} ) {
    usage();
    exit 0;
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
my $info_burst = burst( $resolver, $jobs, $rqts_by_domain );
display_stats( $info_burst, $display_in_json );