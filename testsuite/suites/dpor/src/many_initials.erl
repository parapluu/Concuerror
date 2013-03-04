-module(many_initials).

-export([many_initials/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

many_initials() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() -> ets:insert(table, {x, 1}) end),
    spawn(fun() -> ets:insert(table, {y, 1}) end),
    spawn(fun() -> ets:insert(table, {z, 1}) end),
    spawn(fun() ->
                  [{y, Y}] = ets:lookup(table, y),
                  [{z, Z}] = ets:lookup(table, z),
                  case {Y, Z} of
                      {1,1} -> [{x, _}] = ets:lookup(table, x);
                      _     -> ok
                  end
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
