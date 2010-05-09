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
	{0, _Msg} -> Next ! stop;
	{TTL, Msg} ->
	    Next ! {TTL - 1, Msg},
	    loop(Next);
	stop -> Next ! stop
    end.

%% ------------------------------------------------------------------------
%% Instrumenting file "./test/ring.erl"
%% -file("./test/ring.erl", 1).

%% -module(ring).

%% -export([start/3]).

%% start(NProc, TTL, Msg) ->
%%     spawn_next(self(), NProc, TTL, Msg).

%% spawn_next(First, 0, TTL, Msg) ->
%%     sched:rep_send(self(), {TTL + 1, Msg}), loop(First);
%% spawn_next(First, Counter, TTL, Msg) ->
%%     Pid = sched:rep_spawn(fun () ->
%% 				  spawn_next(First, Counter - 1, TTL, Msg)
%% 			  end),
%%     loop(Pid).

%% loop(Next) ->
%%     sched:rep_receive(fun (Aux) ->
%% 			      receive
%% 				{0, _Msg} ->
%% 				    {begin {0, _Msg} end,
%% 				     begin sched:rep_send(Next, stop) end};
%% 				{TTL, Msg} ->
%% 				    {begin {TTL, Msg} end,
%% 				     begin
%% 				       sched:rep_send(Next, {TTL - 1, Msg}),
%% 				       loop(Next)
%% 				     end};
%% 				stop ->
%% 				    {begin stop end,
%% 				     begin sched:rep_send(Next, stop) end}
%% 				after 0 -> Aux()
%% 			      end
%% 		      end).
