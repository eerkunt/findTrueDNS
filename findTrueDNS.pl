#!/usr/bin/perl
#
# scanNetwork  -    This scripts fetches the public DNS XML and queries defined hostnames 
#                   across all DNS Servers.
#
# Author            Emre Erkunt
#                   (emre.erkunt@superonline.net)
#
# History :
# ---------------------------------------------------------------------------------------------
# Version               Editor          Date            Description
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# 0.0.1_AR              EErkunt         20140330        Initial ALPHA Release
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

use threads;
use LWP::Simple;
use HTTP::Request::Common;
use Net::Nslookup;
use Net::DNS;
use Geo::IP::PurePerl;
my %opt;
use vars qw/ %opt /;
use Getopt::Std;
my $version     = "0.0.1_AR";
my $arguments   = "d:vt:";
getopts( $arguments, \%opt ) or usage();
$| = 1;
usage() if ( $opt{h} || !$opt{d});
$opt{t} = 1 unless $opt{t};
my @running = ();
my @Threads;
#
###############################################################################################
# Main Loop
print "findTrueDNS v$version\n";
print "Verbose Mode is ON\n" if ( $opt{v} );
print "Running with $opt{t} threads.\n" if ( $opt{v} );
my @dnsList;
my $gi = Geo::IP::PurePerl->new("GeoIP.dat");
  
# Fetch DNS List
my $url = "public-dns.tk/nameservers.txt";
print "Fetching Public DNS from $url." if ( $opt{v} );
my $ua = LWP::UserAgent->new;
my $URL = 'http://'.$url;
my $response = $ua->get( $URL );
if ( $response->is_success) {
	my $output = $response->decoded_content;
	my @output = split('\n', $output);
	
	foreach $line ( @output ) {
		if ( $line =~ /(\d*\.\d*\.\d*\.\d*)/ ) {
			push(@dnsList, $1);
			&swirl();
		}
	}
	
	print "( ".scalar @dnsList." Name Servers )\n" if ( $opt{v} );
} else {
	print "ERROR!\n";
}
my $url = "wiki.opennicproject.org/Tier2";
print "Fetching Public DNS from $url." if ( $opt{v} );
my $ua = LWP::UserAgent->new;
my $URL = 'http://'.$url;
my $response = $ua->get( $URL );
if ( $response->is_success) {
	my $output = $response->decoded_content;
	my @output2 = split('\n', $output);
	
	foreach $line ( @output2 ) {
		if ( $line =~ /<td>([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*)<\/td>/ ) {
			push(@dnsList, $1);
		}
	}
	
	print "( ".scalar @dnsList." Name Servers )\n" if ( $opt{v} );
} else {
	print "ERROR!\n";
}


print "Running DNS Queries with $opt{t} threads.\n" if ( $opt{v} );
open(CSV, ">> output.csv") or die;
print CSV "ID;Result;\"Name Server\";\"Name Server Country\";FQDN;\"Resolved IP\";\"Resolved IP Country\"\n";
close(CSV);
my $lineCount = 0;
while($lineCount < scalar @dnsList) {
	@running = threads->list(threads::running);
	# print scalar @running." threads running.\n";
	while ( scalar @running < $opt{t} ) {
		# print "New Thread on Item #$lineCount\n";
		#if ( ((scalar @dnsList)-$lineCount) < 1119 ) {
			my $thread = threads->new( sub { &queryFQDN2( $opt{d}, $dnsList[$lineCount], $gi, ((scalar @dnsList)-$lineCount) );});
			push (@Threads, $thread);
			@running = threads->list(threads::running);
		#}
		$lineCount++;
		if ( $lineCount > scalar @dnsList ) {
			last;
		}
	}
	foreach my $thr (@Threads) {
		if ($thr->is_joinable()) {
			$thr->join;
		}
	}
	sleep 1;
}
@running = threads->list(threads::running);
#print "\nFinishing pending jobs ( ".scalar @running." left )\n";
while (scalar @running != 0) {
	foreach my $thr (@Threads) {
		$thr->join if ($thr->is_joinable());
	}
	@running = threads->list(threads::running);
}	

exit 0;
#
###############################################################################################
# Related Functions

sub queryFQDN2 ( $ $ $ ) {
	my $FQDN 		= shift;
	my $ServerIP 	= shift;
	my $GI			= shift;
	my $count		= shift;
	my $filename    = "output.csv";

	my $resolver = Net::DNS::Resolver->new;
	$resolver->nameservers($ServerIP);
	$resolver->tcp_timeout(5);
	$resolver->udp_timeout(5);
	my $query 	 = $resolver->search($FQDN);
	
	open(CSV, ">> $filename") or die;
	if($query) {
		foreach my $rr ($query->answer) {
			next unless $rr->type eq "A";
			if ($rr->address ne "195.175.254.2" && $rr->address ne "10.10.34.34" ) {
				print CSV "$count;QUERIED;$ServerIP;\"".$gi->country_name_by_addr($ServerIP)."\";$FQDN;".$rr->address.";\"".$gi->country_name_by_addr($rr->address)."\"\n";
				print "[ $count ]\n";
				return 1;
			} else {
				print CSV "$count;BLOCKED;$ServerIP;\"".$gi->country_name_by_addr($ServerIP)."\";$FQDN;".$rr->address.";\"".$gi->country_name_by_addr($rr->address)."\"\n";
				print "[ $count ]\n";
				return 1;
			}
		}
	} else {
		print CSV "$count;FAILED;$ServerIP;\"".$gi->country_name_by_addr($ServerIP)."\";$FQDN;N/A;N/A\n";
		print "[ $count ]\n";
		return 0;
	}
	close(FILE);
}

sub pingHost ( $ ) {
	my $IP = shift;

	my $p = Net::Ping->new();
	if ($p->ping($IP)) {
		#print GREEN "[ICMP Ok] ";
		return 1;
	} else {
		#print RED "[ICMP NOk] ";
		return 0;
	}
}

sub usage {
		my $usageText = << 'EOF';
	
findTrueDNS  -    This scripts fetches the public DNS XML and queries defined hostnames 
                  across all DNS Servers.
				  
Author            Emre Erkunt
                  (emre.erkunt@superonline.net)

Usage : findTrueDNS [-d FQDN] [-v] [-t threads]

 Parameter Descriptions :
 -d	[FQDN]				Domain Name that will be queried
 -t [NUMBER OF THREADS] Number of threads you would like to run this script. Default : 20
 -v						Verbose            ( Default OFF )

EOF
		print $usageText;
		exit;
}   # usage()


sub swirl() {
	
	my $diff = 1;
	my $now = time();	
	
	if ( ( $now - $swirlTime ) gt 1 ) {
		if    ( $swirlCount%8 eq 0 ) 	{ print "\b|"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 1 ) 	{ print "\b/"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 2 ) 	{ print "\b-"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 3 ) 	{ print "\b\\"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 4 ) 	{ print "\b|"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 5 ) 	{ print "\b/"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 6 ) 	{ print "\b-"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 7 ) 	{ print "\b\\"; $swirlCount++; }

		$swirlTime = $now;
	}
	return;
	
}