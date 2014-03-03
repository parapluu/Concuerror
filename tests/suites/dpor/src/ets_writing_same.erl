-module(ets_writing_same).

-export([ets_writing_same/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ets_writing_same() ->
    ets:new(table, [named_table, public]),
    spawn(fun() ->
                  ets:insert(table, {x, 42})
          end),
    spawn(fun() ->
                  case ets:lookup(table, x) of
                      [{x,42}] ->
                          case ets:lookup(table, y) of
                              [] -> throw(yes);
                              _ -> ok
                          end;
                      _ -> ok
                  end
          end),
    ets:insert(table, {y, 1}),
    ets:insert(table, {x, 42}),
    receive after infinity -> dead end.
