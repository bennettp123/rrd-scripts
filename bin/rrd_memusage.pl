#!/usr/bin/perl
use RRDs;

# define location of rrdtool databases
my $rrd = '~/.rrd/db/memusage.rrd';
# define location of images
my $img = '~/.rrd/img';

my $mem_data = `free -b |grep cache:|cut -d":" -f2|awk '{print \$1}'`;
chomp $mem_data;

# if loadavg database doesn't exist, create it
if (! -e "$rrd") {
  RRDs::create "$rrd",
        "-s 60",
	"DS:memory_usage:GAUGE:120:0:2147483647",
	"RRA:AVERAGE:0.5:1:2880",
	"RRA:AVERAGE:0.5:30:672",
	"RRA:AVERAGE:0.5:120:732",
	"RRA:AVERAGE:0.5:720:1460";
}

RRDs::update "$rrd",
  "-t", "memory_usage",
  "N:$mem_data";

# Generate graphs
CreateGraphs("day");
CreateGraphs("week");
CreateGraphs("month");
CreateGraphs("year");

#------------------------------------------------------------------------------
sub CreateGraphs($){
  my $period = shift;
  
  RRDs::graph "$img/memusage-$period.png",
		"-s -1$period",
		"-t Memory Use",
		"--lazy",
		"-h", "150", "-w", "700",
		"-l 0",
		"-a", "PNG",
		"-v memory use",
		"DEF:usage=$rrd:memory_usage:AVERAGE",
		"VDEF:min=usage,MINIMUM",
		"VDEF:avg=usage,AVERAGE",
		"VDEF:max=usage,MAXIMUM",
		"VDEF:cur=usage,LAST",
		"COMMENT: \\l",
		"COMMENT:               ",
		"COMMENT:Minimum    ",
		"COMMENT:Maximum    ",
		"COMMENT:Average    ",
		"COMMENT:Current    \\l",
		"COMMENT:   ",
		"AREA:usage#EDA362:Usage  ",
		"LINE1:usage#F47200",
		"GPRINT:min:%5.1lf %sB   ",
		"GPRINT:max:%5.1lf %sB   ",
		"GPRINT:avg:%5.1lf %sB   ",
		"GPRINT:cur:%5.1lf %sB   \\l";
  if ($ERROR = RRDs::error) { 
    print "$0: unable to generate $period graph: $ERROR\n"; 
  }
}

exit 0;

data_error:
exit 1;

regex_error:
exit 2;
