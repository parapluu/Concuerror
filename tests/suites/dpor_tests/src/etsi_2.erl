-module(etsi_2).

-export([etsi_2/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

etsi_2() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    spawn(fun() ->
                  ets:insert(table, {x,1}),
                  block()
          end),
    spawn(fun() ->
                  ets:insert(table, {y,1}),
                  [{x, _}] = ets:lookup(table, x),
                  block()
          end),
    spawn(fun() ->
                  [{x, X}] = ets:lookup(table, x),
                  case X of
                      0 -> ok;
                      1 -> [{y, _}] = ets:lookup(table, y)
                  end,
                  block()
          end),
    block().

block() ->
    receive
    after
        infinity -> ok
    end.
