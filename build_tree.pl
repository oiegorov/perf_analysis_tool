use strict;
use warnings;
use local::lib;
use JSON;
use Data::Dumper;
use File::Path "mkpath";

use ManipulateJSON "decode_json_file";

## Parse metrics form "events" array
sub parse_events {
  use List::MoreUtils qw(uniq first_index);
  my $metrics_file = decode_json_file("json/metrics.json");

  my @hw_events = @{$_[0]};
  for my $events (@{$_[0]}) {
    if (exists $metrics_file->{$events}) {
      ## Delete the metric from events array ------------
      my $index = first_index {$_ eq $events} @hw_events;
      splice @hw_events, $index, 1;
      ## ------------------------------------------------
      push @hw_events, ( $metrics_file->{$events} =~ m/[^0-9\/\+\*\-]+/g );
    }
  }

  return @hw_events = uniq(@hw_events);
}

sub create_path_save_experim_data {
  my ($srcpath, $path, $non_common_experim_hash, $common_experim_hash, $hash_to_json) = @_;

  my $full_path = "$srcpath"."$path";
  ## Create a directory path
  mkpath($full_path);

  my %temp_hash = (%{$non_common_experim_hash}, %{$common_experim_hash},
                    %{{"profiler_outpath" => [$full_path]}},
                    %{{"profiler_outfile" => [$full_path."perf.data"]}} );
  $hash_to_json->{"$path"} = \%temp_hash;
}

## Reading the contents of JSON files
##-------------------------------------------------------
my $conf = decode_json_file("json/conf.json");
my $experim_desc = decode_json_file("json/experim_desc.json");
##-------------------------------------------------------

## Iteration loop through experiment description file
##-------------------------------------------------------

## AoA of parameters that have different values for each experiment
## (with level==true)
my @non_common_experim_hash;
## Hash of parameters common to all the experiments (with level=false)
my %common_experim_hash; 

## Parse metrics and include only events in the "events" array
if (exists $experim_desc->{"events"}) {
  @{$experim_desc->{"events"}} = parse_events($experim_desc->{"events"});
}

## Sort out parameters and their values depending on "level" property
for my $param (keys %{$experim_desc}) {

  ## "repeat_num" must be treated differently. No such entry in conf.json
  next if ($param eq "repeat_num");

  ## $conf is a reference to the hash of the whole JSON file
  ## we address the value of a specific key as $conf->{"key_name"}
  ## the value of the key is another hash, whose keys we can
  ## address as $conf->{"key_name"}{"inner_hash_key_name"}
  if ($conf->{$param}{"level"} eq "true") {
    push(@non_common_experim_hash, [$param,
                                    @{$experim_desc->{$param}}]);  
  }
  else {
    $common_experim_hash{$param} = \@{$experim_desc->{$param}};
  }
}

## We need to separate non_common parameter types from values, so that
## we know the precedence of parameter values put into paths
my @non_common_experim_hash_keys;
foreach (@non_common_experim_hash) {
  push( @non_common_experim_hash_keys, shift @{$_});
}

## put AoA with all the parameter values into one formated string
my $glob = join (',', map ('{'.join(',', @$_).'}', @non_common_experim_hash));

my @non_common_param_vals;

## Define the directory ($srcpath) to save experiment results
my $srcpath; 
if (exists $conf->{"main_path"}) {
  $srcpath = $conf->{"main_path"};
  ## To check that path ends by '/'
  $srcpath .= "/" if ( !($srcpath =~ /\/$/) );
}
else {
  $srcpath = "/tmp/";
}

my $path;

## The final hash to be converted to json file
my %hash_to_json;

## glob() returns arrays of all possible combinations
while (my $s = glob($glob)) {

  ## Create an array of experiment non-common parameters values
  @non_common_param_vals = split(/,/, $s);

  my %non_common_experim_hash;
  for (my $i = 0; $i < @non_common_param_vals; $i++) {
    my @temp_arr = split (/ /, $non_common_param_vals[$i]);
    $non_common_experim_hash{$non_common_experim_hash_keys[$i]} = \@temp_arr;
    ## Extract circuit name from the specified path to circuit
    if ($non_common_experim_hash_keys[$i] eq "circuit") {
      $non_common_param_vals[$i] =~ s/.*\/([a-zA-Z0-9_-]*)\.cir/$1/;
    }
    $path=$path."$non_common_param_vals[$i]/";
  }

  ## Handle the situation when each experiment is to be executed several
  ## times. Each execution try should have its folder path=.../../try_#
  if (exists $experim_desc->{"repeat_num"} and
    $experim_desc->{"repeat_num"}[0] != 1 ) {

    my $repeat_num =  $experim_desc->{"repeat_num"}[0];
    if ($repeat_num == 0) {
      die ' "repeat_num" cannot be equal to 0, stopped ';
    }
    
    for (my $j = 0; $j < scalar($repeat_num); $j++) {
      my $try = $j+1;
      my $old_path = $path;
      $path=$path."try_$try/";

      create_path_save_experim_data($srcpath, $path, \%non_common_experim_hash,
        \%common_experim_hash, \%hash_to_json);
      
      $path = $old_path;
    }
  }
  else {    # just one try is needed for each experiment
    create_path_save_experim_data($srcpath, $path, \%non_common_experim_hash,
      \%common_experim_hash, \%hash_to_json);
  }

  $path = "";
}

open(FH, ">json/full_experim_desc.json") || die "Cannot open file: $!\n" ;
print FH to_json(\%hash_to_json, {pretty => 1});
close(FH);

