use strict;
use warnings;
use local::lib;
use JSON;
use Data::Dumper;
use File::Path "mkpath";

use ManipulateJSON qw(decode_json_file convert_events);

## "events" field from experiment description file can include both specific
## event names and metric names; profiler can record only specific events:
## each metric should be parsed to get the names of events it consists of.
sub parse_events {
  use List::MoreUtils qw(uniq first_index);
  my $metrics_file = decode_json_file("json/metrics.json");

  my @hw_events = @{$_[0]};
  my @new_hw_events;

  for my $events (@hw_events) {
    if (exists $metrics_file->{$events}) {
      push @new_hw_events, ($metrics_file->{$events} =~ m/[^0-9\/\+\*\-]+/g);
    }
    else {
      push @new_hw_events, $events;
    }
  }

  @new_hw_events = uniq(@new_hw_events);

  ## Specific event names should be converted if Perf is used
  @new_hw_events = @{convert_events(\@new_hw_events)};

  return @new_hw_events;
}

## Create experiment directories and prepare a hash of each individual
## experiment description
sub create_path_save_experim_data {
  my ($srcpath, $path, $non_common_parameters, $common_parameters, $hash_to_json) = @_;

  my $full_path = "$srcpath"."$path";
  ## Create a directory path
  mkpath($full_path);

  ## profiler_outpath for Amplifier and profiler_outfile for Perf
  my %temp_hash = (%{$non_common_parameters}, %{$common_parameters},
                    %{{"profiler_outpath" => [$full_path]}},
                    %{{"profiler_outfile" => [$full_path."perf.data"]}} );
  $hash_to_json->{"$path"} = \%temp_hash;
}

## Read specification files
##-------------------------------------------------------
my $conf = decode_json_file("json/conf.json");
my $experim_desc = decode_json_file("json/experim_desc.json");
##-------------------------------------------------------

## parameters that have different values for each experiment ('level'==true)
my @non_common_parameters;

## parameters common to all the experiments ('level'=false)
my %common_parameters; 

## Parse metrics and convert event names (if necessary)
if (exists $experim_desc->{"events"}) {
  @{$experim_desc->{"events"}} = parse_events($experim_desc->{"events"});
}

## Sort out experiment parameters depending on their "level" property
for my $param (keys %{$experim_desc}) {

  ## "repeat_num" must be treated differently. No such entry in conf.json
  next if ($param eq "repeat_num");


  if ($conf->{$param}{"level"} eq "true") {
    ## Save separately common parameter names to correctly create experiments'
    ## directories later (each non common parameter defines directory level)
    push(@non_common_parameters, [$param,
                                    @{$experim_desc->{$param}}]);  
  }
  else {
    ## Don't care about common parameters order, just put 'em into hash
    $common_parameters{$param} = \@{$experim_desc->{$param}};
  }
}

## We need to separate non_common parameter names from values, so that
## the precedence of parameter values is preserved (hashes impose no order)
my @non_common_parameter_names;
foreach (@non_common_parameters) { #is an array of arrays
  ## push the name of parameter
  push( @non_common_parameter_names, shift @{$_});
}

## Put all the non common parameter values into one formated string. Needed
## later to produce all possible combinations of them
my $glob = join (',', map ('{'.join(',', @$_).'}', @non_common_parameters));

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

## Path to the experiment result data
my $path;

## The final hash of experiments' configurations to be saved to json file
my %hash_to_json;

## glob() returns arrays of all possible non common parameter combinations
while (my $s = glob($glob)) {

  ## The following manipulations with non common parameter names/values is
  ## explained by the fact the directory tree must be uniform, thus the order
  ## of these parameters is important
  ##----------------------------------------------------------------------------

  ## Create an array of experiment non-common parameters values
  @non_common_param_vals = split(/,/, $s);

  my %non_common_parameters;
  for (my $i = 0; $i < @non_common_param_vals; $i++) {
    my @temp_arr = split (/ /, $non_common_param_vals[$i]);
    $non_common_parameters{$non_common_parameter_names[$i]} = \@temp_arr;
    ## Extract circuit name from the specified path to circuit
    if ($non_common_parameter_names[$i] eq "circuit") {
      $non_common_param_vals[$i] =~ s/.*\/([a-zA-Z0-9_-]*)\.cir/$1/;
    }
    $path=$path."$non_common_param_vals[$i]/";
  }
  ##----------------------------------------------------------------------------

  ## Handle the situation when each experiment is to be executed several
  ## times (tries). Each execution try must have its path=.../../try_#
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

      create_path_save_experim_data($srcpath, $path, \%non_common_parameters,
        \%common_parameters, \%hash_to_json);
      
      $path = $old_path;
    }
  }
  else {    # just one try is needed for each experiment
    create_path_save_experim_data($srcpath, $path, \%non_common_parameters,
      \%common_parameters, \%hash_to_json);
  }

  ## Reset path name for the next experiment
  $path = "";
}

## Save the experiments description hash into file
open(FH, ">json/full_experim_desc.json") || die "Cannot open file: $!\n" ;
print FH to_json(\%hash_to_json, {pretty => 1});
close(FH);
