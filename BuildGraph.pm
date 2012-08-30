package BuildGraph;
use strict;
use warnings;
use Exporter;
use JSON;
use Data::Dumper;
use ManipulateJSON "decode_json_file";
use Number::Bytes::Human qw(format_bytes);

our @ISA = qw(Exporter);
our @EXPORT = qw(build_gen_code_graph);

## Parse the time obtained from >CPU TIME ..< to use in gnuplot, in the
## form "days+1 **h_**mn_**s"
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

  ## Handle hours..
  $time =~ s/^\s/0/;
  ## Truncate the milliseconds from total time
  $time =~ s/([0-9a-z\s]+\ds)(.*)/$1/;

  $time =~ s/\s\s/ /g;
  $time =~ s/\s/_/g;

  ## Calculate the number of days and recalculate hours
  ## the numbering of days starts from 1, not 0
  $time =~ m/(\d+)h/;
  my $hours = $1;
  my $days = sprintf("%d", ($hours / 24) + 1);
  $hours = $hours - (($days-1) * 24);
  $time =~ s/(\d+)(h)/$days $hours$2/;

  return $time;
}

sub build_gen_code_graph {

  my $main_path = $_[0];
  my $views = decode_json_file("${main_path}/views.json");
  my $extract_desc = decode_json_file("${main_path}/extract_desc.json");
  my %circuit_hash;

  ## Include transient simulation time and reslib.so size in each view
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
    ## Memorize the size of reslib.so file (in a pretty format)
    my $reslib_path = $res_folder."/reslib.so";
    my $reslib_size = format_bytes(-s $reslib_path);
    #my $reslib_size = -s $reslib_path;
    push @{$views->{$single_view}{"reslib_size"}}, $reslib_size;
    #-------------------------------------------------------------------

    ## Populate the circuit hash with experiment data
    my $circuit = $views->{$single_view}{"circuit"}[0];
    push @{$circuit_hash{$circuit}}, $views->{$single_view};
    #print $eldo_outpath, ": ", $reslib_size, ". ", $converted_time, "\n";
  }


  ## Find out the values of HW_DSS_SCHURS and NUM_CORES used in chosen
  ## experiments
  my @dss_schurs_num = @{$extract_desc->{"view"}{"define"}};

  ## To specify the max limit for xrange and x2range in gnuplot
  my $last_schur_val = $dss_schurs_num[$#dss_schurs_num];
  $last_schur_val =~ s/([A-Za-z_]*)([0-9]+)/$2/;

  ## To specify the min limit for xrange and x2range in gnuplot
  my $first_schur_val = $dss_schurs_num[0];
  $first_schur_val =~ s/([A-Za-z_]*)([0-9]+)/$2/;

  my @cores_num = @{$extract_desc->{"view"}{"num_cores"}};

  ## Main plotting cycle (for each specified circuit)
  for my $circuits (keys %circuit_hash) {

    ## Extract circuit name from the full path to circuit
    my $circuit_name = $circuits;
    $circuit_name =~ s/(.*)\/([A-Za-z0-9_-]+)\/[A-Za-z0-9_-]+.cir$/$2/;

    my $path_to_plot_data = $main_path."/plot_data_".$circuit_name;

    ## Create a file with data to plot by gnuplot
    #-------------------------------------------------------------------
    open (PLOT_DATA, ">".$path_to_plot_data) || die "Cannot open file for writing: $!\n";
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
      ## Need to start from 1, not 0, to be able to use logarithmic axis
      #$dss_schur_value += 1;
      print PLOT_DATA $dss_schur_value."\t\t\t";
      ## output only one reslib.so size column per hw_dss_schurs row
      my $cnt = 0;

      ## Output transient simulation time for each number of threads
      for my $core_num (@cores_num) {
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
    close(PLOT_DATA);
    #-------------------------------------------------------------------

    ## Output data we're about to plot
    print "\n\nPlotted data: \n------------------------------------\n";
    open (FH, "$path_to_plot_data");
    while (<FH>) { print $_; }

    ##------------------------------------------------------------------
    ## Part of plotting in Gnuplot
#set terminal x11 persist
    open PROC, "| ~fbaray/local/aol/bin/gnuplot " || die "Could not start gnuplot: $!";

print PROC "set terminal pngcairo size 1280, 1024\n";
print PROC "set output '",$main_path,"/graph_",$circuit_name,".png'\n";
print PROC "set title '(",$circuit_name,") Simulation Time vs. DSS_SCHURS Value'\n";
print PROC <<GNUPLOT;
set ytics nomirror
set y2tics
set ylabel "Simulation time (1 thread)"
set y2label "Simulation time (8 threads)"
set timefmt '%d %Hh_%Mmn_%Ss'
set format y '%d %T'
set ydata time
set format y2 '%d %T'
set y2data time


set xtics nomirror
set x2tics rotate -45
set xlabel "DSS_SCHURS value"
set x2label "reslib.so size"

set key right bottom
set grid x2tics

GNUPLOT

print PROC "set xrange [$first_schur_val:$last_schur_val]\n";
print PROC "set x2range [$first_schur_val:$last_schur_val]\n";

print PROC "plot '",$path_to_plot_data,"' using 1:3:x2tic(2) title '1 thread' axes x1y1 w linesp lc rgb 'red', ";
print PROC "'",$path_to_plot_data,"' using 1:5:x2tic(2) title '8 threads' axes x1y2 w linesp lc rgb 'blue'\n";
#  print PROC "e\n";
    close PROC;
    ##------------------------------------------------------------------

  }
}


#set xrange [0.1:2000000000]
#set x2range [0.1:2000000000]

#set logscale x
#set logscale x2

#set timefmt '%Hh_%Mmn_%Ss'
#set format y '%T'
#set ydata time
#set format y2 '%T'
#set y2data time

1;
