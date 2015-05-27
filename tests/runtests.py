#!/usr/bin/env python

import os
import re
import sys
import glob
import subprocess
from ctypes import c_int
from multiprocessing import Process, Lock, Value, BoundedSemaphore, cpu_count


#---------------------------------------------------------------------
# Extract scenarios from the specified test
def runTest(test):
    global dirname
    global results
    # test has the format of '.*/suites/<suite_name>/src/<test_name>(.erl)?'
    # Split the test in suite and name components using pattern matching
    rest1, name = os.path.split(test)
    rest2 = os.path.split(rest1)[0]
    suite = os.path.split(rest2)[1]
    name = os.path.splitext(name)[0]
    if os.path.isdir(test):
        # Our test is a multi module directory
        dirn = test     # directory
        modn = "test"   # module name
        files = glob.glob(dirn + "/*.erl")
    else:
        dirn = rest1
        modn = name
        files = [test]
    # Create a dir to save the results
    try:
        os.makedirs(results + "/" + suite + "/results")
    except OSError:
        pass
    sema.acquire()
    # Compile it
    os.system("erlc -W0 -o %s %s/%s.erl" % (dirn, dirn, modn))
    # And extract scenarios from it
    pout = subprocess.Popen(
        ["erl -noinput -pa %s -pa %s -s scenarios extract %s -s init stop"
         % (dirname, dirn, modn)], stdout=subprocess.PIPE, shell=True)
    sema.release()
    procS = []
    for scenario in pout.stdout:
        # scenario has the format of {<mod_name>,<func_name>,<preb>}\n
        scen = scenario.strip("{}\n").split(",")
        # And run the test
        p = Process(
            target=runScenario,
            args=(suite, name, modn, scen[1], scen[2], scen[3:], files))
        p.start()
        procS.append(p)
    pout.stdout.close()
    # Wait
    for p in procS:
        p.join()
    # Cleanup temp files
    os.remove("%s/%s.beam" % (dirn, modn))


#---------------------------------------------------------------------
# Run the specified scenario and print the results
def runScenario(suite, name, modn, funn, preb, flags, files):
    global concuerror
    global results
    global dirname
    global sema
    global lock
    global total_tests
    global total_failed
    if "dpor" in flags:
        dpor_flag = "--optimal=true"
        file_ext = "-dpor"
        dpor_output = "dpor"
    elif "source" in flags:
        dpor_flag = "--optimal=false"
        file_ext = "-source"
        dpor_output = "source"
    else:
        dpor_flag = ""
        file_ext = ""
        dpor_output = "full"
    sema.acquire()
    # Run concuerror
    status = os.system(
        ("%s -kiq --timeout -1 --assume_racing false --show_races false"
         " %s -f %s"
         " --output %s/%s/results/%s-%s-%s%s.txt"
         " -m %s -t %s"
         )
        % (concuerror, dpor_flag, " -f ".join(files),
           results, suite, name, funn, preb, file_ext,
           modn, funn))
    # Compare the results
    has_crash = "crash" in flags
    orig = ("%s/suites/%s/results/%s-%s-%s%s.txt"
            % (dirname, suite, name, funn, preb, file_ext))
    rslt = ("%s/%s/results/%s-%s-%s%s.txt"
            % (results, suite, name, funn, preb, file_ext))
    equalRes = equalResults(orig, rslt)
    if status == 0 and not has_crash:
        finished = True
    elif status != 0 and has_crash:
        finished = True
    else:
        finished = False
    sema.release()
    # Print the results
    lock.acquire()
    total_tests.value += 1
    if equalRes and finished:
        # We don't need to keep the results file
        try:
            os.remove(rslt)
        except:
            pass
        print "%-10s %-20s %-50s  \033[01;32mok\033[00m" % \
              (suite, name, "("+funn+",  "+preb+",  "+dpor_output+")")
    else:
        total_failed.value += 1
        print "%-10s %-20s %-50s  \033[01;31mfailed\033[00m" % \
              (suite, name, "("+funn+",  "+preb+",  "+dpor_output+")")
    lock.release()


def equalResults(orig, rslt):
    return 0 == subprocess.call("bash differ %s %s" % (orig, rslt), shell=True)

#---------------------------------------------------------------------
# Main program

# Get the directory of Concuerror's testsuite
dirname = os.path.abspath(os.path.dirname(sys.argv[0]))
concuerror = os.path.abspath(dirname + "/../concuerror")
results = os.path.abspath(dirname + "/results")

# Cleanup temp files
os.system("make -j -C %s/.. default tests/scenarios.beam" % dirname)
os.system("rm -rf %s/*" % results)

# If we have arguments we should use them as tests,
# otherwise check them all
if len(sys.argv) > 1:
    tests = sys.argv[1:]
    tests = [os.path.abspath(item) for item in tests]
else:
    tests = glob.glob(dirname + "/suites/*/src/*")

# How many threads we want (default, number of CPUs in the system)
threads = os.getenv("THREADS", "")
if threads == "":
    try:
        threads = str(cpu_count())
    except:
        threads = "4"

# Print header
print "Concuerror's Testsuite (%d threads)\n" % int(threads)
print "%-10s %-20s %-50s  %s" % \
      ("Suite", "Test", "(Function,  Preemption Bound,  Reduction)", "Result")
print "---------------------------------------------" + \
      "---------------------------------------------"

# Create share integers to count tests and
# a lock to protect printings
lock = Lock()
total_tests = Value(c_int, 0, lock=False)
total_failed = Value(c_int, 0, lock=False)

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
print "  %d caused unexpected failures!" % total_failed.value

if total_failed.value != 0:
    exit(1)
