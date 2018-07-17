-module(process_info).

-compile(export_all).
-export([scenarios/0]).

scenarios() -> [{T, inf, dpor} || T <- [test1, test2, test3]].

test1() ->
    Fun = fun() -> register(foo, self()) end,
    P = spawn(Fun),
    exit(process_info(P, registered_name)).

test2() ->
    Fun = fun() -> register(foo, self()) end,
    P = spawn(Fun),
    exit(process_info(P, [registered_name, group_leader])).

test3() ->
  {P, _} = spawn_monitor(fun() -> ok end),
  receive
    _ -> ok
  end,
  undefined = process_info(P, [registered_name, group_leader]).
