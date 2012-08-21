package BuildGraph;
use strict;
use warnings;
use Exporter;
use JSON;
use Data::Dumper;
use Switch;
use IPC::System::Simple "capture";
use ManipulateJSON "decode_json_file";
use Chart::Graph::Gnuplot qw(gnuplot);

our @ISA = qw(Exporter);
our @EXPORT = qw(build_gen_code_graph);

## Parse the time obtained from >CPU TIME ..< to use in gnuplot, in the
## form **h **mn **s
sub convert_time_for_gnuplot {
  my $time = $_[0];

  ## Seems we don't need it anymore
#  ## Add '0mn' for circuits that ran less than 1 minute
#  if ( !($time =~ m/[a-z0-9\s]+mn/) ) {
#    $time = "0mn ".$time;
#  }
#  ## Add '0h' for circuits that ran less than 1 hour
#  if ( !($time =~ m/\d+h/) ) {
#    $time = "0h ".$time;
#  }

  ## Truncate the milliseconds from total time
  $time =~ s/\s([0-9a-z\s]+\ds)(.*)/$1/;

  ## Replace spaces by '_' symbol
  $time =~ s/\s\s/ /g;
  $time =~ s/\s/_/g;

  return $time;
}


sub build_gen_code_graph {

  my $main_path = $_[0];
  my $views = decode_json_file("${main_path}/views.json");
  my $extract_desc = decode_json_file("${main_path}/extract_desc.json");
  my %circuit_hash;

  for my $single_view (keys %$views) {
    my $eldo_outpath = $views->{$single_view}{"eldo_outpath"}[0];
    open(FH, "${eldo_outpath}/log_execution") || die "Cannot open file: $!\n" ;
    my $eldo_log = do { local $/; <FH> };
    close(FH);

    #-------------------------------------------------------------------
    my $trans_time;

    ## Extract the transient simulation time ( for monothread we have
    ## "Elapsed CPU.." for multithread - just "Elapsed..."
    $eldo_log =~ m/.*^Elapsed[0-9a-z:\sCPU]+\(([0-9a-z\s]+)\)/ms;
    $trans_time = $1;

    my $converted_time = convert_time_for_gnuplot($trans_time);
    push @{$views->{$single_view}{"transient_time"}}, $converted_time;
    #-------------------------------------------------------------------

    #-------------------------------------------------------------------
    ## Find the *.res folder
    my $res_folder = `find $eldo_outpath -maxdepth 1 -name "*.res" -type d`;    
    chomp $res_folder;
    ## Memorize the size of reslib.so file
    my $reslib_path = $res_folder."/reslib.so";
    my $reslib_size = -s $reslib_path;
    push @{$views->{$single_view}{"reslib_size"}}, $reslib_size;
    #-------------------------------------------------------------------

    ## Populate the circuit hash with experiment data
    my $circuit = $views->{$single_view}{"circuit"}[0];
    push @{$circuit_hash{$circuit}}, $views->{$single_view};
    #print $eldo_outpath, ": ", $reslib_size, ". ", $converted_time, "\n";
  }

  open (PLOT_DATA, ">plot_data") || die "Cannot open file for writing: $!\n";

  ## Find out the values of HW_DSS_SCHURS and NUM_CORES used in chosen
  ## experiments
  my @dss_schurs_num = @{$extract_desc->{"view"}{"define"}};
  my @cores_num = @{$extract_desc->{"view"}{"num_cores"}};

  for my $circuits (keys %circuit_hash) {

    ## Print comments for each data set (one data set per circuit)
    ## Circuit name
    print PLOT_DATA "# Circuit: ", $circuit_hash{$circuits}[0]->{"circuit"}[0],
      "\n";
    print PLOT_DATA "# hw_dss_schurs \treslib.so \t";
    for (@cores_num) {
      print PLOT_DATA "$_ thread \t";
    }
    print PLOT_DATA "\n";
    
    for my $dss_schur (@dss_schurs_num) {
      ## Leave only the numeric value of DSS_SCHURS_number
      my $dss_schur_value = $dss_schur;
      $dss_schur_value =~ s/([A-Za-z_]*)([0-9]+)/$2/;
      print PLOT_DATA $dss_schur_value."\t\t\t";
      my $cnt = 0;

      for my $core_num (@cores_num) {
        #print $core_num." ";
        for my $single_circuit (@{$circuit_hash{$circuits}}) {
          if ( ($single_circuit->{"num_cores"}[0] eq $core_num) and
               ($single_circuit->{"define"}[0] eq $dss_schur)) {
            if ($cnt==0) {
              print PLOT_DATA $single_circuit->{"reslib_size"}[0], " \t";
              $cnt++;
            }
            print PLOT_DATA $single_circuit->{"transient_time"}[0], " \t";
          }
        }
      }
      print PLOT_DATA "\n";
    }
    
    print PLOT_DATA "\n\n";
  }
  close(PLOT_DATA);

  ##------------------------------------------------------------------
  ## Part of plotting in Gnuplot
  my ($x, $y);
  open PROC, "| ~fbaray/local/aol/bin/gnuplot " || die "Could not start gnuplot: $!";
  print PROC <<GNUPLOT;
set terminal x11 persist
set timefmt '%Hh_%Mmn_%Ss'
set format y '%T'
set ydata time
plot [0:*]["00:00:00":*] "plot_data" index 0 u 1:3 w linesp, "" index 0 u 1:4 w linesp
GNUPLOT
  close PROC;

}

1;

