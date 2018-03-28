-module(infinite_loop).

-export([scenarios/0]).
-export([exceptional/0]).
-export([test1/0, test2/0]).

-concuerror_options_forced([{timeout, 500}]).

scenarios() ->
    [{T, inf, dpor, crash} || T <- [test1, test2]].

exceptional() ->
  fun(_Expected, Actual) ->
      Cmd =
        "grep \"You can try to increase the '--timeout' limit and/or ensure that"
        " there are no infinite loops in your test.\" ",
      [_,_,_|_] = os:cmd(Cmd ++ Actual),
      true
  end.

test1() ->
    loop().

test2() ->
    process_flag(trap_exit, true),
    loop().

loop() ->
    loop().
