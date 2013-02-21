-module(writeread).

-export([writeread/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

writeread() ->
    ets:new(table, [named_table, public]),
    spawn(fun() ->
                  ets:insert(table, {x, 1})%,
                  %ets:lookup(table, x)
          end),
    spawn(fun() ->
                  ets:insert(table, {x, 1}),
                  ets:lookup(table, x)
          end),
    ets:insert(table, {x,0}),
    ets:lookup(table, x),
    receive after infinity -> deadlock end.
