#!/usr/bin/env python

import os
import re
import sys
import glob
import subprocess
from ctypes import c_int
from multiprocessing import Process, Lock, Value, BoundedSemaphore


#---------------------------------------------------------------------
# Extract scenarios from the specified test

def runTest(test):
    global dirname
    global results
    # test has the format of '.*/suites/<suite_name>/src/<test_name>(.erl)?'
    # Split the test in suite and name components using pattern matching
    t = test.split("/")
    suite = t[-3]
    name = os.path.splitext(t[-1])[0]
    if os.path.isdir(test):
        # Our test is a multi module directory
        dirn = test     # directory
        modn = "test"   # module name
        files = glob.glob(dirn + "/*.erl")
    else:
        dirn = os.path.dirname(test)
        modn = name
        files = [test]
    # Create a dir to save the results
    try:
        os.mkdir(results + "/" + suite)
    except OSError:
        pass
    # Compile it
    os.system("erlc -W0 -o %s %s/%s.erl" % (dirn, dirn, modn))
    # And extract scenarios from it
    pout = subprocess.Popen(
            ["erl -noinput -pa %s -pa %s -s scenarios extract %s -s init stop"
            % (dirname, dirn, modn)], stdout=subprocess.PIPE, shell=True)
    procS = []
    for scenario in pout.stdout:
        # scenario has the format of {<mod_name>,<func_name>,<preb>}\n
        scen = scenario.strip("{}\n").split(",")
        # And run the test
        p = Process(target=runScenario,
                args=(suite, name, modn, scen[1], scen[2], files))
        p.start()
        procS.append(p)
    pout.stdout.close()
    # Wait
    for p in procS:
        p.join()

#---------------------------------------------------------------------
# Run the specified scenario and print the results

def runScenario(suite, name, modn, funn, preb, files):
    global concuerror
    global results
    global dirname
    global sema
    global lock
    global total_tests
    global total_failed
    sema.acquire()
    # Run concuerror
    os.system("%s --target %s %s --files %s --output %s/%s/%s-%s-%s.txt --preb %s --quiet"
            % (concuerror, modn, funn, ' '.join(files), results, suite, name,
               funn, preb, preb))
    # Compare the results
    a = "%s/suites/%s/results/%s-%s-%s.txt" % (dirname, suite, name, funn, preb)
    b = "%s/%s/%s-%s-%s.txt" % (results, suite, name, funn, preb)
    equalRes = equalResults(a, b)
    sema.release()
    # Print the results
    lock.acquire()
    total_tests.value += 1
    if equalRes:
        print "%-10s %-20s %-40s  \033[01;32mok\033[00m" % \
                (suite, name, "("+funn+",  "+preb+")")
    else:
        total_failed.value += 1
        print "%-10s %-20s %-40s  \033[01;31mfailed\033[00m" % \
                (suite, name, "("+funn+",  "+preb+")")
    lock.release()

def equalResults(f1, f2):
    try:
        fp1 = open(f1, 'r')
    except IOError:
        return False
    try:
        fp2 = open(f2, 'r')
    except IOError:
        fp1.close()
        return False
    while True:
        l1 = fp1.readline()
        l2 = fp2.readline()
        if (l1 != l2) and (not ignoreLine(l1)):
            fp1.close(); fp2.close()
            return False
        if not l1:
            fp1.close(); fp2.close()
            return True

def ignoreLine(line):
    global ignore_matches
    for match in ignore_matches:
        if re.search(match, line):
            return True
    return False

#---------------------------------------------------------------------
# Main program

# Compile some regular expressions
match_pids = re.compile("<\d+\.\d+\.\d+>")
match_refs = re.compile("#Ref<[\d\.]+>")
match_file = re.compile("suites/.+/src/.*\.erl")
ignore_matches = [match_pids, match_refs, match_file]

# Get the directory of Concuerror's testsuite
dirname = os.path.normpath(os.path.dirname(sys.argv[0]))
concuerror = dirname + "/../concuerror"
results = dirname + "/results"

# Cleanup temp files
os.system("find %s -name '*.beam' -exec rm {} \;" % dirname)
os.system("rm -rf %s/*" % results)

# Compile scenarios.erl
os.system("erlc %s/scenarios.erl" % dirname)

# If we have arguments we should use them as tests,
# otherwise check them all
if len(sys.argv) > 1:
    tests = sys.argv[1:]
    tests = [item.rstrip('/') for item in tests] 
else:
    tests = glob.glob(dirname + "/suites/*/src/*")

# Print header
print "Concuerror's Testsuite\n"
print "%-10s %-20s %-40s  %s" % \
        ("Suite", "Test", "(Function,  Preemption Bound)", "Result")
print "---------------------------------------" + \
      "------------------------------------------"

# Create share integers to count tests and
# a lock to protect printings
lock = Lock()
total_tests = Value(c_int, 0, lock=False)
total_failed = Value(c_int, 0, lock=False)

# How many threads we want (default 4)
threads = os.getenv("THREADS", "")
if threads == "":
    threads = "4"
sema = BoundedSemaphore(int(threads))

# For every test do
procT = []
for test in tests:
    p = Process(target=runTest, args=(test,))
    p.start()
    procT.append(p)
# Wait
for p in procT:
    p.join()

# Print overview
print "\nOVERALL SUMMARY for test run"
print "  %d total tests, which gave rise to" % len(tests)
print "  %d test cases, of which" % total_tests.value
print "  %d caused unexpected failures" % total_failed.value

# Cleanup temp files
os.system("find %s -name '*.beam' -exec rm {} \;" % dirname)
