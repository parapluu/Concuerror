-module(ets_dependencies_n).

-export([ets_dependencies_n/0, ets_dependencies_n/1]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ets_dependencies_n() ->
    ets_dependencies_n(3).

ets_dependencies_n(N) ->
    ets:new(table, [public, named_table]),
    Writer =
        fun() ->
            ets:insert(table, {x, 42})
        end,
    Reader =
        fun(I) ->
            ets:lookup(table, I),
            ets:lookup(table, x)
        end,
    spawn(Writer),
    [spawn(fun() -> Reader(I) end) || I <- lists:seq(1, N)],
    receive
    after
        infinity -> deadlock
    end.
