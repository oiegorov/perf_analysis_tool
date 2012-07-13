use strict;
use warnings;
use JSON;
use Data::Dumper;

use ManipulateJSON "decode_json_file";
use ParseAmplReport qw(parse_ampl_report);

my $views = decode_json_file("json/views.json");
my $extract_desc = decode_json_file("json/extract_desc.json");

# for each type of the report, call the corresponding script to generate
my $reports = parse_ampl_report($views, $extract_desc);
#print Dumper $reports;

my $top_n = shift @{$extract_desc->{"func_num"}};
my @events = @{$extract_desc->{"events"}};
my $func_pattern = $extract_desc->{"func_pattern"}[0];

for my $report_name (@{$reports}) {
  
  print "\n";
  print "-------------------------------------------";
  print $report_name;
  print "-------------------------------------------\n";
  print "\n";
  print "Function ";
  for my $event (@events) {
    print "\t".$event;
  }
  print "\n";


  my $parsed_report = decode_json_file("$report_name");
  my %func_pattern_hash;

  ## Choose functions which correspond to user-specified pattern
  for my $funcs (keys %{$parsed_report}) {
    if ($funcs =~ /$func_pattern/) {
      $func_pattern_hash{"$funcs"} = $parsed_report->{$funcs};
    }
  }

  ## Sort selected functions depending on their rang in descending order
  my @sorted = sort {$func_pattern_hash{$a}->{"rang"} <=>
    $func_pattern_hash{$b}->{"rang"}} keys %func_pattern_hash;

  for (my $i = 0; $i < $top_n; $i++) {
    my $func_name = $sorted[$i];
    print $i+1 .". $func_name ";
    for my $event (@events) {
      #here we must take into account metric calculation;
      #my $metric_formulas = decode_json_file("json/metrics.json");
      #if (exists $metric_formulas->{$event}) {
      #  print "yeyeyeyeye\n";
        
      #}
      #else {
        print "\t".$func_pattern_hash{$func_name}->{$event};
      #}
    }
    print "\n";
    #print Dumper $func_pattern_hash{$func_name};
  }
}

# depending on the filters from $extract_desc, generate custom reports
