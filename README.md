This document explains the functionality of the tool.

The general logic of using the tool is:

Launch all the experiments that could be interesting to analyze.  This
process is automated and requires only several concise specification
files. After the performance results of all the experiments are obtained,
show only specific information (e.g. only 20 functions with the biggest
CPI ratio for 2 specific circuits ran on 4 cores). Such reports can be
generated using the performance data collected during the
first step.

See the Vtune Amplifier and Perf use cases and sample configuration
files in the bottom of this document.

The first thing to do is to specify the following files:

----------------------------------------------------------------------
1. experim_desc.json
----------------------------------------------------------------------
Contains the parameters of the experiments to launch. 

The required parameters are:
* ("circuit"). The full path(s) to the .cir file(s).
* ("num_cores") number of cores. 
* ("eldo_outpath") directory to save eldo output.
For VTune Amplifier:
* ("analysis") analysis type. Each VTune''s analysis type groups a
predefined set of hardware performance events. The list of all
available analysis types can be checked on
http://software.intel.com/sites/products/documentation/hpc/amplifierxe/en-us/2011Update/lin/ug_docs/index.htm
For Perf:
* ("events") individual event names to capture with hardware perfomance counters. 
Event names should be written in the Intel format. The mapping
of Perf events to Intel events is specified in events.json file. The
list of hardware events available on specific Intel architecture can be
checked on Intel website.

The additional parameters are:
* ("repeat_num") number of experiment repetitions. By default each
experiment is launched only once.


----------------------------------------------------------------------
2. conf.json
----------------------------------------------------------------------
Contains all the general experiment configurations.

The required:
* ("main_path") directory to save experiment results in.
* ("eldo_cmd") path to eldo executable.
* ("profiler_cmd") path to profiler executable.
* configuration for each parameter from "experim_desc.json" file as well
as optional eldo/profiler parameters. Each parameter includes the following fields:
-- "target": either "eldo" or "profiler".
-- "command": Which option should be included in the eldo/profiler
command to use the parameter?
-- "level": "true" if a new experiment should be run for each
parameter''s value. Otherwise, "false".
The user should also specify a command to add an output path for
VTune Amplifier ("profiler_outpath") or an output file for Perf
("profiler_outfile").

----------------------------------------------------------------------
3. metrics.json
----------------------------------------------------------------------
Contains the formulas to compute performance metrics. Events should be
written in Intel format, e.g.
```
{
  "CPI": "CPU_CLK_UNHALTED.THREAD/INST_RETIRED.ANY",
  ...
}
```


----------------------------------------------------------------------
4. events.json
----------------------------------------------------------------------
Specifies the correspondence between Intel and Performance Counters for
Linux (PCL) event names, e.g:
```
{
  "CPU_CLK_UNHALTED.THREAD": "cycles",
  ...
}
```

----------------------------------------------------------------------
5. experim_desc.json
----------------------------------------------------------------------
Specifies the information we want to include in a particular performance
report. 
At first, the views should be chosen. A view is a particular set
of experiments having some specific parameters (e.g. a view could be a
set of all the circuits ran on 4 cores, or a single circuit ran on 1
core several times).
After a particular set of experiments is chosen, the user can specify
more precisely which performance information will be included in the
report. The possible parameters are:
* ("func_pattern") to output only the functions which correspond to
specified regex.
* ("sort") to sort the chosen functions based on the value of a
specific performance event/metric.
* ("func_num") include only N functions with the biggest sorting
parameter's value.
* ("events") function's event/metric values to write in the
report.
* ("same_experim") if "false" - include the results of only a single
experiment''s run. If "true" - all the repetitive experiment execution
results will be included in the report.

Required for Vtune Amplifier:
* ("report") specifies the report type. Only "hw-events" is supported
for the moment. The full list of available reports can be checked on
http://software.intel.com/sites/products/documentation/hpc/amplifierxe/en-us/2011Update/lin/ug_docs/index.htm




The tool consists of the following perl scripts:

----------------------------------------------------------------------
script prepare_experiments.pl
----------------------------------------------------------------------
This script setups all the experiments to be conducted. Based on the
user-specified circuits, number of cores, and other specifications from
experim_desc.json, as well as parameter configurations from conf.json,
the script creates descriptions for each experiment (written to
full_experim_desc.json file) and a directory tree to store the results.

