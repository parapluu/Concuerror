# Concuerror's 'real tests' suite

## Structure

This testsuite contains a number of suites, each following its own
logic.

Suites are structured in the following way:
`./suites/<suite_name>`

Each suite has a `Makefile` whose default target should run all tests
in the suite.

## How to run all the tests

From Concuerror's main directory, execute `make tests-real`.
