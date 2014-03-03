-module(two_writers_readers_1).

-export([two_writers_readers_1/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

two_writers_readers_1() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    spawn(fun() ->
                  ets:insert(table, {x, 1}),
                  ets:insert(table, {x, 2})
          end),
    Fun =
        fun() ->
                ets:lookup(table, y),
                ets:lookup(table, x)
        end,
    spawn(Fun),
    spawn(Fun),
    receive
    after
        infinity -> ok
    end.
