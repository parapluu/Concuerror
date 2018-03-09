# Concuerror's 'output comparison' testsuite

## Structure

This testsuite contains a number of **suites**, each
containing a number of **tests**, each consisting of a single module
or a collection of modules.

Suites and tests are structured in the following way:
`./suites/<suite_name>/src/<test_name>`

Each test contains a main module:
* For tests consisting of a single module, the main module is
  `<test_name>.erl`.
* For tests consisting of a collection of modules, a directory
  `<test_name>` should exist, containing all the modules. The main
  module is `<test_name>/test.erl`.

Each test contains a number of scenarios, specified in the main
module.  [`test_template.erl`](./test_template.erl) is a sample main
module, with instructions and explanations.

## Logic

All tests contained in this directory are based on comparing
Concuerror's output report against a reference output.

**The script normally checks only the last line (total number of
  interleavings explored and exit status)**.

Tests can also describe exceptional passing criteria (not based on
output comparison). See [`test_template.erl`](./test_template.erl) for
more details.

If a test is failing, Concuerror's current output is kept in:

`results/<suite_name>/results/<test_name>-<scenario_info>.txt`

The reference output for each scenario is stored in:
`suites/<suite_name>/results/<test_name>-<scenario_info>.txt`

An easy way to inspect failures is to run a visual diff tool
e.g. `meld` like this: `meld suites/ results/`

The main point is differences in the final line. Other lines may
differ without affecting the result; they are also kept in the
reference file to give an idea of Concuerror's expected behaviour.

## How to run tests

1) To run all the tests execute `./runtests.py`.

2) To run all the tests from specific suites, e.g. SUITE1 and SUITE2
   execute `./runtests.py suites/SUITE1/src/* suites/SUITE2/src/`.

3) To run specific tests `./runtests.py suites/SUITE1/src/<TEST1>.erl
suites/SUITE2/src/<TEST2>`

The script extracts and runs scenarios in parallel, trying to use all
the cores in the system. If you want to limit this, set the
environment variable `THREADS` to a lower number.

## How to add test cases in any suite:

1) If the test requires Concuerror to analyze a single file
   (`<test>.erl`) place it in the suite's `src` directory.

2) If analysis of more files is needed place them all in a new
   directory `src/TEST`. This directory must include a `test.erl`
   module.

3) Run `runtests.py` with your test, inspect the output file and once
   satisfied copy it in the suite's `results` directory.

## How to create a new suite:

1) Create a sub-directory in the `suites` directory.

2) In the suite's directory create subdirectories `src` and `results`.

3) Add tests as described in previous section.
