-module(ets_cross).

-export([test/0,scenarios/0]).

scenarios() -> [{test, inf, dpor}].

test() ->
    ets:new(table, [public, named_table]),
    spawn(fun() ->
                  ets:insert(table, {x, 1}),
                  ets:insert(table, {y, 1})
          end),
    spawn(fun() ->
                  ets:insert(table, {y, 2}),
                  ets:insert(table, {x, 2})
          end),
    receive
    after
        infinity -> ok
    end.
