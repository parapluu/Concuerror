-module(receive_deps).

-export([test/0]).
-export([scenarios/0]).

-concuerror_options_forced([{ignore_error, deadlock}]).

scenarios() -> [{test, inf, dpor}].

test() ->
    P = self(),
    ets:new(table, [public, named_table]),
    Fun =
        fun(X) ->
                fun() ->
                        P ! X,
                        case X =:= 1 orelse ets:lookup(table, k) =:= [{k,1}] of
                            true -> ets:insert(table, {k,X});
                            false -> ok
                        end
                end
        end,
    spawn(Fun(1)),
    spawn(Fun(2)),
    spawn(Fun(3)),
    receive
        A ->
            receive
                B when B =/= A ->
                    receive
                        C when C =/= A, C =/= B ->
                            ok
                    end
            end
    end,
    true = ets:lookup(table,k) =/= [{k,3}],
    receive after infinity -> ok end.
