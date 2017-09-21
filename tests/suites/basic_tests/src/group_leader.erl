-module(group_leader).

-export([scenarios/0]).
-export([test/0, test1/0]).

scenarios() ->
    [{T, inf, dpor} || T <- [test,test1]].

test() ->
  C = spawn(fun() -> receive _ -> ok end end),
  group_leader(C, self()),
  C ! ok.

test1() ->
  {C, _} = spawn_monitor(fun() -> ok end),
  receive
    _MonitorDown -> ok
  end,
  group_leader(C, self()).
