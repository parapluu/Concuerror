-module(messages_2).

-export([test/0]).
-export([scenarios/0]).

scenarios() -> [{test, inf, dpor}].

test() ->
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
                        receive R -> R = a end,
                        receive _ -> ok end
                end
        end,
    B = spawn(BFun),
    CFun = fun() -> B ! c end,
    C = spawn(CFun),
    B ! a,
    B ! special.
