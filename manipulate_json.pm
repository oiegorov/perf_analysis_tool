package manipulate_json;
use strict;
use warnings;
use JSON;
use Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(decode_json_file);

sub decode_json_file {
  local $/;  # to enable slurp: read the whole file into one string
  open (FH, $_[0]) || die "Cannot open file $_[0]: $!\n";
  my $json_file = <FH>;
  close(FH);

  return from_json($json_file);
}

1;
