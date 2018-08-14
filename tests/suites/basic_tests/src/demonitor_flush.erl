-module(demonitor_flush).

-compile(export_all).

-concuerror_options_forced([show_races]).

%%------------------------------------------------------------------------------

scenarios() ->
  [{T, inf, dpor} || T <- [test1, test2, test3, test4, test5, test6]].

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

%% This is a little strange: with default scheduling and
%% use_receive_patterns, Concuerror sees that the monitor is delivered
%% before the ok message, but since it is not received, it cannot be
%% received, so no additional schedulings are explored. Contrast with
%% next:

test4() ->
  P = self(),
  {Pid, Ref} = spawn_monitor(fun() -> ok end),
  spawn(fun() -> P ! ok, P ! go end),
  receive go -> ok end,
  demonitor(Ref, [flush]),
  receive
    ok -> ok;
    {'DOWN', Ref, process, Pid, _} -> error(impossible)
  after
    0 -> ok
  end.

%% Here the ok message is delivered first, so the monitor message
%% could be delivered earlier and be preferred; it is clear however
%% that since the receive is after the flush this will make no
%% difference.

test5() ->
  P = self(),
  spawn(fun() -> P ! ok, P ! go end),
  {Pid, Ref} = spawn_monitor(fun() -> ok end),
  receive go -> ok end,
  demonitor(Ref, [flush]),
  receive
    ok -> ok;
    {'DOWN', Ref, process, Pid, _} -> error(impossible)
  after
    0 -> ok
  end.

test6() ->
  P = self(),
  spawn(fun() -> P ! ok, P ! go end),
  {Pid, Ref} = spawn_monitor(fun() -> ok end),
  receive go -> ok end,
  receive
    {'DOWN', Ref, process, Pid, _} -> ok
  after
    0 -> ok
  end,
  demonitor(Ref, [flush]),
  receive
    ok -> ok;
    {'DOWN', Ref, process, Pid, _} -> error(impossible)
  after
    0 -> ok
  end.
