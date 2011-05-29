%%%----------------------------------------------------------------------
%%% Author      : Alkis Gotovos <alkisg@softlab.ntua.gr>
%%% Description : Generic registration server
%%%----------------------------------------------------------------------

-module(reg_server).

-export([attach/0, detach/0, ping/0, start/0, stop/0]).

-define(REG_NAME, reg_server).
-define(REG_REQUEST, reg_request).
-define(REG_REPLY, reg_reply).

-include("reg_server.hrl").

-record(state, {free, reg}).


%%%----------------------------------------------------------------------
%%% Exports
%%%----------------------------------------------------------------------

attach() ->
    request(attach).

detach() ->
    request(detach).

ping() ->
    request(ping).

start() ->
    case whereis(?REG_NAME) of
	undefined ->	    
	    Pid = spawn(fun() -> loop(initState()) end),
	    try register(?REG_NAME, Pid) of
		true -> ok
	    catch
		error:badarg ->
		    Pid ! {?REG_REQUEST, kill},
		    already_started
	    end;
	_Pid -> already_started
    end.

stop() ->
    request(stop).

%%%----------------------------------------------------------------------
%%% Internals
%%%----------------------------------------------------------------------

initState() ->
    FreeList = lists:seq(1, ?MAX_ATTACHED),
    #state{free = ordsets:from_list(FreeList),
	   reg = dict:new()}.

loop(#state{free = Free, reg = Reg} = State) ->
    receive
	{?REG_REQUEST, Target, attach} ->
	    case dict:find(Target, Reg) of
		{ok, RegNum} ->
		    reply(Target, RegNum),
		    loop(State);
		error ->
		    case ordsets:to_list(Free) of
			[] ->
			    reply(Target, server_full),
			    loop(State);
			[RegNum|NewFreeList] ->
			    NewReg = dict:store(Target, RegNum, Reg),
			    monitor(process, Target),
			    reply(Target, RegNum),
			    NewFree = ordsets:from_list(NewFreeList),
			    NewState = State#state{free = NewFree,
						   reg = NewReg},
			    loop(NewState)
		    end
	    end;
	{?REG_REQUEST, Target, detach} ->
	    {Reply, NewFree, NewReg} =
		detach_proc(Target, Free, Reg),
	    reply(Target, Reply),
	    NewState = State#state{free = NewFree,
				   reg = NewReg},
	    loop(NewState);
	{?REG_REQUEST, Target, ping} ->
	    case dict:find(Target, Reg) of
		{ok, RegNum} -> reply(Target, RegNum);
		error -> reply(Target, pong)
	    end,
	    loop(State);
	{'DOWN', _Ref, process, Target, _Info} ->
	    NewState =
		case dict:is_key(Target, Reg) of
		    true ->
			{ok, NewFree, NewReg} =
			    detach_proc(Target, Free, Reg),
			State#state{free = NewFree,
				    reg = NewReg};
		    false -> State
		end,
	    loop(NewState);
	{?REG_REQUEST, Target, stop} ->
	    unregister(?REG_NAME),
	    reply(Target, ok);
	{?REG_REQUEST, kill} -> killed
    end.

detach_proc(Target, Free, Reg) ->
    case dict:is_key(Target, Reg) of
	false -> {ok, Free, Reg};
	true ->
	    RegNum = dict:fetch(Target, Reg),
	    NewReg = dict:erase(Target, Reg),
	    NewFree = ordsets:add_element(RegNum, Free),
	    {ok, NewFree, NewReg}
    end.

request(Request) ->
    case whereis(?REG_NAME) of
	undefined -> server_down;
	Pid ->
	    Ref = monitor(process, Pid),
	    Pid ! {?REG_REQUEST, self(), Request},
	    receive
		{?REG_REPLY, Reply} ->
		    demonitor(Ref, [flush]),
		    Reply;
		{'DOWN', Ref, process, Pid, _Reason} ->
		    server_down
	    end
    end.

reply(Target, Reply) ->
    Target ! {?REG_REPLY, Reply}.
