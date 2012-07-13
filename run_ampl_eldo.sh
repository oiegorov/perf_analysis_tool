#!/bin/bash

case "$1" in
  general)
    collect_type=nehalem-general-exploration
    ;;
  memory)
    collect_type=nehalem-memory-access
    ;;
  uops)
    collect_type=nehalem-cycles-uops
    ;;
  *)
    echo "please, precise analysis type (-collect ...)\n"
    ;;
esac

ampl_folder=$2
circuit_name=$3
#eldo_output_folder=/tmp/garbage/
eldo_output_folder=$4
proc_num=$5

echo $collect_type

#numactl --physcpubind=1 /opt/intel/vtune_amplifier_xe/bin64/amplxe-cl -collect $collect_type \
/opt/intel/vtune_amplifier_xe/bin64/amplxe-cl -collect $collect_type \
-r $ampl_folder /nobackup/oiegorov/eldo_wa/aol-dbg_opt/eldo_src/eldo_vtune_64.exe \
-hm_physbind_0 -prof_start 0 $circuit_name -outpath $eldo_output_folder \
-use_proc $proc_num 
