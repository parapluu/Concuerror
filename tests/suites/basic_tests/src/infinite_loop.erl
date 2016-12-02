-module(infinite_loop).

-export([scenarios/0]).
-export([exceptional/0]).
-export([test/0]).

-concuerror_options_forced([{timeout, 1000}]).

scenarios() ->
    [{test, inf, dpor, crash}].

exceptional() ->
  fun(_Expected, Actual) ->
      Cmd =
        "grep \"You can try to increase the '--timeout' limit and/or ensure that"
        " there are no infinite loops in your test.\" ",
      [_,_,_|_] = os:cmd(Cmd ++ Actual),
      true
  end.

test() ->
  test().
