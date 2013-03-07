-module(readers_wrr).

-export([readers_wrr/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

readers_wrr() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    Writer =
        fun() ->
                ets:lookup(table, y),
                ets:insert(table, {x, 1})
        end,
    Reader =
        fun() ->
                ets:lookup(table, y),
                ets:lookup(table, x)
        end,
    spawn(Writer),
    spawn(Reader),
    spawn(Reader),
    receive
    after
        infinity -> ok
    end.
