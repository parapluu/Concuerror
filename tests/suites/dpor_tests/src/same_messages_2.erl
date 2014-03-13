-module(same_messages_2).

-export([same_messages_2/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

same_messages_2() ->
    P = self(),
    Fun =
        fun(A) ->
                fun() ->
                        P ! unlock,
                        P ! A
                end
        end,
    spawn(Fun(a)),
    spawn(Fun(b)),
    receive
        unlock ->
            receive
                Msg when Msg =:= a;    
                         Msg =:= b -> throw(Msg)
            end
    end.
