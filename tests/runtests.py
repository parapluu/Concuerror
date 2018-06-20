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
    global sema1
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
    # Compile it
    os.system("erlc -W0 -o %s %s/%s.erl" % (dirn, dirn, modn))
    # And extract scenarios from it
    pout = subprocess.check_output(
        ["erl -boot start_clean -noinput -pa %s -pa %s -s scenarios extract %s -s init stop"
         % (dirname, dirn, modn)], shell=True).splitlines()
    procS = []
    for scenario in pout:
        # scenario has the format of {<mod_name>,<func_name>,<preb>}\n
        scen = scenario.strip("{}").split(",")
        # And run the test
        p = Process(
            target=runScenario,
            args=(suite, name, modn, scen[1], scen[2], scen[3:], files))
        sema.acquire()
        p.start()
        procS.append(p)
    # Wait
    for p in procS:
        p.join()
    # Must happen late, in case the test has/needs exceptional
    os.remove("%s/%s.beam" % (dirn,modn))
    sema1.release()
        
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
        dpor_flag = "--dpor=optimal"
        file_ext = "-dpor"
        dpor_output = ""
    elif "optimal" in flags:
        dpor_flag = "--dpor=optimal"
        file_ext = "-optimal"
        dpor_output = ""
    elif "source" in flags:
        dpor_flag = "--dpor=source"
        file_ext = "-source"
        dpor_output = "source"
    elif "persistent" in flags:
        dpor_flag = "--dpor=persistent"
        file_ext = "-persistent"
        dpor_output = "persistent"
    else:
        dpor_flag = "--dpor=none"
        file_ext = "-nodpor"
        dpor_output = "disabled"
    if preb == "inf":
        bound = ""
        bound_type = ""
        preb_output = ""
    else:
        bound = ("-b %s") % (preb)
        if "bpor" in flags:
            bound_type = "-c bpor"
            preb_output=("%s/bpor") % (preb)
            preb=("%s-bpor") % (preb)
        else:
            bound_type = "-c delay"
            preb_output=("%s/delay") % (preb)
    if funn == modn:
        funn_output = ""
    else:
        funn_output = funn
    txtname = "%s-%s-%s%s.txt" % (name, funn, preb, file_ext)
    rslt = "%s/%s/results/%s" % (results, suite, txtname)
    try:
        os.remove(rslt)
    except OSError:
        pass
    # Run concuerror
    status = os.system(
        ("%s -kq --assume_racing false"
         " %s -f %s"
         " --output %s"
         " -m %s -t %s %s %s"
         )
        % (concuerror, dpor_flag, " ".join(files),
           rslt, modn, funn, bound, bound_type))
    # Compare the results
    has_crash = "crash" in flags
    orig = "%s/suites/%s/results/%s" % (dirname, suite, txtname)
    equalRes = equalResults(suite, name, orig, rslt)
    if status != 512 and not has_crash:
        finished = True
    elif status == 512 and has_crash:
        finished = True
    else:
        finished = False
    # Print the results
    lock.acquire()
    total_tests.value += 1
    suitename = re.sub('\_tests$', '', suite)
    logline = ("%-8s %-63s"
               % (suitename,
                  name+", "+funn_output+", "+preb_output+", "+dpor_output))
    if equalRes and finished:
        # We don't need to keep the results file
        try:
            os.remove(rslt)
        except:
            pass
        print "%s \033[01;32m    ok\033[00m" % (logline)
              
    else:
        total_failed.value += 1
        print "%s \033[01;31mfailed\033[00m" % (logline)
    lock.release()
    sema.release()

def equalResults(suite, name, orig, rslt):
    global dirname
    beamdir = "%s/suites/%s/src" % (dirname, suite)
    cmd = ("erl -boot start_clean -noinput -pa %s/%s -pa %s"
           " -run scenarios exceptional \"%s\" \"%s\" \"%s\""
           % (beamdir, name, beamdir, name, orig, rslt))
    if 0 == subprocess.call(cmd, shell=True):
        return True
    else:
        return 0 == subprocess.call("bash differ %s %s" % (orig, rslt), shell=True)

#---------------------------------------------------------------------
# Main program

# Get the directory of Concuerror's testsuite
dirname = os.path.abspath(os.path.dirname(sys.argv[0]))
concuerror = os.getenv("CONCUERROR", dirname + "/../bin/concuerror")
results = os.path.abspath(dirname + "/results")

# Ensure made
assert 0 == os.system("%s --version" % (concuerror))
assert 0 == os.system("erlc scenarios.erl")

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
        threads = str(max(1, cpu_count() - 1))
    except:
        threads = "1"

# Print header
print "Concuerror's Testsuite (THREADS=%d)\n" % int(threads)
print "%-8s %-63s %s" % \
      ("Suite", "Module, Test (' '=Module), Bound (' '=inf), DPOR (' '=optimal)", "Result")
print "-------------------------------------------------------------------------------"

# Create share integers to count tests and
# a lock to protect printings
lock = Lock()
total_tests = Value(c_int, 0, lock=False)
total_failed = Value(c_int, 0, lock=False)

sema = BoundedSemaphore(int(threads))
sema1 = BoundedSemaphore(int(threads))

# For every test do
procT = []
for test in tests:
    p = Process(target=runTest, args=(test,))
    procT.append(p)
    sema1.acquire()
    p.start()
# Wait
for p in procT:
    p.join()

# Print overview
print "\nOVERALL SUMMARY for test run"
print "  %d total tests, which contained" % len(tests)
print "  %d scenarios, of which" % total_tests.value
print "  %d caused unexpected failures!" % total_failed.value

if total_failed.value != 0:
    exit(1)
