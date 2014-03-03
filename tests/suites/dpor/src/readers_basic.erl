-module(readers_basic).

-export([readers_basic/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

readers_basic() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    Writer =
        fun() ->
                ets:insert(table, {x, 1})
        end,
    Reader =
        fun() ->
                ets:lookup(table, x)
        end,
    spawn(Writer),
    spawn(Reader),
    spawn(Reader),
    receive
    after
        infinity -> ok
    end.
