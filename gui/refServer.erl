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
	
-spec lookup(id()) -> ref() | not_found.

lookup(Id) ->
    refServer ! {self(), #gui{type = ref_lookup, msg = Id}},
    receive
	#gui{type = ref_ok, msg = Value} -> Value;
	#gui{type = ref_error, msg = not_found} -> not_found;
	#gui{type = ref_error, msg = Msg} ->
	    io:format("Internal refServer:lookup error - ~s~n", [Msg]),
	    exit(error)
    end.

reg() ->
    register(refServer, self()),
    loop(dict:new()).

loop(Dict) ->
    receive
	{Pid, #gui{type = ref_add, msg = {Id, Ref}}} ->
	    NewDict = dict:append(Id, Ref, Dict),
	    Pid ! #gui{type = ref_ok},
	    loop(NewDict);
	{Pid, #gui{type = ref_lookup, msg = Id}} ->
	    case dict:find(Id, Dict) of
		{ok, [Value]} -> Pid ! #gui{type = ref_ok, msg = Value};
		{ok, _Value} -> Pid ! #gui{type = ref_error, msg = "Found more than one"};
		error -> Pid ! #gui{type = ref_error, msg = not_found}
	    end,
	    loop(Dict);
	{Pid, #gui{type = ref_stop}} ->
	    Pid ! #gui{type = ref_ok};
	Other ->
	    io:format("refServer - unexpected message: ~p~n", [Other]),
	    loop(Dict)
    end.
