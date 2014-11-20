#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use IO::Socket;
use Switch;
use Bencode qw( bencode bdecode );
use threads;

local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
my ( $opts_help, $opts_host, $opts_port, $opts_sessions, $opts_stats, $opts_cacti, $opts_verbose, $opts_action);

GetOptions(
	'h|help|?'	=> \$opts_help,
	'H|host=s'	=> \$opts_host,
	'p|port=s'	=> \$opts_port,
	'sessions'	=> \$opts_sessions,
	'stats'		=> \$opts_stats,
	'c|cacti'	=> \$opts_cacti,
	'v|verbose'	=> \$opts_verbose,
	'a|action=s'	=> \$opts_action,
	);

	if ($opts_help) {
		printhelp();
		exit 0;
	}
	if ( !($opts_host) || !($opts_port) ) {
		printusage();
		exit 0;
	}
	if ( !($opts_action) ) {
		print "Set PING as Action" if ($opts_verbose);
		$opts_action = "ping";
	}

	if ($opts_verbose) { print "\nopts_host:\t$opts_host\nopts_port:\t$opts_port\n"; }

	#get random Number for RTP prxy Unique ID
	my $range = 10000;
	my $random_number = int(rand($range));
	my $bencoded;
	my @data = undef;
	my $output;
	my $sock = undef;

	switch ($opts_action) {
		case "ping" {
			$bencoded = bencode { 'command' => 'ping' };
		}
		case "list" {
			$bencoded = bencode { 'command' => 'I' };
		}
		case "query" {
			$bencoded = bencode { 'command' => 'query' };
		}
	}
	if ( !($bencoded)) {
		print "Did not get any Command\n";
		exit 2;
	}

	print "Bencode string: ", $bencoded, "\n" if ($opts_verbose);

	eval {
		alarm(1);
		# create socket with given parameters
		$sock = new IO::Socket::INET (
			PeerAddr => $opts_host, PeerPort => $opts_port,
			Proto => 'udp'
		);

		# Send out Encoded to RTPengine
		$sock->send("$random_number $bencoded");

		# read
		$sock->recv($output,1000000) || die "Socket not open!";

		# split string since the unique ID is still leading
		@data = split(/ /,$output);

		# close socket
		$sock->close();
	};
	alarm(0);

	if ($@) {
		print ("Could not connect to RTPEngine on port $opts_port!");
		exit 2;
	}

	my @result = values bdecode($data[1]);

	print "\nData received from socket: ", $result[0], " + ", $data[0], "\n" if ($opts_verbose);

	if ( $result[0] eq "pong" && $random_number eq $data[0]) {
		print "RTPengine working! ";
		exit 0;
	} else {
		print "ERROR: Unvalid answer from RTPEngine!";
		exit 2;
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

