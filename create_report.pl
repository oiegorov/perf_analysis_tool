#!/usr/bin/perl

use strict;
use warnings;
use JSON;
use Data::Dumper;
use 5.0100;

use ManipulateJSON  qw(decode_json_file convert_events);
use ParseAmplReport qw(parse_ampl_report);
use ParsePerfReport qw(parse_perf_report);

my $main_path;
if (! exists $ARGV[0]) {
  print "Please specify experiment directory.\n";
  exit;
}
else {
  $main_path = shift @ARGV;
}


## Parse metric and calculate its value
sub calculate_metric {
  my $formula = $_[0];
  my $func_values = $_[1];

  ## Dots are not allowed in var names in Math::Symbolic
  $formula =~ s/\./_DOT_/g;

  ## Parse metric formula
  use Math::Symbolic;
  my $tree = Math::Symbolic->parse_from_string($formula);
  my ($sub) = Math::Symbolic::Compiler->compile_to_sub($tree);

  ## Substitute dots back
  $formula =~ s/_DOT_/./g;

  ## Extract hw event names from the formula, sort them alphabetically
  ## Sorting is needed to make $sub work properly
  my @event_names = sort ( $formula =~ m/[^0-9\/\+\*\-]+/g );


  ## Create an array of event values in corresponding order
  my @event_vals;

  for (@event_names) {
    my $event = $_;
    ## Convert VTune event to get Perf's event value
    $event = convert_events($main_path, $event); 
    my $event_func_val = $func_values->{$event};
    ## If an event is undef for some function -- it has a 0 value
    if (defined $func_values->{$event}) {
      push @event_vals, $func_values->{$event};
    }
    else {
      push @event_vals, 0;
    }
  }

  ## Substitute hw event values into formula and get the result
  my $result;
  eval {
    $result = $sub->(@event_vals);
  };
  if ($@) {
    if($@ =~ /Illegal division by zero/) {
      #return "undefined";
      return -1;
    } 
    else {
      die $@;
    }
  }
    
  return $result;
}

my $views = decode_json_file("${main_path}/views.json");
my $extract_desc = decode_json_file("${main_path}/extract_desc.json");
my $conf = decode_json_file("${main_path}/conf.json");

# depending on the profiler, call the corresponding script to generate the report
my $reports;
if ($conf->{"profiler_cmd"} =~ m/^perf/) {
  $reports = parse_perf_report($views, $extract_desc, $main_path);
}
else {
  $reports = parse_ampl_report($views, $extract_desc, $main_path);
}

## The number of functions to display
my $top_n = shift @{$extract_desc->{"func_num"}};
my @events = @{$extract_desc->{"events"}};
my $func_pattern = $extract_desc->{"func_pattern"}[0];

## for each experiment - display the report
for my $report_name (keys %{$reports}) {
  
  print "\n";
  print "------------------------------------";
  print $report_name;
  print "------------------------------------\n";
  print "\n";
  printf "%-4s", " ";
  printf "%-45s", "Function";
  for my $event (@events) {
    printf "%-30s", "$event";
  }
  print "\n";


  my $parsed_report = decode_json_file("$report_name");
  my $total_event_count_file = decode_json_file($reports->{$report_name});
  
  my %func_pattern_hash;

  ## Choose functions which correspond to user-specified pattern
  for my $funcs (keys %{$parsed_report}) {
    if ($funcs =~ /$func_pattern/) {
      $func_pattern_hash{"$funcs"} = $parsed_report->{$funcs};
    }
  }

  my $sort_param = $extract_desc->{"sort"}[0];

  my $metric_formulas = decode_json_file("${main_path}/metrics.json");
  my $sort_param_is_metric = "false";

  ## If sorting parameter is a metric 
  if (exists $metric_formulas->{$sort_param}) {

    $sort_param_is_metric = "true";

    ## Calculate metric for all the selected functions
    for my $func_name (keys %func_pattern_hash) {
      $func_pattern_hash{$func_name}->{$sort_param} =
        calculate_metric($metric_formulas->{$sort_param}, $func_pattern_hash{$func_name});
    }
  }

  ## Need to convert sorting parameter if it is an event
  if ($sort_param_is_metric eq "false") {
    $sort_param = convert_events($main_path, $sort_param);
  }

  ## Get rid of functions that do not have a sorting parameter (i.e. it's value
  ## iz zero)
  for my $func_name (keys %func_pattern_hash) {
    if (!exists $func_pattern_hash{$func_name}->{$sort_param}) {
      delete $func_pattern_hash{$func_name};
    }
  }

  ## Sort selected functions according to the sorting parameter (in descending
  ## order)
  my @sorted = reverse sort {$func_pattern_hash{$a}->{$sort_param} <=>
    $func_pattern_hash{$b}->{$sort_param}} keys %func_pattern_hash;
  
  ## Contains {"event"->"sum"} for chosen events of all selected functions
  my %partial_event_sum;

  for (my $i = 0; $i < $top_n; $i++) {
    if (exists $sorted[$i]) { # check that the num of selected funcs < $top_n
      my $func_name = $sorted[$i];
      printf "%-4s", $i+1;
      printf "%-45s", "$func_name";
      for my $event (@events) {
        if ( exists $metric_formulas->{$event} ) {
          if (! (exists  $func_pattern_hash{$func_name}->{$event}) ) {
            ## If an event is actually a metric & is not the sorting parameter
            ## means, that it was not calculated before. Need to do it now.
            my $val = calculate_metric($metric_formulas->{$event},
              $func_pattern_hash{$func_name});
            $func_pattern_hash{$func_name}->{$event} = $val;
          }
          printf "%-30.5f", "$func_pattern_hash{$func_name}->{$event}";
        }
        else {
          my $converted_event = convert_events($main_path, $event);
          if ( (!exists $func_pattern_hash{$func_name}->{$converted_event}) 
              or (!defined $func_pattern_hash{$func_name}->{$converted_event})) {
            $func_pattern_hash{$func_name}->{$converted_event} = 0;
          }
          ## We only increment total sum if an event is actually a hw event
          $partial_event_sum{$converted_event} +=
            $func_pattern_hash{$func_name}->{$converted_event};
          printf "%-30.0f", "$func_pattern_hash{$func_name}->{$converted_event}";
        }
      }
      print "\n";
    }
  }

  print "\n";
  printf "%-49s", "      Total %";
  ## For each event - display the % the selected funcs contribute to the total
  ## value of the event.

  my @events_copy = @events;
  for my $selected_event (@events_copy) {
    if (convert_events($main_path, $selected_event) ne "-1") {
      $selected_event = convert_events($main_path, $selected_event);
      if ($total_event_count_file->{$selected_event} ne "0") {
        my $percent = $partial_event_sum{$selected_event} /
          $total_event_count_file->{$selected_event} * 100;
        printf "%-30.3f", $percent ;
      }
      else {
        printf "%-30s", "illegal division by zero"; 
      }
    }
    else {
      printf "%-30s", "";
    }
  }

  print "\n\n";

}

