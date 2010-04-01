%%%----------------------------------------------------------------------
%%% File    : refServer.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : 
%%%
%%% Created : 31 Mar 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

-module(refServer).
-export([start/1, stop/0, add/1, lookup/1]).

-include("../include/gui.hrl").

%% Start server linked to calling process

-spec start(boolean()) -> pid().

start(Link) ->
    case Link of
	true -> spawn_link(fun reg/0);
	false -> spawn(fun reg/0)
    end.

-spec stop() -> 'ok'.

stop() ->
    Pid = whereis(refServer),
    unregister(refServer),
    Pid ! {self(), #gui{type = ref_stop}},
    receive
	#gui{type = ref_ok} -> ok
    end.

-spec add({id(), ref()}) -> 'ok'.

add({_Id, _Ref} = T) ->
    refServer ! {self(), #gui{type = ref_add, msg = T}},
    receive
	#gui{type = ref_ok} -> ok
    end.
	
-spec lookup(id()) -> ref().

lookup(Id) ->
    refServer ! {self(), #gui{type = ref_lookup, msg = Id}},
    receive
	#gui{type = ref_ok, msg = {_, Ref}} -> Ref;
	#gui{type = ref_ok, msg = Other} -> Other
    end.

reg() ->
    register(refServer, self()),
    loop([]).

%% TODO: change list to dict
loop(Dict) ->
    receive
	{Pid, #gui{type = ref_add, msg = {_Id, _Ref} = T}} ->
	    Pid ! #gui{type = ref_ok},
	    loop([T|Dict]);
	{Pid, #gui{type = ref_lookup, msg = Id}} ->
	    Result = lists:keyfind(Id, 1, Dict),
	    Pid ! #gui{type = ref_ok, msg = Result},
	    loop(Dict);
	{Pid, #gui{type = ref_stop}} ->
	    Pid ! #gui{type = ref_ok};
	Other ->
	    io:format("refServer - unexpected message: ~p~n", [Other]),
	    loop(Dict)
    end.
