#!/bin/bash

concuerror="../concuerror"
results="./results"
prevDir=`pwd`

# Cleanup temp files
cd `dirname $0`
find . -name '*.beam' -exec rm {} \;
rm -rf $results/*

# Compile scenarios.erl
erlc scenarios.erl

# If we have arguments we should use this as
# tests, otherwise check them all
if [ $# -eq 0 ]; then
    tests=(`ls -d suites/*/src/*`)
else
    tests=("$@")
fi

# For every test do
for test in "${tests[@]}"; do
    unset files
    unset temp
    temp=(`echo $test | sed -e 's/suites\/\(\w\+\)\/src\/\(\w\+\)\(\.erl\)\?/\1 \2/'`)
    suite="${temp[0]}"
    name="${temp[1]}"
    if [ -d $test ]; then
        # Our test is a multi module directory
        dir=$test
        mod="test"
        files=(`ls $dir/*.erl`)
    else
        # Our test is a single module file
        dir=${test%/*}
        mod=$name
        files=$test
    fi
    # Create a dir to save the results
    mkdir -p $results/$suite
    # Compile it
    erlc -W0 -o $dir $dir/$mod.erl
    # And extract scenarios from it
    erl -noinput -pa . -pa $dir -s scenarios extract $mod -s init stop | \
    while read line; do
        # Get function and preemption bound
        unset temp
        temp=(`echo $line | sed -e 's/{\w\+,\(\w\+\),\(\w\+\)}/\1 \2/'`)
        fun="${temp[0]}"
        preb="${temp[1]}"
        printf "Running test %s-%s (%s, %s).." $suite $name $fun $preb
        # And run concuerror
        $concuerror --target $mod $fun --files "${files[@]}" \
            --output $results/$suite/$name-$fun-$preb.txt \
            --preb $preb --noprogress --nolog
        diff -I '<[0-9]\+\.[0-9]\+\.[0-9]\+>' \
            -I '#Ref<[0-9\.]\+>' \
            -uw suites/$suite/results/$name-$fun-$preb.txt \
            $results/$suite/$name-$fun-$preb.txt &> /dev/null
        if [ $? -eq 0 ]; then
            printf "\033[01;32mok\033[00m\n"
        else
            printf "\033[01;31mfailed\033[00m\n"
        fi
    done
done

# Cleanup temp files
find . -name '*.beam' -exec rm {} \;
cd $prevDir
