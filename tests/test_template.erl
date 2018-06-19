%%% See README.md for more details about the structure of these suites.

-module(test_template).

%% Each scenario corresponds to a 0-arity function that is exported.
-export([test/0]).

%% The scenarios/0 function (explained below) should also be exported.
-export([scenarios/0]).
%% The exceptional/0 function (explained below) is optional.
-export([exceptional/0]).

%% If a test requires specific options for Concuerror, they should be
%% placed in the following attribute.
-concuerror_options_forced([]).

%%------------------------------------------------------------------------------

%% The `scenarios/0` function returns a list of tests.
%%
%% - The list contains atoms or tuples.
%% - A test is specified by a three-element tuple.
%% - Atoms are converted to single-element tuples.
%% - Missing mandatory elements are substituted by a default value.
%% - More, optional test specification, can be added as additional tuple
%%   elements.
%% - Tuple element meanings:
%%   - first element is test function's name (0-arity)
%%   - second element is preemption bound (default is 'inf')
%%   - third element is DPOR algorithm (default is 'optimal')
%%   - additional elements are:
%%     - the atom `crash`, if Concuerror should crash when executing the test
%%     - a specialization for the bounding algorithm (bpor)

scenarios() -> [{test, inf, optimal}].

%% A test may have a different pass condition. The `exceptional/0`
%% function can be used to define an anonymous function with inputs
%% the filenames of the expected and actual outputs. Any check can then
%% be performed. The result of the anonymous function (which should be
%% `true`/`false`) is used to decide pass/fail.
exceptional() ->
  fun(_Expected, _Actual) ->
      %% Cmd = "grep \"<text>\" ",
      %% [_,_,_|_] = os:cmd(Cmd ++ Actual),
      false
  end.

%%------------------------------------------------------------------------------

%% This is a dummy test function.
test() ->
  ok.
