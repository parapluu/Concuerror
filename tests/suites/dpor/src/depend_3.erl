-module(depend_3).

-export([depend_3/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

depend_3() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() -> ets:insert(table, {z, 1}) end),
    spawn(fun() -> ets:insert(table, {x, 1}) end),
    spawn(fun() -> ets:insert(table, {y, 1}),
                   ets:insert(table, {y, 2})
          end),
    spawn(fun() ->
                  [{x, X}] = ets:lookup(table, x),
                  case X of
                      0 -> ok;
                      1 ->
                          [{y, Y}] = ets:lookup(table, y),
                          case Y of
                              0 -> ok;
                              _ -> ets:lookup(table, z)
                          end
                  end
          end),
    spawn(fun() ->
                  [{y, Y}] = ets:lookup(table, y),
                  case Y of
                      0 -> ok;
                      _ -> ets:lookup(table, z)
                  end
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
