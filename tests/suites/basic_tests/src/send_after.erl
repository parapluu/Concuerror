-module(send_after).

-export([scenarios/0]).
-export([test1/0,test2/0,test3/0,test4/0,test5/0,test6/0,
         test7/0,test8/0,test9/0,testA/0,testB/0,testC/0,
         test11/0,test12/0,test13/0,test14/0,test15/0,test16/0,
         test17/0,test18/0,test19/0,test1A/0,test1B/0,test1C/0
        ,test1D/0
        ]).

scenarios() ->
    [{T, inf, dpor} ||
        T <-
            [test1,test2,test3,test4,test5,test6,
             test7,test8,test9,testA,testB,testC,
             test11,test12,test13,test14,test15,test16,
             test17,test18,test19,test1A,test1B,test1C
            ,test1D
            ]
    ].

test1() ->
    test(simple, send_after).
test2() ->
    test(simple, start_timer).
test3() ->
    test(cancel, send_after).
test4() ->
    test(cancel, start_timer).
test5() ->
    test(read_safe_1, send_after).
test6() ->
    test(read_safe_1, start_timer).
test7() ->
    test(read_safe_2, send_after).
test8() ->
    test(read_safe_2, start_timer).
test9() ->
    test(cancel_safe_1, send_after).
testA() ->
    test(cancel_safe_1, start_timer).
testB() ->
    test(cancel_safe_2, send_after).
testC() ->
    test(cancel_safe_2, start_timer).
test11() ->
    test(simple, send_after, 0).
test12() ->
    test(simple, start_timer, 0).
test13() ->
    test(cancel, send_after, 0).
test14() ->
    test(cancel, start_timer, 0).
test15() ->
    test(read_safe_1, send_after, 0).
test16() ->
    test(read_safe_1, start_timer, 0).
test17() ->
    test(read_safe_2, send_after, 0).
test18() ->
    test(read_safe_2, start_timer, 0).
test19() ->
    test(cancel_safe_1, send_after, 0).
test1A() ->
    test(cancel_safe_1, start_timer, 0).
test1B() ->
    test(cancel_safe_2, send_after, 0).
test1C() ->
    test(cancel_safe_2, start_timer, 0).

test1D() ->
  erlang:send_after(0, self(), ok),
  receive ok -> ok end,
  P = self(),
  spawn(fun() -> P ! foo end),
  spawn(fun() -> P ! bar end),
  receive _ -> ok end.

test(Tag, Type) ->
    test(Tag, Type, 1000).

test(Tag, Type, Timeout) ->
    Msg = foo,
    {Fun, PatternFun} =
        case Type of
            send_after ->
                {fun() -> erlang:send_after(Timeout, self(), Msg) end,
                 fun(_Ref) -> Msg end};
            start_timer ->
                {fun() -> erlang:start_timer(Timeout, self(), Msg) end,
                 fun(Ref) -> {timeout, Ref, Msg} end}
        end,
    true = testa(Tag, Fun, PatternFun).

testa(simple, Fun, PatternFun) ->
    Ref = Fun(),
    Pattern = PatternFun(Ref),
    receive
        Pattern -> true
    after
        1000 -> true
    end,
    receive after infinity -> ok end;
testa(cancel, Fun, PatternFun) ->
    Ref = Fun(),
    Pattern = PatternFun(Ref),
    erlang:cancel_timer(Ref),
    receive
        Pattern -> true
    after
        1000 -> true
    end,
    receive after infinity -> ok end;
testa(read_safe_1, Fun, PatternFun) ->
    Ref = Fun(),
    Pattern = PatternFun(Ref),
    receive
        Pattern ->
            erlang:read_timer(Ref) =:= false
    after
        1000 -> true
    end;
testa(read_safe_2, Fun, PatternFun) ->
    Ref = Fun(),
    Pattern = PatternFun(Ref),
    Leftover = erlang:read_timer(Ref),
    receive
        Pattern -> true
    after
        1000 ->
            Leftover =/= false
    end;
testa(cancel_safe_1, Fun, PatternFun) ->
    Ref = Fun(),
    Pattern = PatternFun(Ref),
    receive
        Pattern ->
            erlang:cancel_timer(Ref) =:= false
    after
        1000 -> true
    end;
testa(cancel_safe_2, Fun, PatternFun) ->
    Ref = Fun(),
    Pattern = PatternFun(Ref),
    Leftover = erlang:cancel_timer(Ref),
    receive
        Pattern -> true
    after
        1000 ->
            Leftover =/= false
    end.
