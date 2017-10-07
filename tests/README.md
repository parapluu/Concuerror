# Concuerror's testsuite

Concuerror's testsuite contains a number of **suites**, each
containing a number of **tests**, each consisting of a single module
or a collection of modules.

Suites and tests are structured in the following way:
`tests/suite/<suite_name>/src/<test_name>`

Each test contains a main module:
* For tests consisting of a single module, the main module is
  `<test_name>.erl`.
* For tests consisting of a collection of modules, a directory
  `<test_name>` should exist, containing all the modules. The main
  module is `<test_name>/test.erl`.

Each test contains a number of scenarios, specified in the main
module.  [`test_template.erl`](./test_template.erl) is a sample main
module, with instructions and explanations.


## To run the testsuite:

1) To run all the tests simple execute `./runtests.py`.

2) To run all the tests from specific suites, e.g. SUITE1 and SUITE2
   execute `./runtests.py suites/SUITE1/src/* suites/SUITE2/src/`.

3) To run specific tests `./runtests.py suites/SUITE1/src/<TEST1>.erl
suites/SUITE2/src/<TEST2>`

If a test is failing, Concuerror's actual output is kept in:

`results/<suite_name>/results/<test_name>-<scenario_info>.txt`

The expected output for each scenario are saved in:
`suite/<suite_name>/results/<test_name>-<scenario_info>.txt`

**The script normally checks only the total number of interleavings
  explored (last line)**.

Handling of exceptional cases is described in
[`test_template.erl`](./test_template.erl).

An easy way to inspect failures is to run a visual diff tool
e.g. `meld` like this: `meld suites/ results/`

The script extracts and runs scenarios in parallel, trying to use all
the cores in the system. If you want to limit this, set the
environment variable `THREADS` to a lower number.

## To add test cases in any suite:

1) If the test requires Concuerror to analyze a single file
   (`<test>.erl`) place it in the suite's `src` directory.

2) If analysis of more files is needed place them all in a new
   directory `src/TEST`. This directory must include a `test.erl`
   module.

3) Run `runtests.py` with your test, inspect the output file and once
   satisfied copy it in the suite's `results` directory.

## To create a new suite:

1) Create a sub-directory in `suites` directory.

2) In the suite's directory create subdirectories `src` and `results`.

3) Add tests as described in previous section.
