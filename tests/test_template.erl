-module(test_template).

-export([test/0]).

-export([scenarios/0]).
-export([exceptional/0]).

-concuerror_options_forced([]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf, optimal}].

exceptional() ->
  fun(_Expected, _Actual) ->
      %% Cmd = "grep \"<text>\" ",
      %% [_,_,_|_] = os:cmd(Cmd ++ Actual),
      false
  end.

%%------------------------------------------------------------------------------

test() ->
  ok.
