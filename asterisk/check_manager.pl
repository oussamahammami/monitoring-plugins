#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use diagnostics;
use LIB_AST_MANAGER;
use Data::Dumper;
use Time::HiRes qw( sleep );
use Cache::Memcached;

our (	$opts_help,
	$opts_host,
	$opts_ip,
	$opts_user,
	$opts_password,
	$opts_memcached,
	$opts_nocallsok,
	$opts_service,
	$opts_verbose,
	$opts_noversion,
	$opts_noastconfig,
	$opts_maxcalls,
	$opts_totalcallsmax,
	$opts_active,
	$opts_zapspans,
	$opts_zap,
	$opts_skype,
	$opts_g729,
   );
Getopt::Long::Configure ("bundling");
GetOptions(	'h|help|?' => \$opts_help,
		'H|host=s' => \$opts_host,
		'I|ip=s'   => \$opts_ip,
		'u|user=s' => \$opts_user,
		'p|password=s' => \$opts_password,
		'm|memcached=s' => \$opts_memcached,
		'n|nocalls' => \$opts_nocallsok,
		's|service=s' => \$opts_service,
		'v|verbose' => \$opts_verbose,
		'noversion' => \$opts_noversion,
		'noastconfig' => \$opts_noastconfig,
		'x|maxcalls=i' => \$opts_maxcalls,
		'a|active=s' => \$opts_active,
		'z|zapspans=s' => \$opts_zapspans,
		'zaptel' => \$opts_zap,
		'skype' => \$opts_skype,
		'g729' => \$opts_g729,
		'totalcalls=i' => \$opts_totalcallsmax,
	  );

