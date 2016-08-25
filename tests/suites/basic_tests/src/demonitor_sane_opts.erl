-module(demonitor_sane_opts).

-export([test1/0, test2/0]).

-export([concuerror_options/0]).
-export([scenarios/0]).

%%------------------------------------------------------------------------------

concuerror_options() -> [].

scenarios() -> [{T, inf, dpor} || T <- [test1, test2]].

%%------------------------------------------------------------------------------

test1() ->
  {Pid, Ref} = spawn_monitor(fun() -> ok end),
  demonitor(Ref, ban).

test2() ->
  {Pid, Ref} = spawn_monitor(fun() -> ok end),
  demonitor(Ref, [ban]).
