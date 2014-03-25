-module(long_chain).

-export([long_chain/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

long_chain() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    ets:insert(table, {a, 0}),
    ets:insert(table, {b, 0}),
    ets:insert(table, {c, 0}),
    ets:insert(table, {w, 0}),
    spawn(fun() ->
                  ets:insert(table, {x, 1}),
                  ets:insert(table, {w, 1})
          end),
    spawn(fun() -> fun_ab(x, y, write) end),
    spawn(fun() -> fun_ab(y, a, write) end),
    spawn(fun() -> fun_ab(a, b, write) end),
    spawn(fun() -> fun_ab(b, c, write) end),
    spawn(fun() -> fun_ab(c, z, write) end),
    spawn(fun() -> fun_ab(a, w,  read) end),
    spawn(fun() -> fun_ab(z, w,  read) end),
    receive
    after
        infinity -> ok
    end.

fun_ab(A, B, What) ->
    ets:insert(table, {{self(), ?LINE}}), %% Cover instruction
    [{A, V}] = ets:lookup(table, A),
    ets:insert(table, {{self(), ?LINE}}), %% Cover instruction
    case V of
        1 ->
            case What of
                write -> ets:insert(table, {B, 1});
                read  -> ets:lookup(table,  B    )
            end;
        0 -> ok
    end.
