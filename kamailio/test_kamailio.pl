#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use utils qw($TIMEOUT %ERRORS &usage &support &print_revision);
use XMLRPC::Lite;

our ($opts_method, $opts_verbose, $opts_version, $opts_host, $opts_port);

Getopt::Long::Configure ("bundling");
GetOptions(
		'm|method=s'  => \$opts_method,
		'v|verbose' => \$opts_verbose,
		'V|version' => \$opts_version,
		'h|host=s'    => \$opts_host,
		'p|port=s'    => \$opts_port,
);

my $method = $opts_method || 'system.listMethods';
my @rpc_params = ();

print "Querying Kamailio for method $method\n";

my $res = call_rpc($method,@rpc_params);

print Dumper \$res;

sub call_rpc {
	my ($method,@rpc_params) = @_;
	my (%r,$k);

	my($rpc_call) = XMLRPC::Lite
		-> proxy("http://$opts_host:$opts_port") -> call($method, @rpc_params);

	my $res= $rpc_call->result;

	if (!defined $res){
		print "Error querying Kamailio\n";
		$res=$rpc_call->fault;
		%r=%{$res};
		foreach $k (sort keys %r) {
			print("\t$k: $r{$k}\n");
		}
		exit $ERRORS{'UNKNOWN'};
	} else {
		return($res);
	}
}


