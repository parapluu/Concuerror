-module(ets_insert_new).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    ets:new(table, [named_table, public]),
    child(),
    child(),
    child(),
    receive after infinity -> ok end.

child() ->
    spawn(fun() ->
                  try
                      ets:update_counter(table, c, 1)
                  catch
                      _:_ ->
                          ets:insert_new(table, {c,1})
                  end
          end).
