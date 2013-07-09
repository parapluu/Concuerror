#!/usr/bin/env bash

T=readers

echo "\\hline"
for i in 2 8; do
    f=0
    for t in --dpor --dpor_source --dpor_classic; do
        if [ $f -eq 0 ]; then
            echo "\multirow{3}{*}{$T} & \multirow{3}{*}{$i} & "
            echo -n "     o-DPOR &"
        elif [ $f -eq 1 ]; then
            echo -n " & & s-DPOR &"
        else
            echo -n " & &   DPOR &"
        fi
        f=$((f+1))
        ./concuerror_mem --noprogress -f testsuite/suites/dpor/src/$T.erl \
            -t $T $T $i -p inf $t \
            | grep "OUT" | sed 's/OUT//'
    done
    echo "\\hline"
done