-module(self_exits).

-concuerror_options_forced([{instant_delivery, false}]).

-export([test1/0, test2/0, test3/0, test4/0]).
-export([scenarios/0]).

scenarios() ->
  [{T, inf, dpor} || T <- [test1, test2, test3, test4]].

test1() ->
  {P, M} =
    spawn_monitor(
      fun() ->
          catch exit(self(), normal),
          exit(abnormal)
      end),
  receive
    {'DOWN', M, process, P, R} -> R = normal
  end.

test2() ->
  process_flag(trap_exit, true),
  catch exit(self(), normal),
  P = self(),
  receive
    {'EXIT', P, normal} -> ok
  end.

test3() ->
  {P, M} =
    spawn_monitor(
      fun() ->
          catch exit(self(), abnormal),
          exit(normal)
      end),
  receive
    {'DOWN', M, process, P, R} -> R = abnormal
  end.

test4() ->
  process_flag(trap_exit, true),
  catch exit(self(), abnormal),
  P = self(),
  receive
    {'EXIT', P, abnormal} -> ok
  end.