----------------------------------------------------------------------
script launch_commands.pl
----------------------------------------------------------------------
Constructs and executes the commands taking as an input the descriptions of
experiments created by prepare_experiments.pl script and configurations
from conf.json file. The results of profiling are saved to the created
by prepare_experiments.pl script directories.
----------------------------------------------------------------------

After all the experiments have been conducted, the next step lies
in generating various information about obtained performance data.

----------------------------------------------------------------------
script extract_views.pl
----------------------------------------------------------------------
Simply checks which views are specified in extract_desc.json file and
leaves only those experiments that satisfy these views. Generated file
views.json contains a subset of functions from full_experim_desc.json.

----------------------------------------------------------------------
script create_report.pl
----------------------------------------------------------------------
Generates a report using specific to profiler .pm perl module. 

The goal of ParseAmplReport.pm and ParsePerfReport.pm perl modules is to
provide a uniform representation of collected performance data generated
by profilers (different profilers have different formats for result
representation). The uniform representation is written in .json format
as

```
"function1": {
  "event1": "value",
  "event2": "value",
  ..
}
"function2": {
  ..
  }
..
```

These perl modules also generate a total_event_count.json file with the
total count of each event for all the selected functions in the form:

```
"event1": "total_value",
"event2": "total_value"
..
```

This way, the create_report.pl script outputs as well the relative % of
events collected for displayed functions to the total number of events
for all the functions.

----------------------------------------------------------------------
                          USE CASES
----------------------------------------------------------------------

1. Using Perf profiler

We start with launching the first script prepare_experiments.pl without
passing to it any arguments:
```
$ ./prepare_experiments.pl

>No experiment directory is specified. The following directory was
>automatically created:
>/home/oiegorov/experim_tool/experiment____14_13_50__30_07_2012/
>Sample configurations files were copied to
>/home/oiegorov/experim_tool/experiment____14_13_50__30_07_2012/

>Please modify the configuration files and run this script again
>specifying the newly created experiment directory:
>./prepare_experiments.pl /home/oiegorov/experim_tool/experiment____14_13_50__30_07_2012
```

As we can see, a new directory for our experiments was created and sample
configurations files were copied to it. Before proceeding and running the
same script passing a created directory as an argument, we need to
modify the configuration files in order to launch those tests that we
want to, and not the default ones.

At first, let''s see what should be checked in conf.json file:

```
{
  "eldo_cmd": "/home/oiegorov/eldo_wa/eldo/aol-dbg_opt/eldo_src/eldo_vtune_64.exe",
  "profiler_cmd": "perf record",
  "circuit": 
  {
    "target": "eldo",
    "command": "",
    "level": "true"
  },
  "num_cores":
  {
    "target": "eldo",
    "command": "-use_proc",
    "level": "true"
  },
  "events":
  {
    "target": "profiler",
    "command": "-e",
    "level": "false"
  },
  "eldo_outpath":
  {
    "target": "eldo",
    "command": "-outpath",
    "level": "false"
  },
  "profiler_outfile":
  {
    "target": "profiler",
    "command": "-o",
    "level": "false"
  }
}
```

Pay attention to the "profiler_cmd" field and the fields with the
"target": "profiler", to use correct Perf options. "profiler_outfile"
and "events" fields are required for Perf.

Next, we modify experim_desc.json file to specify the experiments we
want to launch. For example:

```
{
  "circuit":
  [
      "/home/oiegorov/eldo_examples/good/sim64k/sim64k.cir",
      "/home/oiegorov/eldo_examples/bad/VSC1414_VCO_modified/VSC1414-VCO.cir"
  ],
  "num_cores": ["1", "4"],
  "events": ["CPU_CLK_UNHALTED.THREAD", "INST_RETIRED.ANY", "CPI"],
  "repeat_num": [ "2" ]
}
```

Such configuration tells that we want to test two circuits on 1 and 8 cores
each, collect the number of cycles and instructions, as well as automatically
calculate CPI metric. Each experiment should be launched two times.

The next step is to add some specific metric formulas to metrics.json file or
add some new events to events.json file. 

We now ready to execute prepare_experiments.pl and launch_commands.pl scripts,
providing the name of experiment directory:

