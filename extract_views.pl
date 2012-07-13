use strict;
use warnings;
use local::lib;
use JSON;
use Data::Dumper;
use Scalar::Util 'reftype';
use List::MoreUtils 'first_index';

use ManipulateJSON "decode_json_file";

my $experims = decode_json_file("json/full_experim_desc.json");
my $extract_desc = decode_json_file("json/extract_desc.json");

my $same_experim = shift @{$extract_desc->{"same_experim"}};
## The logic of creating the "views" (those experiments that has
## specified parameters) lies in checking each experiment, if it
## satisfies the specified properties.

## To check if "view" is a hash and not a string "all"
if ( UNIVERSAL::isa($extract_desc->{"view"},'HASH') ) {
  foreach my $view_conf (keys %{$extract_desc->{"view"}}) {
    foreach my $experim_conf (keys %{$experims}) {
      ## Leave only one experiment if there were several tries
      if ( ($same_experim eq "false") and !("$experim_conf" =~ /try_1\/$/) 
          and ("$experim_conf" =~ /try_.\/$/) ) {
        delete $experims->{$experim_conf};
        next;
      }

      my $index = 0;
      foreach my $view_param (@{$extract_desc->{"view"}{$view_conf}}) {
        last if ($view_param eq "all"); 
        $index = first_index {$_ eq $view_param} @{$experims->{$experim_conf}{$view_conf}};
        ## index!=-1: experiment's parameter satisfies the view
        last if ($index != -1); 
      }
      ## Experiment's params don't satisfy the view: delete an experiment
      delete $experims->{$experim_conf} if ($index == -1);
    }
  }
}

open(FH, ">json/views.json") || die "Cannot open file: $!\n" ;
print FH to_json($experims, {pretty => 1});
close(FH);
