-module('fig3.1-ext').

-export([test/0]).

-concuerror_options([{ignore_error, deadlock}]).

-ifndef(P).
-define(P, 7).
-endif.

test() ->
  test(?P).

test(P) ->
  ets:new(table, [public, named_table]),
  ets:insert(table, {p, P}),
  [ets:insert(table, {{x, I}, 0}) || I <- lists:seq(1, P)],
  [ets:insert(table, {{y, I}, 0}) || I <- lists:seq(1, P)],
  [ets:insert(table, {{z, I}, 0}) || I <- lists:seq(1, P)],
  FunQ =
    fun(I) ->
        fun() -> ets:insert(table, {{y, I}, 1}) end
    end,
  FunR =
    fun(I) ->
        fun() ->
            [{{y, I}, M}] = ets:lookup(table, {y, I}),
            case M of
              1 -> ok;
              0 -> ets:insert(table, {{z, I}, 1})
            end
        end
    end,
  FunS =
    fun(I) ->
        fun() ->
            [{{z, I}, N}] = ets:lookup(table, {z, I}),
            [{{y, I}, O}] = ets:lookup(table, {y, I}),
            case N of
              0 -> ok;
              1 ->
                %% [{{y, I}, O}] = ets:lookup(table, {y, I}),
                case O of
                  1 -> ok;
                  0 -> ets:insert(table, {{x, I}, 1})
                end
            end
        end
    end,
  FunP =
    fun(I) ->
        fun() ->
            [{{x, I}, L}] = ets:lookup(table, {x, I}),
            case L =:= 1 andalso I < P of
              true ->
                spawn(FunQ(I + 1)),
                spawn(FunR(I + 1)),
                spawn(FunS(I + 1));
              false ->
                ok
            end
        end
    end,
  [spawn(FunP(I)) || I <- lists:seq(P, 1, -1)],
  spawn(FunQ(1)),
  spawn(FunR(1)),
  spawn(FunS(1)),
  block().

block() -> receive after infinity -> ok end.
