-module(ets_heir).

-export([ets_heir/0]).

ets_heir() ->
    Heir = spawn(fun() -> ok end),                         
    Tid = ets:new(table, [{heir, Heir, heir}]),
    spawn(fun() ->
                  ets:lookup(Tid, x),
                  throw(too_bad)
          end).