```
$ ./prepare_experiments /home/oiegorov/experim_tool/experiment____14_13_50__30_07_2012/
$ ./launch_commands.pl /home/oiegorov/experim_tool/experiment____14_13_50__30_07_2012/
```

After all the tests are executed we normally would like to output some
performance reports. To do this, we need to specify what exactly should
appear in the report. This is specified in extract_desc.json file:

```
{
  "view":
  {
    "circuit":
    [
      "/home/oiegorov/eldo_examples/bad/test_PLL_modified/test_PLLrevF_sstPLLsch0-tran.cir"
    ],
    "num_cores": ["1", "4"]
  },
  "events": ["CPU_CLK_UNHALTED.THREAD", "INST_RETIRED.ANY", "CPI"],
  "func_num": [ "15" ],
  "func_pattern": [".*"],
  "sort": ["CPU_CLK_UNHALTED.THREAD"],
  "same_experim": ["false"]
}
```

What is specified here is that we want to output the performance data only for
one circuit, ran on 1 and 8 cores, "same_experim" says that the performance
data only for a single repetition must be outputed. The events we want to see
are CPU cycles, instructions and CPI metrics. The functions will be sorted by
the number of cycles in descending order, with only first 15 of them displayed.
We do not impose any restrictions on function names, as regex ".*" specifies.

Here is a generated sample report:

```
------------------------------------/home/oiegorov/experim_tool/experiment____14_13_50__30_07_2012/test_PLLrevF_sstPLLsch0-tran/1/try_1/parsed_report_hwevents.json------------------------------------
```

    Function                                     CPU_CLK_UNHALTED.THREAD       INST_RETIRED.ANY              CPI
    1   bsim4_calc_mos                               2271                          1172                          1.93771
    2   fss_subckt_set_IQ_derive_64                  649                           780                           0.83205
    3   solve2_00000000000036bf                      547                           747                           0.73226
    4   FMath_exp                                    547                           442                           1.23756
    5   fss_subckt_get2_64_64                        525                           615                           0.85366
    6   schur2_00000000000036bf                      517                           679                           0.76141
    7   fss_device_load_factor_64_eldo_solver        504                           771                           0.65370
    8   fss_subckt_set_dVI_64                        396                           804                           0.49254
    9   bsim4_is_bypass_ext                          364                           243                           1.49794
    10  FMath_log                                    339                           187                           1.81283
    11  schur2_000000000000375c                      334                           422                           0.79147
    12  solve2_000000000000375c                      320                           359                           0.89136
    13  fss_subckt_sub_dIQ_derive_64                 295                           315                           0.93651
    14  bsim4_to_nodal                               267                           270                           0.98889
    15  sdm_subckt_inst_apply                        239                           242                           0.98760

          Total %                                    44.802                        44.550

```
------------------------------------/home/oiegorov/experim_tool/experiment____14_13_50__30_07_2012/test_PLLrevF_sstPLLsch0-tran/4/try_1/parsed_report_hwevents.json------------------------------------
```

    Function                                     CPU_CLK_UNHALTED.THREAD       INST_RETIRED.ANY              CPI
    1   bsim4_calc_mos                               7277                          5734                          1.26910
    2   tsk_thrd_consume_forever                     7083                          2081                          3.40365
    3   tsk_main                                     5228                          2167                          2.41255
    4   fss_subckt_get2_64_64                        3092                          2688                          1.15030
    5   solve2_00000000000036bf                      2494                          3419                          0.72945
    6   fss_subckt_set_IQ_derive_64                  2202                          3790                          0.58100
    7   schur2_00000000000036bf                      2020                          3109                          0.64973
    8   solve2_000000000000375c                      2000                          1631                          1.22624
    9   fss_device_load_factor_64_eldo_solver        1869                          3465                          0.53939
    10  schur2_000000000000375c                      1789                          1978                          0.90445
    11  FMath_exp                                    1701                          1941                          0.87635
    12  fss_subckt_set_dVI_64                        1528                          3507                          0.43570
    13  bsim4_is_bypass_ext                          1334                          1055                          1.26445
    14  tsk_next_in_pool_consume.clone.2             1312                          936                           1.40171
    15  fss_subckt_sub_dIQ_derive_64                 1295                          1544                          0.83873

          Total %                                    50.223                        46.487

