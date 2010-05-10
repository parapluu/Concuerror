-module(ring).
-export([start/3]).

start(NProc, TTL, Msg) ->
    spawn_next(self(), NProc, TTL, Msg).

spawn_next(First, 0, TTL, Msg) ->
    self() ! {TTL + 1, Msg},
    loop(First);
spawn_next(First, Counter, TTL, Msg) ->
    Pid = spawn(fun() -> spawn_next(First, Counter - 1, TTL, Msg) end),
    loop(Pid).
			
loop(Next) ->
    receive
	{0, _} -> Next ! stop;
	{TTL, Msg} ->
	    Next ! {TTL - 1, Msg},
	    loop(Next);
	stop -> Next ! stop
    end.
