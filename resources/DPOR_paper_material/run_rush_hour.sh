#!/usr/bin/env bash

T=rush_hour

echo "\\hline"
for i in -; do
    f=0
    for t in --dpor --dpor_source --dpor_classic; do
        if [ $f -eq 0 ]; then
            echo "\multirow{3}{*}{rush\_hour} & \multirow{3}{*}{$i} & "
            echo -n "     o-DPOR &"
        elif [ $f -eq 1 ]; then
            echo -n " & & s-DPOR &"
        else
            echo -n " & &   DPOR &"
        fi
        f=$((f+1))
        ./concuerror_mem --noprogress  -f testsuite/suites/resources/src/manolis/*.erl \
            -t rush_hour test_2workers_benchmark -p inf $t | \
            grep "OUT" | sed 's/OUT//'
    done
    echo "\\hline"
done