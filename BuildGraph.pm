package BuildGraph;
use strict;
use warnings;
use Exporter;
use JSON;
use Data::Dumper;
use Switch;
use IPC::System::Simple "capture";
use ManipulateJSON "decode_json_file";

our @ISA = qw(Exporter);
our @EXPORT = qw(build_gen_code_graph);

sub build_gen_code_graph {

  print "yeyey!!!\n";
}

1;

