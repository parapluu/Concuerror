-module(demonitor_flush).

-export([test1/0, test2/0, test3/0]).

-export([concuerror_options/0]).
-export([scenarios/0]).

%%------------------------------------------------------------------------------

concuerror_options() -> [show_races].

scenarios() -> [{T, inf, dpor} || T <- [test1, test2, test3]].

%%------------------------------------------------------------------------------

test1() ->
  {Pid, Ref} = spawn_monitor(fun() -> ok end),
  demonitor(Ref, [flush]),
  receive
    {'DOWN', Ref, process, Pid, _} -> error(impossible)
  after
    0 -> ok
  end.

test2() ->
  {Pid, Ref} = spawn_monitor(fun() -> ok end),
  demonitor(Ref, []),
  receive
    {'DOWN', Ref, process, Pid, _} -> possible
  after
    0 -> ok
  end,
  receive after infinity -> ok end.

test3() ->
  {Pid, Ref} = spawn_monitor(fun() -> ok end),
  demonitor(Ref),
  receive
    {'DOWN', Ref, process, Pid, _} -> possible
  after
    0 -> ok
  end,
  receive after infinity -> ok end.
