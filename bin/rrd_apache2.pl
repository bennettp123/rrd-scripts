#!/usr/bin/perl
use RRDs;
use LWP::UserAgent;
use File::stat;
use File::HomeDir;
use Time::localtime;

# define location of rrdtool databases
my $rrd = File::HomeDir->my_home . '/.rrd/db/apache2.rrd';
# define location of images
my $img = File::HomeDir->my_home . '/.rrd/img';
# define your apache stats URL
my $URL = 'http://localhost/status/?auto';
# nginx pidfile -- used to detect when server is restarted
my $apache2_pidfile = '/var/run/apache2.pid';
# stores the most recent nginx pid -- used to detect when the server is restarted
my $apache2_last_pidfile = File::HomeDir->my_home . '/.rrd/apache2_last_pid';
# true if nginx has been restarted
my $apache2_has_been_restarted = 0;
# the time when the server was last restarted
my $server_restarted_time;

my $apache2_current_pid;
open(my $fh, '<', $apache2_pidfile) or goto missing_pid;
{
	local $/;
	$apache2_current_pid = <$fh>;
}
close($fh);
chomp $apache2_current_pid;
$apache2_current_pid =~ /(\d+)/;
$apache2_current_pid = $1;

my $apache2_last_pid;
open(my $fh, '<', $apache2_last_pidfile) or goto missing_pid;
$server_restarted_time = stat($fh)->mtime;
{
	local $/;
	$apache2_last_pid = <$fh>;
}
close($fh);
chomp $apache2_last_pid;
$apache2_last_pid =~ /(\d+)/;
$apache2_last_pid = $1;

if($apache2_current_pid =~ /^\d+$/ and $apache2_last_pid =~ /^\d+$/) {
	if($apache2_current_pid != $apache2_last_pid) {
		$apache2_has_been_restarted = 'yes';
	}
}

missing_pid:
# continue silently.:)

if($apache2_current_pid =~ /^(\d+)$/) {
	open(my $fh, '>', $apache2_last_pidfile) or do {
		print STDERR "warning: couldn't write pidfile $apache2_last_pidfile: $!\n";
		goto couldnt_write_pidfile;
	};
	print $fh "$1\n";
	close($fh);
}

couldnt_write_pidfile:
# continue silently.:)

my $ua = LWP::UserAgent->new(timeout => 30);
my $response = $ua->request(HTTP::Request->new('GET', $URL));

my $accesses_total = 0;
my $kbyes_total = 0;
my $cpuload = 0;
my $uptime = 0;
my $req_persec = 0;
my $bytes_persec = 0;
my $workers_busy = 0;
my $workser_idle = 0;
my $scoreboard = "";

foreach (split(/\n/, $response->content)) {
	$accesses_total = $1 if (/^Total Accesses:\s+([\d\.]+)/i);
	$kbyes_total = $1 if (/^Total kBytes:\s+([\d\.]+)/i);
	$cpuload = $1 if (/^CPULoad:\s+([\d\.]+)/i);
	$uptime = $1 if (/^Uptime:\s+([\d\.]+)/i);
	$req_persec = $1 if (/^ReqPerSec:\s+([\d\.]+)/i);
	$bytes_persec = $1 if (/^BytesPerSec:\s+([\d\.]+)/i);
	$bytes_perreq = $1 if (/BytesPerReq:\s+([\d\.]+)/i);
	$workers_busy = $1 if (/^BusyWorkers:\s+([\d\.]+)/i);
	$workers_idle = $1 if (/^IdleWorkers:\s+([\d\.]+)/i);
	#$scoreboard = $1 if (/^Scoreboard:\s+(\d+)/);
}

#print "AT:$accesses_total; KBT:$kbyes_total; CPU:$cpuload; UP:$uptime; RPS:$req_persec; BPS:$bytes_persec; BPR:$bytes_perreq; WB:$workers_busy; WI:$workers_idle;\n";

# if rrdtool database doesn't exist, create it
if (! -e "$rrd") {
  RRDs::create "$rrd",
        "-s 60",
	"DS:requests_total:GAUGE:120:0:100000000",
	"DS:kbytes_total:GAUGE:120:0:100000000",
	"DS:cpuload:GAUGE:120:0:60000",
	"DS:uptime:GAUGE:120:0:100000000",
	"DS:req_persec:GAUGE:120:0:100000000",
	"DS:bytes_persec:GAUGE:120:0:100000000",
	"DS:bytes_prereq:GAUGE:120:0:100000000",
	"DS:busy_workers:GAUGE:120:0:60000",
	"DS:idle_workers:GAUGE:120:0:60000",
	"RRA:AVERAGE:0.5:1:2880",
	"RRA:AVERAGE:0.5:30:672",
	"RRA:AVERAGE:0.5:120:732",
	"RRA:AVERAGE:0.5:720:1460";
}

