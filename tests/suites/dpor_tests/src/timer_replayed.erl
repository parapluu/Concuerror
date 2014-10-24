-module(timer_replayed).

-export([test/0]).
-export([scenarios/0]).

scenarios() -> [{test, inf, dpor}].

test() ->
    ets:new(table, [named_table, public]),
    spawn(fun() -> ets:insert(table, {x,1}) end),
    spawn(fun() -> ets:lookup(table, x) end),
    P = self(),
    spawn(fun() -> erlang:send_after(100, P, ok) end),
    receive ok -> ok after 100 -> ok end,
    receive after infinity -> ok end.
