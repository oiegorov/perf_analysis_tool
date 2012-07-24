use strict;
use warnings;
use local::lib;
use JSON;
use Data::Dumper;
use IPC::System::Simple "capture";

use ManipulateJSON "decode_json_file";

# first, read full_experim json file
# for each experiment configuration, construct an eldo command

my $experims = decode_json_file("json/full_experim_desc.json");
my $conf = decode_json_file("json/conf.json");

my $eldo_exe = $conf->{"eldo_cmd"};
my $profiler_exe = $conf->{"profiler_cmd"};
my $eldo_cmd = "";
my $profiler_cmd = "";

for my $path (keys %{$experims}) {

  for my $params (keys %{$experims->{$path}}) {
    next if (!exists $conf->{$params});
    if ($conf->{$params}{"target"} eq "eldo") { 
      $eldo_cmd = $eldo_cmd . $conf->{$params}{"command"} . " " . join(" ",
        @{$experims->{$path}{$params}}) . " ";
    }
    elsif ($conf->{$params}{"target"} eq "profiler") { 
      ## Special case for VTune's event-config=.. option
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
  my $output;
  $output = capture("$profiler_exe $profiler_cmd $eldo_exe $eldo_cmd");
  #my $logname = $path;
  #$logname =~ s/\//:/g;
  open(FH, ">".$experims->{$path}{"profiler_outpath"}[0]."log") || die "I Cannot open file: $!\n" ;
  print FH $output;
  close(FH);
    
  $eldo_cmd = "";
  $profiler_cmd = "";
}
