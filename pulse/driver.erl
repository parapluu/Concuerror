%%%----------------------------------------------------------------------
%%% File : dot.erl
%%% Modified by : Alkis Gotovos <el3ctrologos@hotmail.com> and
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : 
%%%
%%% Created : 1 Apr 2010 by Maria Christakis <christakismaria@gmail.com>
%%%----------------------------------------------------------------------

-module(driver).
-export([drive/1, drive/2, drive0/1, drive2/1]).

-include("../include/gui.hrl").

-type drive() :: {'events', _} | {'live', _} | {'schedule', [any()]}.
%% XXX: Make more specific
-type drive_lst() :: [drive(),...].

-spec drive(fun(), pid()) -> drive_lst().

drive(Fun, Caller) ->
    Result = scheduler:start([{seed, now()}], Fun),
    io:format("~p~n", [noEvents(Result)]),
    case lists:keyfind(events, 1, Result) of
	{events, Events} ->
	    io:format("(generating file schedule.dot ...)~n"),
	    dot:dot("schedule.dot", Events),
	    Caller ! #gui{type = dot, msg = ok};
	_ -> ok
    end,
    Result.

-spec drive(fun()) -> drive_lst().

drive(Fun) ->
    Result = scheduler:start([{seed, now()}], Fun),
    io:format("~p~n", [noEvents(Result)]),
    case lists:keyfind(events, 1, Result) of
	{events, Events} ->
	    io:format("(generating file schedule.dot ...)~n"),
	    dot:dot("schedule.dot", Events);
	_ -> ok
    end,
    Result.

-spec drive0(fun()) -> 'ok'.

drive0(Fun) ->
    drive(Fun),
    ok.

-spec drive2(fun()) -> [drive() | {drive(), 'NEQ', drive()},...].

drive2(Fun) ->
    io:format("=== RUN 1 ===~n"),
    Result1 = drive(Fun),
    Sched1  = case lists:keyfind(schedule, 1, Result1) of
		  {schedule, Sched} -> Sched;
		  _                 -> exit("no schedule")
	      end,
    io:format("=== RUN 2 ===~n"),
    Result2 = scheduler:start([{schedule, Sched1}], fun() -> Fun() end),
    io:format("=== RESULT ===~n"),
    diff(noEvents(Result1), noEvents(Result2)).

noEvents(Result) ->
    [Res || Res <- Result, case Res of {events,_} -> false; _ -> true end].

diff(X, X) -> X;
diff(X, Y) when tuple_size(X) =:= tuple_size(Y) ->
    list_to_tuple(diff(tuple_to_list(X), tuple_to_list(Y)));
diff([X|Xs],[Y|Ys]) ->
    [diff(X, Y)|diff(Xs, Ys)];
diff(X, Y) ->
    {X, 'NEQ', Y}.
