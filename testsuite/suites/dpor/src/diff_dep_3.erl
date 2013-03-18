-module(diff_dep_3).

-export([diff_dep_3/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

diff_dep_3() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() -> ets:insert(table, {x, 1}) end),
    spawn(fun() -> ets:insert(table, {z, 1}) end),
    spawn(fun() ->
                  [{z, Z}] = ets:lookup(table, z),
                  case Z of
                      0 -> ok;
                      1 -> ets:lookup(table, x)
                  end
          end),
    spawn(fun() ->
                  ets:lookup(table, x)
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
