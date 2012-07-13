#!/bin/bash

perl build_tree.pl
perl launch_commands.pl
perl extract_views.pl
perl create_report.pl

