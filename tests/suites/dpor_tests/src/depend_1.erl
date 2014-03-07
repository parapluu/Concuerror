-module(depend_1).

-export([depend_1/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

depend_1() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() -> ets:insert(table, {z, 1}) end),
    spawn(fun() -> ets:insert(table, {x, 1}) end),
    spawn(fun() -> ets:insert(table, {y, 1}) end),
    spawn(fun() ->
                  [{x, X}] = ets:lookup(table, x),
                  case X of
                      1 ->
                          [{y, Y}] = ets:lookup(table, y),
                          case Y of
                              1 -> ets:lookup(table, z);
                              _ -> ok
                          end;
                      _ -> ok
                  end
          end),
    spawn(fun() ->
                  [{y, Y}] = ets:lookup(table, y),
                  case Y of
                      1 -> ets:lookup(table, z);
                      _ -> ok
                  end
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
