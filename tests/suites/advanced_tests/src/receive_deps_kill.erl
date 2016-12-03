-module(receive_deps_kill).

-export([test/0]).
-export([scenarios/0]).

-concuerror_options_forced(
   [ {ignore_error, deadlock}
   , {instant_delivery, false}
   ]).

scenarios() -> [{test, inf, dpor}].

test() ->
    P = self(),
    ets:new(table, [public, named_table]),
    Fun =
        fun(X) ->
                fun() ->
                        P ! X,
                        case X =:= 1 orelse ets:lookup(table, k) =/= [] of
                            true -> ets:insert(table, {k,X});
                            false -> ok
                        end
                end
        end,
    spawn(Fun(1)),
    receive
        _ ->
            R = spawn(Fun(2)),
            receive
                _ ->
                    exit(R, boo),
                    ets:lookup(table,k)                    
            end
    end,
    receive after infinity -> ok end.
