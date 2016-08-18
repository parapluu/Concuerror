-module(test_template).

-export([test/0]).

-export([concuerror_options/0]).
-export([scenarios/0]).
-export([exceptional/0]).

%%------------------------------------------------------------------------------

concuerror_options() -> [].

scenarios() -> [{test, inf, dpor}].

exceptional() ->
  fun(_Expected, _Actual) ->
      %% Cmd = "grep \"<text>\" ",
      %% [_,_,_|_] = os:cmd(Cmd ++ Actual),
      false
  end.

%%------------------------------------------------------------------------------

test() ->
  ok.
