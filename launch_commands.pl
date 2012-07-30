#!/usr/bin/perl

use strict;
use warnings;
use local::lib;
use JSON;
use Data::Dumper;
use IPC::System::Simple "capture";

use ManipulateJSON "decode_json_file";

my $main_path;
if (! exists $ARGV[0]) {
  print "Please specify experiment directory.\n";
  exit;
}
else {
  $main_path = shift @ARGV;
}

# first, read full_experim file that contains every experiment's description
# then, for each experiment configuration, construct an eldo command
my $experims = decode_json_file("${main_path}/full_experim_desc.json");
my $conf = decode_json_file("${main_path}/conf.json");

my $eldo_exe = $conf->{"eldo_cmd"};
my $profiler_exe = $conf->{"profiler_cmd"};
my $eldo_cmd = "";
my $profiler_cmd = "";

## For each experiment's configuration (distinguished by the saved path)
for my $path (keys %{$experims}) {

  for my $params (keys %{$experims->{$path}}) {
    next if (!exists $conf->{$params});
    if ($conf->{$params}{"target"} eq "eldo") { 
      $eldo_cmd = $eldo_cmd . $conf->{$params}{"command"} . " " . join(" ",
        @{$experims->{$path}{$params}}) . " ";
    }
    elsif ($conf->{$params}{"target"} eq "profiler") { 
      ## Special case for VTune's event-config=.. and Perf's events=.. option
      if ( $conf->{$params}{"command"} =~ /=$/ ) {
        $profiler_cmd = $profiler_cmd . $conf->{$params}{"command"} . 
        join(",", @{$experims->{$path}{$params}}) . " ";
      }
      else {
        $profiler_cmd = $profiler_cmd . $conf->{$params}{"command"} . " "
        . join(",", @{$experims->{$path}{$params}}) . " ";
      }
    }
  }

  print $profiler_exe, " ", $profiler_cmd, " ", $eldo_exe, " ",
    $eldo_cmd, "\n";

  ## Execute constructed command
  my $experim_path = $experims->{$path}{"profiler_outpath"}[0];
  my $eldo_log = $experims->{$path}{"eldo_outpath"}[0]."log_execution";
  my $output = capture("$profiler_exe $profiler_cmd $eldo_exe $eldo_cmd 2> ${experim_path}.errlog");
  open(FH, ">".$eldo_log) || die "I cannot open file: $!\n" ;
  print FH $output;
  close(FH);
    
  $eldo_cmd = "";
  $profiler_cmd = "";
}
