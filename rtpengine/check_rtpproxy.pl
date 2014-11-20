#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use IO::Socket;
use threads;

# Main
{
	my (
		$opts_help,
		$opts_host,
		$opts_port,
		$opts_sessions,
		$opts_stats,
		$opts_cacti,
		$opts_verbose,
		$opts_timeout,
	);

	GetOptions(
		'h|help|?'	=> \$opts_help,
		'H|host=s'	=> \$opts_host,
		'p|port=s'	=> \$opts_port,
		'sessions'	=> \$opts_sessions,
		'stats'		=> \$opts_stats,
		'c|cacti'	=> \$opts_cacti,
		'T|timeout=i'	=> \$opts_timeout,
		'v|verbose'	=> \$opts_verbose,
	);

	if ($opts_help) {
		printhelp();
		exit 0;
	}
	if ( !($opts_host) || !($opts_port) ) {
		printusage();
		exit 0;
	}

	if ($opts_verbose) { print "\nopts_host:\t$opts_host\nopts_port:\t$opts_port\n"; }

	$opts_timeout = 8 unless ($opts_timeout);

	alarm($opts_timeout);
	# create socket with given parameters
	my $sock = new IO::Socket::INET (
		PeerAddr => $opts_host,
		PeerPort => $opts_port,
		Proto => 'udp'
	) or die "Could not connect: $!\n";

	# send command ("12345" as identifier)
	$sock->send("12345 I");

	# read
	my $output;
	$sock->recv($output,1000000);
	my @data = split(/\n/,$output);

	# close socket
	$sock->close();
	alarm(0);

	if ($opts_verbose) { print "\nData received from socket:\n"; }

	my ($created, $sessions, $streams, $in, $out, $relayed, $dropped);
	$created = $sessions = $streams = $in = $out = $relayed = $dropped = 0;
	for (my $i=0; $i<=$#data; $i++) {
		if ($opts_verbose) { print "$data[$i]\n"; }
		if ( $data[$i] =~ /sessions created/ ) { $data[$i] =~ /sessions created: (.*)$/; $created = $1; }
		if ( $data[$i] =~ /active sessions/ ) { $data[$i] =~ /active sessions: (.*)$/; $sessions = $1; }
		if ( $data[$i] =~ /active streams/ ) { $data[$i] =~ /active streams: (.*)$/; $streams = $1; }

		if ( $data[$i] =~ /stats.=/ ) {
			$data[$i] =~ /stats = (.*)\/(.*)\/(.*)\/(.*),/;
			$in += $1;
			$out += $2;
			$relayed += $3;
			$dropped += $4;
		}
	}

	if ($#data > 0 && $created > 0) {

		if ($opts_cacti) {
			if ($opts_sessions) {
				print "created:$created sessions:$sessions streams:$streams";
			}
			elsif ($opts_stats) {
				print "in:$in out:$out relayed:$relayed dropped:$dropped";
			}
			else {
				print "created:$created sessions:$sessions streams:$streams in:$in out:$out relayed:$relayed dropped:$dropped";
			}
		}
	} else {
		print "Did not get useful data!\n";
	}
}

sub printhelp {
	printusage();
	print <<TEXT;
options:

	-h, --help:		Show usage
	-H, --host:		Hostname
	-p, --port:		Port
	--sessions:		Print out session related stats
	--stats:		Print out packet stats
	-T, --timeout:		Specify timeout (default 10s)
	-c, --cacti:		Cacti-conform Output

	example: ./check_morertp.pl -H rtpproxy.staging.sipgate.net -p 9000 -c

TEXT
}

sub printusage {
	print "\nusage: check_morertp.pl [-h] -H host\n",
	"	      -p port [-c] [--extra-opts]\n",
	"\n";
}