my $sip			= 0;
my $zap 		= 0;
my $local 		= 0;
my $channels 		= 0;
my $calls 		= 0;
my $commandCorrect 	= 1;
my $error		= 0;
my $version		= '';
my $astconfig		= '';
my $uptime		= 0;
our %ERRORS 		= ('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);

my $state = 'UNKNOWN';
my $msg;
my $cfgpath = '/etc/icinga/objects/';

our $cmdfile = '/var/lib/icinga/rw/icinga.cmd';

if ($opts_help) {
	print_help();
	exit $ERRORS{'OK'};
}

my $asterisk_manager = new AST_MANAGER;

$asterisk_manager->user($opts_user);
$asterisk_manager->secret($opts_password);
$asterisk_manager->host($opts_ip);

CHECK:
{
	unless (my $auth = $asterisk_manager->conn) {
		$state = 'CRITICAL';
                $state = "UNKNOWN" if ($asterisk_manager->{'error'} =~ /Connection refused/);
		$msg = $asterisk_manager->{'error'};
		last CHECK;
	}
	# if active option is set, do only one specific check and return result
	if ($opts_active) {
		if ($opts_active eq 'uptime') {
			($state,$msg) = check_uptime('active');
		} elsif ($opts_active eq 'version') {
			($state,$msg) = check_version('active');
		} elsif ($opts_active eq 'astconfig') {
			($state,$msg) = check_astconfig('active');
		} elsif ($opts_active eq 'sipchan') {
			($state,$msg) = check_calls('active');
		} elsif ($opts_active eq 'zapspans') {
			($state,$msg) = check_zapspans('active');
		} elsif ($opts_active eq 'skype') {
			($state,$msg) = check_skype('active');
		} elsif ($opts_active eq 'g729') {
			($state,$msg) = check_g729('active');
		}
		$msg .= " (active check forced)";
	# otherwise do all checks and push them as passive results
	} else {
		check_version();
		check_astconfig();
		check_uptime();
		check_calls();
		if ($opts_zapspans && $opts_zapspans > 0) {
			check_zapspans();
		}
		if ($opts_skype) {
			check_skype();
		}
		if ($opts_g729) {
			check_g729();
		}

		$asterisk_manager->disconn;

		$msg = "Manager Connection established.";
		$state = "OK";
	}
}

print "$state $msg \n";
exit $ERRORS{$state};

sub check_zapspans {
	my $active = shift;
	my $zapspans = 0;
	my $technology = 'dahdi';
	my $msg = '';
	my $state = 'OK';
	$technology = 'zap' if defined($opts_zap);
	my @spans = $asterisk_manager->clicommand("$technology show status");
	foreach my $element (@spans) {
		if ($element =~ /OK/) {
			$zapspans++;
		}
	}
	if ($zapspans < $opts_zapspans) {
		$state = 'CRITICAL';
	} else {
		# check the PRI output, too
		$zapspans = 0;
		@spans = $asterisk_manager->clicommand("pri show spans");
		foreach my $element (@spans) {
			if ($element =~ /Provisioned, Up, Active/) {
				$zapspans++;
			}
		}
		if ($zapspans < $opts_zapspans) {
			$state = 'CRITICAL';
		}
	}
	$msg = "$zapspans Spans running (wanted = $opts_zapspans)";
	if ($active) {
		return ($state,$msg);
	} else {
		push_passive('ZAPTEL',$state,$msg);
	}
}

sub check_skype {
	my $active = shift;
	my $skype = 0;
	my $state = 'OK';
	my @channeltypes = $asterisk_manager->clicommand("core show channeltypes");
	foreach my $element (@channeltypes) {
		if ($element =~ /Skype/) {
			$skype = 1;
		}
	}
	if ($skype == 1) {
		$msg = "Skype running";
	} else {
		$msg = "No Skype running";
		$state = 'CRITICAL';
	}
	if ($active) {
		return ($state,$msg);
	} else {
		push_passive('SKYPE',$state,$msg);
	}
}

sub check_g729 {
	my $active = shift;
	my $g729 = 0;
	my $err = '';
	my $state = 'OK';
	my $license = 0;
	my ($enc, $dec, $total) = (0, 0, 0);
	my @channeltypes = $asterisk_manager->clicommand("g729 show licenses");
	# Example output
	# File: G729-6D98CEC4.lic -- Key: G729-6D98CEC4 -- Host-ID: 30:14:52:ad:dc:d4:11:55:22:24:5c:d8:a6:9d:54:18:86:a1:df:5c -- Channels: 5 (Expires: 2024-12-15) (OK)
	# 1/1 encoders/decoders of 5 licensed channels are currently in use
	foreach my $element (@channeltypes) {
		if ($element =~ /File: G729.*Channels: (\d+).*\((.*)\)$/) {
			$license = 1;
			if ($2 eq "OK") {
				$g729 += $1;
			} else {
				$err .= $2;
			}
		} elsif ($element =~ /(\d+)\/(\d+) encoders\/decoders of (\d+) licensed channels are currently in use/) {
			($enc, $dec, $total) = ($1, $2, $3);
		}
			
	}
	if ($g729 > 0) {
		my $inuse = $enc;
		$inuse = $dec if ($dec > $enc);
		$msg = "Total channels: $g729 In use: $inuse";
		if ($enc >= $total*0.8 || $dec >= $total*0.8) {
			$state = 'WARNING';
		}
	} else {
		if ($license == 0) {
			$msg = "No license found!";
		} else {
			$msg = "G729 problem: $err";
		}
		$state = 'CRITICAL';
	}
	if ($active) {
		return ($state,$msg);
	} else {
		push_passive('G729',$state,$msg);
	}
}

sub check_calls {
	my $active = shift;
	my $nopermission = undef;
	my $useoldcall = undef;
	my $calls = 0;
	my $totalcalls = 0;
	$opts_service = "SIPCHAN" unless ($opts_service);
	my @res = $asterisk_manager->clicommand("core show channels count");
	foreach my $element (@res) {
		if ($element =~ /^(\d+) active calls?/) { $calls=$1; next; }
		if ($element =~ /^(\d+) calls? processed/) { $totalcalls=$1; next; }
	}
	if ($calls > 0) {
		if (($opts_maxcalls) && ($calls > $opts_maxcalls)) {
			$state = "CRITICAL";
			$msg = "Above maximum calls: $calls (max: $opts_maxcalls)";
			if ($active) {
				return ($state,$msg);
			} else {
				push_passive($opts_service,$state,$msg);
			}
		}
		else {
			$state = "OK";
			$state = "WARNING" if ($opts_totalcallsmax && $totalcalls > $opts_totalcallsmax);
			$msg = "$calls Calls, $totalcalls calls processed";
			$msg .= ", Max Calls exceeded" if ($opts_totalcallsmax && $state eq "WARNING");
			if ($active) {
				return ($state,$msg);
			} else {
				push_passive($opts_service,$state,$msg);
			}
		}
	}
	elsif ($calls == 0) {
		if ($opts_nocallsok) {
			$state = 'OK';
		} else {
			$state = "CRITICAL";
		}
		$msg = "No calls.";
		if ($active) {
			return ($state,$msg);
		} else {
			push_passive($opts_service,$state,$msg);
		}
	}
	else {
		$state = "UNKNOWN";
		$msg = "No result";
		if ($active) {
			return ($state,$msg);
		} else {
			push_passive($opts_service,$state,$msg);
		}
	}
}

sub check_version {
	# Checks the current version of Asterisk and compares it with the wanted version objects/versions/astversion.txt
	my $active = shift;

	my @version = $asterisk_manager->clicommand("core show version");
	foreach my $element (@version) {
		if ($element =~ /^(Asterisk [a-zA-Z0-9\.\-\+~]+)/) {
			$version = $1;
		}
	}
	my $wanted_version = undef;
	my $state = 'CRITICAL';
	my $msg = "Lorem Ipsum";
	unless ($opts_noversion) {
		my $filename = '';
		if (-e "$cfgpath/versions/astversion-$opts_host.txt") {
			$filename = "$cfgpath/versions/astversion-$opts_host.txt";
		} else {
			$filename = "$cfgpath/versions/astversion.txt";
		}
		if (!(-e $filename)) {
			$state = 'UNKNOWN';
			$msg = "Reference Version file missing!";
		} else {
			open(FILE, $filename);
			while (<FILE>) {
				$wanted_version = $_;
				chomp $wanted_version;
			}
			close(FILE);
			if (!$wanted_version) {
				$state = 'UNKNOWN';
				$msg = "UNKNOWN ASTVersion";
			}
			elsif ($version eq $wanted_version) {
				$state = 'OK';
				$msg = "Version: $version";
			}
			else {
				$state = "WARNING";
				$msg = "Version is $version (latest: $wanted_version)";
			}
		}
	}
	else {
		$state = 'OK';
		$msg = "Version: $version";
	}

	print Dumper $version if $opts_verbose;
	print Dumper $wanted_version if $opts_verbose;

	if ($active) {
		return ($state,$msg);
	} else {
		push_passive("AST_VERSION",$state,$msg);
	}

}

sub check_astconfig {
	# Checks the current astconfig of Asterisk and compares it with the wanted astconfig objects/versions/astconfig.txt
	my $active = shift;

	my $dialplancommand = 0;
	my @astconfig = $asterisk_manager->clicommand("core show globals");
	foreach my $element (@astconfig) {
		if ($element =~ /commit ([a-zA-Z0-9]+)/) {
			$astconfig = $1;
		} elsif ($element =~ /No such command/) {
			$dialplancommand = 1;
		}
	}
	if ($dialplancommand) {
		@astconfig = $asterisk_manager->clicommand("dialplan show globals");
		foreach my $element (@astconfig) {
			if ($element =~ /commit ([a-zA-Z0-9]+)/) {
				$astconfig = $1;
			}
		}
	}

	my $wanted_astconfig = undef;
	my $state = 'CRITICAL';
	my $msg = "Lorem Ipsum";
	unless ($opts_noastconfig) {
		my $filename = '';
		if (-e "$cfgpath/versions/astconfig-$opts_host.txt") {
			$filename = "$cfgpath/versions/astconfig-$opts_host.txt";
		} else {
			$filename = "$cfgpath/versions/astconfig.txt";
		}
		if (!$astconfig) {
			$state = 'UNKNOWN';
			$msg = "Could not find running ASTCONFIG version";
		} elsif (!(-e $filename)) {
			$state = 'UNKNOWN';
			$msg = "Reference astconfig version file missing!";
		} else {
			open(FILE, $filename);
			while (<FILE>) {
				$wanted_astconfig = $_;
				chomp $wanted_astconfig;
			}
			close(FILE);
			if (!$wanted_astconfig) {
				$state = 'UNKNOWN';
				$msg = "UNKNOWN ASTCONFIG";
			}
			elsif ($astconfig eq $wanted_astconfig) {
				$state = 'OK';
				$msg = "ASTCONFIG commit: $astconfig";
			}
			elsif ($wanted_astconfig eq "STAGE") {
				$state = 'OK';
				$msg = "ASTCONFIG commit: $astconfig This is a STAGE Setup";
			}
			else {
				$state = "WARNING";
				$msg = "ASTCONFIG commit: $astconfig (latest: $wanted_astconfig)";
			}
		}
	}
	else {
		$state = 'OK';
		$msg = "ASTCONFIG: $astconfig";
	}

	print Dumper $astconfig if $opts_verbose;
	print Dumper $wanted_astconfig if $opts_verbose;

	if ($active) {
		return ($state,$msg);
	} else {
		push_passive("AST_CONFIG",$state,$msg);
	}

}

sub check_uptime {
	my $active = shift;
	my $seconds = 0;
	my @uptime = $asterisk_manager->clicommand("core show uptime");
	foreach my $element (@uptime) {
		if ($element =~ /^System uptime: (.*)/) {
			$uptime = $1;
			if ($element =~ /(\d+) year[s]?/) {
				$seconds += $1 * 86400 * 365;
			}
			if ($element =~ /(\d+) week[s]?/) {
				$seconds += $1 * 86400 * 7;
			}
			if ($element =~ /(\d+) day[s]?/) {
				$seconds += $1 * 86400;
			}
			if ($element =~ /(\d+) hour[s]?/) {
				$seconds += $1 * 3600;
			}
			if ($element =~ /(\d+) minute[s]?/) {
				$seconds += $1 * 60;
			}
			if ($element =~ /(\d+) second[s]?/) {
				$seconds += $1;
			}
		}
	}
	my $mkey = 'AST_UPTIME_' . $opts_host;
	my $last = use_memcached($mkey,$seconds);
	if ($last) {
		if ($last =~ /^\d+$/) {
			if ($seconds < $last) {
				my $state = "WARNING";
				my $msg = "Asterisk was restarted recently\nOld uptime: $last seconds, new uptime: $seconds seconds.\nUptime: $uptime";
				if ($active) {
					return ($state,$msg);
				} else {
					push_passive("AST_UPTIME",$state,$msg);
				}
			} else {
				my $state = "OK";
				my $msg = "Uptime: $uptime";
				if ($active) {
					return ($state,$msg);
				} else {
					push_passive("AST_UPTIME",$state,$msg);
				}
			}
		}
	}
	return $seconds;
}

sub use_memcached {
	my ($key, $curresult) = @_;
	my $lastresult;
	my $memd = undef;
	eval {
		$memd = new Cache::Memcached {
			'servers' => [ $opts_memcached ],
			'debug' => 0,
			'compress_threshold' => 10_000,
		};
	};
	if ($@) {
		print "Could not connect to MemcacheD server! $!\n" if (defined($opts_verbose));
	}
	if ($memd) {
		$lastresult = $memd->get( $key );
	}
	if ($lastresult) {
		print "Got last state $lastresult for key $key from MemcacheD\n" if (defined($opts_verbose));
	} else {
		print "Getting last state from MemcacheD failed!\n" if ($opts_verbose);
	}

	unless ($lastresult) {
		$lastresult = undef;
	}

	if ($curresult && $memd) {
		if ( $memd->set( $key , $curresult, 1200 ) ) {
			print "Saved current state $curresult for key $key to MemcacheD\n" if (defined($opts_verbose));
		} else {
			print "Saving to MemCacheD failed!\n" if ($opts_verbose);
		}
	}
	return $lastresult;
}

sub push_passive {
	my ($service,$state,$msg) = @_;
	my $timestamp = time;

	eval {
		open CMD, ">>", $cmdfile or die $!;
	};
	if ($@) {
		print "Could not open Command file!\n" if (defined($opts_verbose));
		return;
	}

	my $cmdmsg = sprintf("[%s] PROCESS_SERVICE_CHECK_RESULT;%s;%s;%s;%s\n", $timestamp,$opts_host,$service,$ERRORS{$state},$msg);

#	[<timestamp>] PROCESS_SERVICE_CHECK_RESULT;<host_name>;<svc_description>;<return_code>;<plugin_output>

	print $cmdmsg if (defined($opts_verbose));
	print CMD $cmdmsg;

	close CMD;
}

sub printusage {

	print "\nusage: check_manager [-h?] -H hostname -I hostaddress\n",
	      "-u username -p password -s servicename [--nocalls]\n",
	      "[-a servicename] [-c] -x maxcalls [--noversion] [--noastconfig]\\n";
}

sub print_help {

	print "Copyright (c) 2008 sipgate GmbH\n\n";
	printusage();

	print <<TEXT;

options:

	-H, --host:	The (Icinga) Hostname of the host to check.

	-I, --ip:	IP address of the host to check.

	-u, --username: Username of the Manager User

	-p, --password: Password of the Manager User

	-a, --active:   Force active Check of specific sub-check
	                possible values: sipchan, version, uptime, astconfig, zapspans

	-n, --nocalls:  Return ok when there are no calls, too

	--noversion:    Don't check for version of Asterisk

	--noastconfig:  Don't check for astconfig of Asterisk

	-s, --service:  Name of the SIPCHAN service check

	--totalcalls:   Warn if total number of calls since start is exceeded

	-x, --maxcalls: Maximum amount of parallel calls

	-z, --zapspans:	Number of Zapspans that should be up

	--zaptel:	Use old zaptel instead of dahdi

TEXT
}

