-module(messages_1).

-export([messages_1/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

messages_1() ->
    A = self(),
    BFun =
        fun() ->
                S =
                    receive
                        special -> true
                    after
                        0 -> receive special -> false end
                    end,
                case S of
                    true ->
                        receive a -> ok end,
                        receive c -> ok end;
                    false ->
                        receive _ -> ok end,
                        receive _ -> ok end
                end
        end,
    B = spawn(BFun),
    CFun = fun() -> B ! c end,
    C = spawn(CFun),
    B ! a,
    B ! special.
