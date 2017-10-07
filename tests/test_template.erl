-module(test_template).

%% Each scenario corresponds to a 0-arity function that is exported.
-export([test/0]).

%% These are also exported functions.
-export([scenarios/0]).
-export([exceptional/0]).

%% If a test requires specific options for Concuerror, they should be
%% placed in the following attribute.
-concuerror_options_forced([]).

%%------------------------------------------------------------------------------

%% The `scenarios/0` function returns a list of tuples each containing
%% the scenario's function name and preemption bound (typically inf).
%% Tuples may optionally contain a third term, specifying what dynamic
%% partial order reduction algorithm should be used.
scenarios() -> [{test, inf, optimal}].

%% A test may have a different pass condition. The `exceptional/0`
%% function can be used to define an anonymous function with inputs
%% the filenames of the expected and actual outputs. Any test can then
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
