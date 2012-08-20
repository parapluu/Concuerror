#!/bin/bash

concuerror="../concuerror"

# Cleanup temp files
find . -name '*.beam' -exec rm {} \;
rm -rf temp
mkdir temp

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
        # Our test is a multi module test
        dir=$test
        mod="test"
        files=(`ls $dir/*.erl`)
    else
        # Our test is a single module test
        dir=${test%/*}
        mod=$name
        files=$test
    fi
    mkdir -p temp/$suite
    # Compile it
    erlc -W0 -o $dir $dir/$mod.erl
    # And extract scenarios from it
    erl -noinput -pa . -pa $dir -s scenarios extract $mod -s init stop | \
    while read line; do
        # Get function and preemption bound
        unset temp
        temp=(`echo $line | sed -e 's/{\w\+,\(\w\+\),\([0-9]\+\)}/\1 \2/'`)
        fun="${temp[0]}"
        preb="${temp[1]}"
        printf "Running test %s-%s (%s, %s)..\n" $suite $name $fun $preb
        # And run concuerror
        $concuerror analyze --target $mod $fun --files "${files[@]}" \
            --output temp/results.ced --preb $preb --no_progress > /dev/null
        $concuerror show --snapshot temp/results.ced \
            --details --all > temp/$suite/$name-$fun-$preb.txt
        diff -uw suites/$suite/results/$name-$fun-$preb.txt \
            temp/$suite/$name-$fun-$preb.txt
    done
done

# Cleanup temp files
find . -name '*.beam' -exec rm {} \;
