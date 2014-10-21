-module(diff_dep_1).

-export([diff_dep_1/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

diff_dep_1() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() -> ets:insert(table, {x, 1}) end),
    spawn(fun() -> ets:insert(table, {y, 1}) end),
    spawn(fun() -> ets:insert(table, {z, 1}) end),
    spawn(fun() ->
                  [{z, Z}] = ets:lookup(table, z),
                  erlang:display({z,Z}),
                  case Z of
                      0 -> ok;
                      1 ->
                          [{x, X}] = ets:lookup(table, x),
                          erlang:display({x1,X})
                  end
          end),
    spawn(fun() ->
                  [{y, Y}] = ets:lookup(table, y),
                  erlang:display({y,Y}),
                  case Y of
                      0 -> ok;
                      1 ->
                          [{x, X}] = ets:lookup(table, x),
                          erlang:display({x2,X})
                  end
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
