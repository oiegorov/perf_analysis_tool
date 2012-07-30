package ParseAmplReport;
use strict;
use warnings;
use Exporter;
use JSON;
use Data::Dumper;
use Switch;
use IPC::System::Simple "capture";
use ManipulateJSON "decode_json_file";

our @ISA = qw(Exporter);
our @EXPORT = qw(parse_ampl_report);

sub parse_hwevents {

  my $views = $_[0];
  my $main_path = $_[1];

  my %parsed_reports;

  for my $view_path (keys %{$views}) {

    my $result_folder = shift @{$views->{$view_path}{"profiler_outpath"}}; 
    my $ampl_report = $result_folder."ampl_report_hwevents.csv";
    my $parsed_report_name = "$result_folder"."parsed_report_hwevents.json";
    my $total_event_count_file = "$result_folder"."total_event_count.json";

    ## Do not generate an amplifier report if it already exists
    if (! -e $parsed_report_name) {  
      my $confs = decode_json_file("${main_path}/conf.json");
      ## Generate an Amplifier report in .csv format
      my @output = capture("$confs->{'profiler_cmd'}"." -report hw-events -result-dir $result_folder -report-output=$ampl_report -format=csv -csv-delimiter=comma");

      open(FH, "$ampl_report")  || die "I Cannot open file: $!\n" ;
      my @file_arr;

      for (<FH>) {
        chomp $_;
        my @line_arr = split(/,/, $_);
        push (@file_arr, \@line_arr);
      }
      close(FH);
       
      my @hw_events;
      for my $hw_event_name (@{$file_arr[0]}) {
        if ($hw_event_name ne 'Function' and
            $hw_event_name ne 'Module') {
          $hw_event_name =~ s/(\S+):Hardware.*/$1/;
          push @hw_events, $hw_event_name;
        }
      }

      my %result_hash;
      my %total_event_count;
      for my $event_name (@hw_events) {
        $total_event_count{$event_name} = 0;
      }

      #for each function line
      # memorize first field as function's name
      # populate subhash
      # write key => value pair where key is function's name, value is
      # subhash
        
      for (my $i = 1; $i < scalar(@file_arr); $i++) {
        ## Save function's name
        my $func_name = $file_arr[$i]->[0];

        ## Treat one special case (wrong name of the function)
        next if (substr($func_name,0,1) eq '"');

        my %func_hash;
        $func_hash{"rang"} = $i;
        $func_hash{"module"} = $file_arr[$i]->[1];

        for (my $j = 2; $j < scalar(@{$file_arr[$i]}); $j++) {
          my $hw_event_index = $j - 2;
          $func_hash{"$hw_events[$hw_event_index]"} = $file_arr[$i]->[$j];
          $total_event_count{"$hw_events[$hw_event_index]"} += $file_arr[$i]->[$j];
        }

        $result_hash{$func_name} = \%func_hash;
      }

      open(FH, ">$parsed_report_name") || die "Cannot open file: $!\n" ;
      print FH to_json(\%result_hash, {pretty => 1});
      close(FH);
      open(FH, ">$total_event_count_file") || die "Cannot open file: $!\n" ;
      print FH to_json(\%total_event_count, {pretty => 1});
      close(FH);
    }

    $parsed_reports{$parsed_report_name} = $total_event_count_file;
  }

  return \%parsed_reports;

}

sub parse_ampl_report {
  my ($views, $extract_desc, $main_path) = @_;

  #here we assume only one report type is specified
  my $report_type = shift @{$extract_desc->{"report"}};

  switch ($report_type) {
    case 'hw-events' {
      return parse_hwevents($views, $main_path);
    }
    case 'sfdump' {

    }
    else {

    }
  }
  
}

1;
