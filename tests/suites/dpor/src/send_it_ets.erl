-module(send_it_ets).

-export([send_it_ets/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

send_it_ets() ->
    Parent = self(),
    ets:new(table, [named_table, public]),
    spawn(fun() ->
                  ets:insert(table, {x,1}),
                  Parent ! ok
          end),
    spawn(fun() ->
                  Parent ! ok
          end),
    receive
        ok ->
            case ets:lookup(table, x) of
                [] -> throw(boom);
                _ -> safe
            end
    end.