# insert values into rrd database
if($nginx_has_been_restarted and defined($server_restarted_time)) {
	printf STDERR "warning: detected nginx server restart; injecting 'U:U:U:U:U'.\n";
	RRDs::update "$rrd",
	  "-t", "requests_total:kbytes_total:cpuload:uptime:req_persec:bytes_persec:bytes_prereq:busy_workers:idle_workers",
	  "$server_restarted_time:U:U:U:U:U:U:U:U:U";
	RRDs::update "$rrd",
	  "-t", "requests_total:kbytes_total:cpuload:uptime:req_persec:bytes_persec:bytes_prereq:busy_workers:idle_workers",
	  "N:U:U:U:U:U:U:U:U:U";
} else {
	RRDs::update "$rrd",
	  "-t", "requests_total:kbytes_total:cpuload:uptime:req_persec:bytes_persec:bytes_prereq:busy_workers:idle_workers",
	  "N:$accesses_total:$kbyes_total:$cpuload:$uptime:$req_persec:$bytes_persec:$bytes_perreq:$workers_busy:$workers_idle";
}

# Generate graphs
CreateGraphs("day");
CreateGraphs("week");
CreateGraphs("month");
CreateGraphs("year");

#------------------------------------------------------------------------------
sub CreateGraphs($){
  my $period = shift;
  
  RRDs::graph "$img/requests-$period.png",
		"-s -1$period",
		"-t Requests on apache2",
		"--lazy",
		"-h", "150", "-w", "700",
		"-l 0",
		"-a", "PNG",
		"-v requests/min",
		"DEF:requests_persec=$rrd:req_persec:AVERAGE",
		"CDEF:requests=requests_persec,60,*",
		"LINE2:requests#336600:Requests",
		"GPRINT:requests:MAX:  Max\\: %5.1lf %S",
		"GPRINT:requests:AVERAGE: Avg\\: %5.1lf %S",
		"GPRINT:requests:LAST: Current\\: %5.1lf %S\\n",
		"HRULE:0#000000";
  if ($ERROR = RRDs::error) { 
    print "$0: unable to generate $period graph: $ERROR\n"; 
  }

  RRDs::graph "$img/connections-$period.png",
		"-s -1$period",
		"-t Workers on apache2",
		"--lazy",
		"-h", "150", "-w", "700",
		"-l 0",
		"-a", "PNG",
		"-v workers",
		#"DEF:total_persec=$rrd:total:AVERAGE",
		#"DEF:reading_persec=$rrd:reading:AVERAGE",
		#"DEF:writing_persec=$rrd:writing:AVERAGE",
		#"DEF:waiting_persec=$rrd:waiting:AVERAGE",

		#"CDEF:total=total_persec,60,*",
		#"CDEF:reading=reading_persec,60,*",
		#"CDEF:writing=writing_persec,60,*",
		#"CDEF:waiting=waiting_persec,60,*",

		"DEF:busy=$rrd:busy_workers:AVERAGE",
		"DEF:idle=$rrd:idle_workers:AVERAGE",

		"LINE2:busy#22FF22:Busy",
		"GPRINT:busy:LAST:   Current\\: %5.1lf %S",
		"GPRINT:busy:MIN:  Min\\: %5.1lf %S",
		"GPRINT:busy:AVERAGE: Avg\\: %5.1lf %S",
		"GPRINT:busy:MAX:  Max\\: %5.1lf %S\\n",
		
		"LINE2:idle#0022FF:Idle  ",
		"GPRINT:idle:LAST: Current\\: %5.1lf %S",
		"GPRINT:idle:MIN:  Min\\: %5.1lf %S",
		"GPRINT:idle:AVERAGE: Avg\\: %5.1lf %S",
		"GPRINT:idle:MAX:  Max\\: %5.1lf %S\\n",
		
		"HRULE:0#000000";
  if ($ERROR = RRDs::error) { 
    print "$0: unable to generate $period graph: $ERROR\n"; 
  }
}
