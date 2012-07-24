package ParsePerfReport;
use strict;
use warnings;
use Exporter;
use JSON;
use Data::Dumper;
use Switch;
use IPC::System::Simple "capture";
use ManipulateJSON "decode_json_file";

our @ISA = qw(Exporter);
our @EXPORT = qw(parse_perf_report);

sub parse_hwevents {

  my $views = $_[0];

  my %parsed_reports;
  #my @event_count_files;

  for my $view_path (keys %{$views}) {
    my $result_folder = shift @{$views->{$view_path}{"profiler_outpath"}}; 
    my $perf_report = $result_folder."perf.data";
    my $output_perf_report = $result_folder."perf_out";
    my $parsed_report_name = "$result_folder"."parsed_report_hwevents.json";
    my $total_event_count_file = "$result_folder"."total_event_count.json";

    ## Do not generate a perf report if it already exists
    if (! -e $parsed_report_name) {  
      my $confs = decode_json_file("json/conf.json");
      my $comm = "perf report -n -t , -i $perf_report > \\
          $output_perf_report 2> $result_folder/perf_err.log";
      my @output = capture($comm);

      open(FH, "$output_perf_report")  || die "I Cannot open file: $!\n" ;
      my @file_arr;

      for (<FH>) {
        chomp $_;
        my @line_arr = split(/,/, $_);
        ## Don't add empty lines
        push (@file_arr, \@line_arr) if (@line_arr);
      }
      close(FH);

      my %result_hash;
      my %total_event_count;

      ## Populate %result_hash with function names
      for my $line (@file_arr) {
        for my $field (@{$line}) {
          ## Select a field with a function name
          if ($field =~ /^\[(\.)|(k)\]/) {
            $field =~ s/\[(\.|k)\]\s//; 
            $result_hash{$field} = {};
          }
        }
      }

      my $current_event = "";
      for my $line (@file_arr) {
        my $first_field = $line->[0];
        if (! ($first_field =~ m/^\#/) ) {
          my $event_val = $line->[1];
          my $current_func_name = $line->[4];
          $current_func_name =~ s/\[(\.|k)\]\s//;
          $result_hash{$current_func_name}{$current_event} = $event_val;
          $total_event_count{$current_event} += $event_val;
        }
        elsif ($first_field =~ m/^\#\sEvents/) {
          $first_field =~ s/.*\s(\S+)/$1/g;
          $current_event = $first_field;
        }
      }

      #print Dumper $result_hash{"bsim4_calc_mos"};
      #print Dumper %result_hash;
      #print Dumper %total_event_count;

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

sub parse_perf_report {
  my ($views, $extract_desc) = @_;

  #here we assume only one report type is specified
  ## No report type for Perf!
  #my $report_type = shift @{$extract_desc->{"report"}};

  #switch ($report_type) {
  #  case 'hw-events' {
      return parse_hwevents($views);
      #  }
      # case 'sfdump' {

      # }
      # else {

      #  }
      #}
  
}

1;
