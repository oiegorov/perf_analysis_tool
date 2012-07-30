package ManipulateJSON;
use strict;
use warnings;
use JSON;
use Exporter;
use Data::Dumper;

our @ISA = qw(Exporter);
our @EXPORT = qw(decode_json_file convert_events);

sub decode_json_file {
  local $/;  # to enable slurp: read the whole file into one string
  open (FH, $_[0]) || die "Cannot open file $_[0]: $!\n";
  my $json_file = <FH>;
  close(FH);

  return from_json($json_file);
}

sub convert_events {
  my $main_path = $_[0];

  use List::MoreUtils qw(first_index);
  my $conf = decode_json_file("${main_path}/conf.json");
  my $hw_events = $_[1];
  ## Convert only if Perf is used. No conversion is needed for VTune
  if ($conf->{"profiler_cmd"} =~ m/^perf/) {
    ## Convert events to PCL form using events.json
    my $events_file = decode_json_file("${main_path}/events.json");

    if ( UNIVERSAL::isa($hw_events,'ARRAY') ) {
      for my $vtune_event (keys %{$events_file}) {
        my $index = first_index {$_ eq $vtune_event} @{$hw_events};
        $hw_events->[$index] = $events_file->{$vtune_event} if ($index != -1);
      }
    }
    else {
      if (exists $events_file->{$hw_events}) {
        $hw_events = $events_file->{$hw_events};
      }
      else {
        return "-1";
      }
    }
  }
  
  return $hw_events;
}

1;
