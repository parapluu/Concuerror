-module(test_instr).
-export([test1/0, test2/0, test3/0, test4/0, test5/0, test6/0]).

-spec test1() -> 'ok'.
    
test1() ->
    Self = self(),
    %% spawn(fun() -> foo1(Self) end)
    sched:rep_spawn(fun() -> foo1(Self) end),
    %% receive _Any -> ok end
    sched:rep_receive(
      fun(Aux) ->
	      receive
		  _Any -> {_Any, ok}
	      after 0 -> Aux()
	      end
      end).

foo1(Pid) ->
    %% Pid ! 42
    sched:rep_send(Pid, 42).

-spec test2() -> 'ok'.

test2() ->
    %% spawn(fun() -> foo21() end)
    sched:rep_spawn(fun() -> foo21() end),
    %% spawn(fun() -> foo22() end)
    sched:rep_spawn(fun() -> foo22() end),
    ok.

foo21() ->
    %% spawn(fun() -> foo22() end)
    sched:rep_spawn(fun() -> foo22() end).

foo22() ->
    42.

-spec test3() -> 'ok'.

test3() ->
    Self = self(),
    %% spawn(fun() -> foo31(Self) end)
    sched:rep_spawn(fun() -> foo31(Self) end),
    %% spawn(fun() -> foo32(Self) end)
    sched:rep_spawn(fun() -> foo32(Self) end),
    sched:rep_receive(
      fun(Aux) ->
	      receive
		  _Any1 -> {_Any1, ok}
	      after 0 -> Aux()
	      end
      end),
    sched:rep_receive(
      fun(Aux) ->
	      receive
		  _Any2 -> {_Any2, ok}
	      after 0 -> Aux()
	      end
      end).

foo31(Pid) ->
    %% Pid ! msg1
    sched:rep_send(Pid, msg1).

foo32(Pid) ->
    %% Pid ! msg2
    sched:rep_send(Pid, msg2).

-spec test4() -> no_return().

test4() ->
    %% spawn(fun() -> foo4() end)
    sched:rep_spawn(fun() -> foo4() end),
    %% receive _Any -> ok end
    sched:rep_receive(
      fun(Aux) ->
	      receive
		  _Any -> {_Any, ok}
	      after 0 -> Aux()
	      end
      end).

foo4() ->
    %% receive _Any -> ok end
    sched:rep_receive(
      fun(Aux) ->
	      receive
		  _Any -> {_Any, ok}
	      after 0 -> Aux()
	      end
      end).

-spec test5() -> no_return().

test5() ->
    Self = self(),
    %% spawn(fun() -> foo1(Self) end)
    sched:rep_spawn(fun() -> foo1(Self) end),
    %% receive _Any -> ok end
    sched:rep_receive(
      fun(Aux) ->
	      receive
		  43 -> {43, ok}
	      after 0 -> Aux()
	      end
      end).

-spec test6() -> ok.

test6() ->
    sched:rep_yield(),
    ets:new(table, [named_table, public]),
    sched:rep_yield(),
    ets:insert(table, {var, 10}),
    Pid = sched:rep_spawn(fun() -> a() end),
    sched:rep_spawn(fun() -> b() end),
    sched:rep_send(Pid, gazonk),
    sched:rep_yield(),
    [{var, N}] = ets:lookup(table, var),
    sched:rep_yield(),
    io:format("~p\n", [N]),
    ok.

a() ->
    sched:rep_yield(),
    [{var, N}] = ets:lookup(table, var),
    sched:rep_yield(),
    ets:insert(table, {var, N / 2}),
    sched:rep_receive(
      fun(Aux) ->
	      receive
		  gazonk -> {gazonk, ok}
	      after 0 -> Aux()
	      end
      end).

b() ->
    sched:rep_yield(),
    [{var, N}] = ets:lookup(table, var),
    sched:rep_yield(),
    ets:insert(table, {var, N + 2}).
