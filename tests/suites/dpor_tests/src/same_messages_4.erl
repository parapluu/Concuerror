-module(same_messages_4).

-export([same_messages_4/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

same_messages_4() ->
    ets:new(table, [named_table, public]),
    P = self(),
    Fun =
        fun(A) ->
                fun() ->
                        case A of
                            true -> ets:insert(table,{foo});
                            false -> ok
                        end,
                        P ! unlock
                end
        end,
    spawn(Fun(true)),
    spawn(Fun(false)),
    receive
        unlock ->
            true = [] =/= ets:lookup(table, foo)
    end.
