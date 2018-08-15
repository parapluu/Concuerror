-module(demonitor_sane_opts).

-compile(export_all).

-concuerror_options_forced([show_races]).

%%------------------------------------------------------------------------------

scenarios() -> [{T, inf, dpor} || T <- [test1, test2, test3]].

%%------------------------------------------------------------------------------

test1() ->
  {Pid, Ref} = spawn_monitor(fun() -> ok end),
  demonitor(Ref, ban).

test2() ->
  {Pid, Ref} = spawn_monitor(fun() -> ok end),
  demonitor(Ref, [ban]).

test3() ->
  {P1, M1} = spawn_monitor(fun() -> receive ok -> ok end end),
  {P2, M2} = spawn_monitor(fun() -> true = demonitor(M1) end),
  receive {'DOWN', M2, process, P2, normal} -> ok end,
  P1 ! ok,
  receive {'DOWN', M1, process, P1, normal} -> ok end.
