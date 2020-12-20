#!/usr/bin/perl

use Data::Dumper;
use List::Util qw(sum);

use strict;
use warnings;

my $log = "/var/run/node_exporter/root_bin_procs_sh.prom";

my %vhosts = (
              '144.76.67.249'        => 'www.daemon.de',
              '127.0.0.1'            => 'www.daemon.de',
              'scipown.e3.daemon.de' => 'www.daemon.de',
             );

sub tcpcon() {
  my $cmd = 'netstat -n -s -p tcp';
  my $count=0;
  open PIPE, "$cmd|";
  while (<PIPE>) {
    chomp;
    if(/connection accepts/) {
      s/^\s*//;
      my ($c, $rest) = split / /, $_, 2;
      $count = $c;
      last;
    }
  }
  close PIPE;
  system('netstat -z -n -s -p tcp > /dev/null');
  return "proc_tcp_session_count $count\n";
}

sub pfdrops() {
  my $cmd = 'tcpdump -n -r /var/log/pflog -tt';
  my $out;
  my $now = time;
  my $past = time - 60;
  my $drops;
  if (open PIPE, "$cmd|") {
    while (<PIPE>) {
      chomp;
      my ($t, $ignore) = split / /, $_;
      if ($t > $past) {
        $drops++;
      }
    }
    close PIPE;
  }
  return "proc_pf_denied_packets $drops\n";
}

sub nginxstats() {
  my $jail = shift;
  my $cmd = "/usr/local/sbin/logtail2 -f /jail/run/scipown/tmp/metrics.log -o /tmp/$jail-nginx-metrics.offset";

  # parse latest metrics
  my %metrics;
  if (open PIPE, "$cmd|") {
    while (<PIPE>) {
      chomp;
      # log_format mtail '$msec $host $connection_requests $request_time $body_bytes_sent $status';
      my($t, $host, $requests, $rtime, $bytes, $status) = split /\s+/, $_;

      if (exists $vhosts{$host}) {
        $host = $vhosts{$host};
      }

      $host =~ s/www.//;

      if (exists $metrics{$host}) {
        $metrics{$host}->{requests}     += $requests;
        push @{$metrics{$host}->{request_time}}, $rtime;
        $metrics{$host}->{bytes_sent}   += $bytes;

        if (exists $metrics{$host}->{status}->{$status}) {
          $metrics{$host}->{status}->{$status}++;
        }
        else {
          $metrics{$host}->{status}->{$status} = 1;
        }
      }
      else {
        $metrics{$host} = {
                           requests     => $requests,
                           request_time => [$rtime],
                           bytes_sent   => $bytes,
                           status       => {$status => 1}
                          };
      }
    }
    close PIPE;
  }

  # pre-process collected stuff
  my %out;
  foreach my $host (sort keys %metrics) {
    my $name = $host;
    $out{"nginx_requests_count{vhost=\"$host\"}"} = $metrics{$host}->{requests};
    $out{"nginx_bytes_sent{vhost=\"$host\"}"}     = $metrics{$host}->{bytes_sent};
    $out{"nginx_request_time{vhost=\"$host\"}"}
      = sum(@{$metrics{$host}->{request_time}}) / @{$metrics{$host}->{request_time}};

    foreach my $status (sort keys %{$metrics{$host}->{status}} ) {
      $out{"nginx_http_status{vhost=\"$host\",status=\"$status\"}"} = $metrics{$host}->{status}->{$status};
    }
  }

  # finally output
  my $o;
  foreach my $key (sort keys %out) {
    $o .= sprintf "%s %s\n", $key, $out{$key};
  }

  return $o;
}

open ND, "| sponge $log";
print ND tcpcon();
print ND pfdrops();
print ND &nginxstats("scipown");
close ND;
