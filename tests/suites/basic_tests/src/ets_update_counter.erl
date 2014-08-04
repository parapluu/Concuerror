-module(ets_update_counter).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    ets:new(table, [named_table, public]),
    ets:insert(table, [{K,0} || K <- [a, b]]),
    spawn(read(a)),
    spawn(write(b)),
    spawn(count(a)),
    spawn(count(b)),
    receive after infinity -> ok end.

read(Key) ->
    fun() -> ets:lookup(table, Key) end.

write(Key) ->
    fun() -> ets:insert(table, {Key,5}) end.
            
count(Key) ->
    fun() -> ets:update_counter(table, Key, 1) end.
