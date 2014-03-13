-module(same_messages_3).

-export([same_messages_3/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

same_messages_3() ->
    P = self(),
    Fun =
        fun(A) ->
                fun() ->
                        P ! A,
                        P ! unlock
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
