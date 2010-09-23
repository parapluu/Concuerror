%%%----------------------------------------------------------------------
%%% File    : test.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : Tests
%%%
%%% Created : 16 May 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

-module(test).
-export([test1/0, test2/0, test3/0, test4/0,
	 test5/0, test6/0, test7/0, test8/0,
	 test9/0, test10/0, test11/0]).

-include("ced.hrl").

%% Normal, 2 proc: Simple send-receive.
-spec test1() -> 'ok'.

test1() ->
    ?assert(foo1() =:= ok).

foo1() ->
    Self = self(),
    spawn(fun() -> foo1_1(Self) end),
    receive _Any -> ok end.

foo1_1(Pid) ->
    Pid ! 42.

%% Normal, 3 proc: Only spawns.
-spec test2() -> 'ok'.

test2() ->
    ?assert(foo2() =:= ok).

foo2() ->
    spawn(fun() -> foo2_1() end),
    spawn(fun() -> foo2_2() end),
    ok.

foo2_1() ->
    spawn(fun() -> foo2_2() end).

foo2_2() ->
    42.

%% Normal, 3 proc: Simple send-receive.
-spec test3() -> 'ok'.

test3() ->
    ?assert(foo3() =:= ok).

foo3() ->
    Self = self(),
    spawn(fun() -> foo3_1(Self) end),
    spawn(fun() -> foo3_2(Self) end),
    receive
	_Any1 -> ok
    end,
    receive
	_Any2 -> ok
    end.

foo3_1(Pid) ->
    Pid ! msg1.

foo3_2(Pid) ->
    Pid ! msg2.

%% Deadlock, 2 proc: Both receiving.
-spec test4() -> no_return().

test4() ->
    ?assert(foo4() =:= ok).

foo4() ->
    spawn(fun() -> foo4_1() end),
    receive _Any -> ok end.

foo4_1() ->
    receive _Any -> ok end.

%% Deadlock, 2 proc: Sending 42, expecting to receive 43.
-spec test5() -> no_return().

test5() ->
    ?assert(foo5() =:= ok).

foo5() ->
    Self = self(),
    spawn(fun() -> foo1_1(Self) end),
    receive 43 -> ok end.

%% Normal, 2 proc: Nested send.
-spec test6() -> 'ok'.

test6() ->
    ?assert(foo6() =:= ok).

foo6() ->
    Self = self(),
    spawn(fun() -> foo6_1(Self) end),
    receive
	Any -> receive
		   Any -> ok
	       end
    end.

foo6_1(Pid) ->
    Pid ! Pid ! 42.

%% Normal, 2 proc: Nested send-receive.
-spec test7() -> 'ok'.

test7() ->
    ?assert(foo7() =:= ok).

foo7() ->
    Self = self(),
    Pid = spawn(fun() -> foo7_1(Self) end),
    Msg = hello,
    Pid ! Msg,
    receive
	Msg -> ok
    end.

foo7_1(Pid) ->
    Pid ! receive
	      Any -> Any
	  end.

%% Race, 2 proc: Classic spawn-link race.
-spec test8() -> 'ok'.

test8() ->
    ?assert(foo8() =:= ok).

foo8() ->
    Self = self(),
    Pid = spawn(fun() -> foo1_1(Self) end),
    link(Pid),
    receive
	_Any -> ok
    end.

%% Normal, 2 proc: Like test1/0, but using function from other file.
-spec test9() -> 'ok'.

test9() ->
    ?assert(foo9() =:= ok).

foo9() ->
    Self = self(),
    spawn(fun() -> test_aux:bar(Self) end),
    receive _Any -> ok end.

%% Assertion violation, 3 proc: 
-spec test10() -> 'ok'.

test10() ->
    Self = self(),
    spawn(fun() -> foo3_1(Self) end),
    spawn(fun() -> foo3_2(Self) end),
    receive
	Msg -> ?assert(Msg =:= msg1)
    end.

%% Normal, 2 proc: Simple receive-after with no patterns.
-spec test11() -> 'ok'.

test11() ->
    ?assert(foo11() =:= ok).

foo11() ->
    Self = self(),
    spawn(fun() -> foo1_1(Self) end),
    receive after 42 -> ok end,
    receive _Any -> ok end.
