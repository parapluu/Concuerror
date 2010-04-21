-module(test_instr).
-export([test1/0, test2/0, test3/0]).

-spec test1() -> ok.
    
test1() ->
    Self = self(),
    %% spawn(fun() -> foo1(Self) end)
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo1(Self) end) end),
    %% receive _Any -> ok end
    sched:rep_receive(
      fun(Aux) ->
	      receive
		  _Any -> ok
	      after 0 -> Aux()
	      end
      end).

foo1(Pid) ->
    %% Pid ! 42
    sched:rep_send(Pid, 42).

-spec test2() -> ok.

test2() ->
    %% spawn(fun() -> foo21 end)
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo21() end) end),
    %% spawn(fun() -> foo22 end)
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo22() end) end),
    ok.

foo21() ->
    %% spawn(fun() -> foo 22 end)
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo22() end) end).

foo22() ->
    42.

-spec test3() -> ok.

test3() ->
    Self = self(),
    %% spawn(fun() -> foo31 end)
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo31(Self) end) end),
    %% spawn(fun() -> foo32 end)
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo32(Self) end) end),
    sched:rep_receive(
      fun(Aux) ->
	      receive
		  _Any1 -> ok
	      after 0 -> Aux()
	      end
      end),
    sched:rep_receive(
      fun(Aux) ->
	      receive
		  _Any2 -> ok
	      after 0 -> Aux()
	      end
      end).

foo31(Pid) ->
    %% Pid ! msg1
    sched:rep_send(Pid, msg1).

foo32(Pid) ->
    %% Pid ! msg2
    sched:rep_send(Pid, msg2).
