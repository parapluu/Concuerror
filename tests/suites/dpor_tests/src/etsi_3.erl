-module(etsi_3).

-export([etsi_3/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

etsi_3() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() -> ets:insert(table, {y,1}) end),
    spawn(fun() ->
                  [{z,_}] = ets:lookup(table,z),
                  [{x,X}] = ets:lookup(table,x),
                  case X of
                      0 -> [{y,_}] = ets:lookup(table,y);
                      1 -> ok
                  end
          end),
    spawn(fun() -> ets:insert(table, {x,1}) end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
