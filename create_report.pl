#!/usr/bin/perl

use strict;
use warnings;
no warnings 'closure';
use JSON;
use Data::Dumper;
use 5.0100;
use Data::Walk; 

use ManipulateJSON  qw(decode_json_file convert_events);
use ParseAmplReport qw(parse_ampl_report);
use ParsePerfReport qw(parse_perf_report);
use BuildGraph qw(build_gen_code_graph);

my $main_path;
if ( (! exists $ARGV[0]) || (! ($ARGV[0] =~ m/\//) ) ) {
  print "Please specify experiment directory.\n";
  exit;
}
else {
  $main_path = $ARGV[0];
}

if (! exists $ARGV[1]) {
  print "Please specify report type.\n";
  exit;
}
elsif ($ARGV[1] eq "graph") {
    build_gen_code_graph($main_path);
  }
elsif ($ARGV[1] eq "table") {
    plot_tip_func_table($main_path);
  }

exit;


#----------------------------------------------------------------------------
sub convert_hw_event {
  my $event = $_[0];
  if ($event =~ m/^r([a-zA-Z0-9]){3,4}$/) {
    $event =~ /r0*([a-zA-Z1-9]+)/;
    $event = "0x".$1;
  }

  return $event;
}
#----------------------------------------------------------------------------

#----------------------------------------------------------------------------
sub extract_func_patterns {
  my $func_groups = $_[0];
  my @func_patterns;

  ## Extract only function patterns from multidimensional hash
  sub process {
    if ( (ref($_) eq 'ARRAY') ) {
      for my $pattern (@{$_}) {
       push @func_patterns, $pattern;
      }
    }
  }

  walk \&process, $func_groups;

  ## Construct a single regex to match any of func patterns
  my $pattern_regex;
  for my $single_pattern (@func_patterns) {
    $pattern_regex .= "(".$single_pattern.")";
  }
  $pattern_regex =~ s/\)\(/\)|\(/g;

  return $pattern_regex;
}
#----------------------------------------------------------------------------

#----------------------------------------------------------------------------
sub extract_func_groups {
  my $func_groups = $_[0];
  my $func_pattern_hash = $_[1];

  my %groups_hash;

  sub process_2 {
    my $elem = $_;
    if ( (ref($elem) eq 'HASH') ) {
      for my $hash_keys (keys %{$elem}) {
        if (ref($elem->{$hash_keys}) eq 'ARRAY') {
          $groups_hash{$hash_keys} = $elem->{$hash_keys};
        }
      }
    }
  }
  walk \&process_2, $func_groups;

  my $pattern_regex;
  for my $group_key (keys %groups_hash) {
    $pattern_regex = "";
    for (@{$groups_hash{$group_key}}) {
      $pattern_regex .= "(".$_.")";
    }
    $pattern_regex =~ s/\)\(/\)|\(/g; 
    $groups_hash{$group_key} = $pattern_regex;
  }

  for my $group_key (keys %groups_hash) {
    my $group_regex = $groups_hash{$group_key};
    $groups_hash{$group_key} = {};
    for my $func_name (keys %{$func_pattern_hash}) {
      if ($func_name =~ m/$group_regex/) {
        $groups_hash{$group_key}{$func_name} =
            $func_pattern_hash->{$func_name};
      }
    }
  }

  return \%groups_hash;
}
#----------------------------------------------------------------------------

#----------------------------------------------------------------------------
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
#----------------------------------------------------------------------------

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
my @func_groups = $extract_desc->{"func_pattern"};

## for each experiment - display the report
for my $report_name (keys %{$reports}) {
  
  ## Parse eldo log file and extract global elapsed time value
  my $eldo_log = $report_name;
  $eldo_log =~ s/(.*)\/[A-Za-z_.]+/$1\/eldo_output/;
  open(FH, "${eldo_log}/log_execution") || die "Cannot open file: $!\n" ;
  $eldo_log = do { local $/; <FH> };
  close(FH);
  $eldo_log =~ /.*GLOBAL\sELAPSED\sTIME\s(.*)<\*/;
  my $elapsed_time = $1;

  my $parsed_report = decode_json_file("$report_name");
  my $total_event_count_file = decode_json_file($reports->{$report_name});

  print "\n";
  print "------------------";
  print $report_name;
  print "------------------\n";
  print "ELAPSED TIME: ", $elapsed_time, "\n"; 
  #print "Total cycles: ", $total_event_count_file->{"cycles"}, "\n"; 
  print "\n";
  printf "%-4s", " ";
  printf "%-45s", "Function";
  for my $event (@events) {
    printf "%-30s", "$event";
  }
  print "\n";
  
  my %func_pattern_hash;

  my $func_groups_json = decode_json_file("${main_path}/func_groups.json");
  my $pattern_regex = extract_func_patterns($func_groups_json, \@func_groups);

  ## Choose functions which correspond to user-specified pattern
  for my $funcs (keys %{$parsed_report}) {
    if ($funcs =~ /$pattern_regex/) {
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
    $sort_param = convert_hw_event($sort_param);
  }

  ## Get rid of functions that do not have a sorting parameter (i.e. its value
  ## iz zero)
  for my $func_name (keys %func_pattern_hash) {
    if (!exists $func_pattern_hash{$func_name}->{$sort_param}) {
      delete $func_pattern_hash{$func_name};
    }
  }

  ## STARTING FROM HERE WE NEED TO PUT FUNCS INTO GROUPS
  my $groups = extract_func_groups($func_groups_json, \%func_pattern_hash);
  
  my $tabulation = "";
  my $level = 0;

  my %total_group_result;

#----------------------------------------------------------------------------
sub hash_walk {
    my ($hash, $key_list, $callback) = @_;
    while (my ($k, $v) = each %$hash) {
        # Keep track of the hierarchy of keys, in case
        # our callback needs it.
        push @$key_list, $k;

        if (ref($v) eq 'HASH') {
          ## Add tabulation for next group level
          print $tabulation, "--------$k-----------------------------\n";
          $tabulation .= "\t";
          ## Recurse.
          hash_walk($v, $key_list, $callback);
        }
        else {
            # Otherwise, invoke our callback, passing it
            # the current key and value, along with the
            # full parentage of that key.
            my $percent_event_hash = $callback->($k, $v, $key_list);
            pop @$key_list;
            ## add to all the parent groups
            for my $parent_group (@$key_list) {
              for my $event (keys %{$percent_event_hash}) {
                $total_group_result{$parent_group}{$event} += $percent_event_hash->{$event};
              }
            }
            next;
        }


        chop $tabulation;

        print $tabulation, "-------------------------------------\n";
        print $tabulation;
        printf "%-49s", "      Total %";
          my @events_copy = @events;

        for my $selected_event (@events_copy) {

          if (convert_events($main_path, $selected_event) ne "-1") {
            $selected_event = convert_events($main_path, $selected_event);
            $selected_event = convert_hw_event($selected_event);
            printf "%-30.3f", $total_group_result{$k}{$selected_event};
          }
        }

        print "\n";

        pop @$key_list;
    }
}
#----------------------------------------------------------------------------

#----------------------------------------------------------------------------
sub print_keys_and_value {
  my ($k, $v, $key_list) = @_;
  #printf "k = %-8s  v = %-4s  key_list = [%s]\n", $k, $v, "@$key_list";
  #print Dumper $v;

  my @sorted;
  my %func_pattern_hash_group = %{$groups->{$k}};

  print $tabulation,"-------$k-------------\n";
  ## Sort selected functions according to the sorting parameter (in
  ## descending order)
  @sorted = reverse sort {$func_pattern_hash_group{$a}->{$sort_param} <=>
  $func_pattern_hash_group{$b}->{$sort_param}} keys %func_pattern_hash_group;

  ## Contains {"event"->"sum"} for chosen events of all selected functions
  my %partial_event_sum;

  for (my $i = 0; $i < $top_n; $i++) {
    if (exists $sorted[$i]) { # check that the num of selected funcs < $top_n
      my $func_name = $sorted[$i];
      printf $tabulation,"%-4s", $i+1;
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
          $converted_event = convert_hw_event($converted_event);
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

  print $tabulation;
  printf "%-49s", "      Total %";
  ## For each event - display the % the selected funcs contribute to the total
  ## value of the event.

  my @events_copy = @events;
  my $percent;
  my %percent_event_hash;
  for my $selected_event (@events_copy) {
    if (convert_events($main_path, $selected_event) ne "-1") {
      $selected_event = convert_events($main_path, $selected_event);
      $selected_event = convert_hw_event($selected_event);
      if ((exists $total_event_count_file->{$selected_event}) and 
           (exists $partial_event_sum{$selected_event}) ) {
        $percent = $partial_event_sum{$selected_event} / 
          $total_event_count_file->{$selected_event} * 100;
        printf "%-30.3f", $percent ;
      }
      else {
        $percent = 0;
        printf "%-30s", "0"; 
      }
    }
    else {
      $percent = -1;
      printf "%-30s", "";
    }

    $percent_event_hash{$selected_event} = $percent;
  }

  print "\n\n";
  
  return \%percent_event_hash;
}
#----------------------------------------------------------------------------

  hash_walk($func_groups_json, [], \&print_keys_and_value);

}

