use strict;
use warnings;
use JSON;
use Data::Dumper;
use 5.0100;

use ManipulateJSON  qw(decode_json_file convert_events);
use ParseAmplReport qw(parse_ampl_report);
use ParsePerfReport qw(parse_perf_report);

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
    $event = convert_events($event); 
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

my $views = decode_json_file("json/views.json");
my $extract_desc = decode_json_file("json/extract_desc.json");
my $conf = decode_json_file("json/conf.json");

# for each type of the report, call the corresponding script to generate
my $reports;
if ($conf->{"profiler_cmd"} =~ m/^perf/) {
  $reports = parse_perf_report($views, $extract_desc);
}
else {
  $reports = parse_ampl_report($views, $extract_desc);
}

print "yaaaaa\n";

my $top_n = shift @{$extract_desc->{"func_num"}};
my @events = @{$extract_desc->{"events"}};
my $func_pattern = $extract_desc->{"func_pattern"}[0];

for my $report_name (keys %{$reports}) {
  
  print "\n";
  print "-------------------------------------------";
  print $report_name;
  print "-------------------------------------------\n";
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

  ## Sort selected functions according to the sorting parameter
  my $sort_param = $extract_desc->{"sort"}[0];

  my $metric_formulas = decode_json_file("json/metrics.json");
  my $sort_param_is_metric = "false";

  ## If sorting parameter is a metric 
  if (exists $metric_formulas->{$sort_param}) {

    ## Calculate metric for all the selected functions
    $sort_param_is_metric = "true";


    for my $func_name (keys %func_pattern_hash) {
      $func_pattern_hash{$func_name}->{$sort_param} =
        calculate_metric($metric_formulas->{$sort_param}, $func_pattern_hash{$func_name});
    }
  }

  if ($sort_param_is_metric eq "false") {
    $sort_param = convert_events($sort_param);
  }

  for my $func_name (keys %func_pattern_hash) {
    if (!exists $func_pattern_hash{$func_name}->{$sort_param}) {
      delete $func_pattern_hash{$func_name};
    }
  }

  my @sorted = reverse sort {$func_pattern_hash{$a}->{$sort_param} <=>
    $func_pattern_hash{$b}->{$sort_param}} keys %func_pattern_hash;
  
  ## Contains {"event"->"sum"} for chosen events of all selected functions
  my %partial_event_sum;

  for (my $i = 0; $i < $top_n; $i++) {
    if (exists $sorted[$i]) {
      my $func_name = $sorted[$i];
      printf "%-4s", $i+1;
      printf "%-45s", "$func_name";
      for my $event (@events) {
        if ( exists $metric_formulas->{$event} ) {
          if (! (exists  $func_pattern_hash{$func_name}->{$event}) ) {
            my $val = calculate_metric($metric_formulas->{$event}, $func_pattern_hash{$func_name});
            $func_pattern_hash{$func_name}->{$event} = $val;
          }
          printf "%-30.5f", "$func_pattern_hash{$func_name}->{$event}";
        }
        else {
          my $converted_event = convert_events($event);
          if ( (!exists $func_pattern_hash{$func_name}->{$converted_event}) 
              or (!defined $func_pattern_hash{$func_name}->{$converted_event})) {
            $func_pattern_hash{$func_name}->{$converted_event} = 0;
          }
          $partial_event_sum{$converted_event} += $func_pattern_hash{$func_name}->{$converted_event};
          printf "%-30.0f", "$func_pattern_hash{$func_name}->{$converted_event}";
        }
      }
      print "\n";
    }
  }

  print "\n";
  printf "%-49s", " ";
  for my $selected_event (keys %partial_event_sum) {
    if ($total_event_count_file->{$selected_event} ne "0") {
      my $percent = $partial_event_sum{$selected_event} /
        $total_event_count_file->{$selected_event} * 100;
      printf "%-30.3f", $percent ;
    }
    else {
      printf "%-30s", "illegal division by zero"; 
    }
  }
  print "\n";
}

