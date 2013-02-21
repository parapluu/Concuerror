-module(priorities).

-export([priorities/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

priorities() ->
    ets:new(table, [named_table, public]),
    Parent = self(),
    P1 =
        spawn(fun() ->
                      receive ok ->
                              Parent ! ok
                      end,
                      ets:lookup(table, y),
                      ets:lookup(table, x)
              end),
    spawn(fun() ->
                  P1 ! ok,
                  ets:insert(table, {x, 42})
          end),
    receive
        ok ->
            ets:lookup(table, y),
            ets:lookup(table, x)
    end,
    receive after infinity -> deadlock end.
