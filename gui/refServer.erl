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

%% Message format
-type ref_type() :: 'ref_add' | 'ref_error' | 'ref_lookup' | 'ref_ok'
                  | 'ref_stop'.
-type ref_msg()  :: 'not_found' | id() | ref() | {id(), ref()}.

-record(ref, {type :: ref_type(),
	      msg  :: ref_msg()}).

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
    Pid ! {self(), #ref{type = ref_stop}},
    receive
	#ref{type = ref_ok} -> ok
    end.

-spec add({id(), ref()}) -> 'ok'.

add({_Id, _Ref} = T) ->
    refServer ! {self(), #ref{type = ref_add, msg = T}},
    receive
	#ref{type = ref_ok} -> ok
    end.
	
-spec lookup(id()) -> ref() | not_found.

lookup(Id) ->
    refServer ! {self(), #ref{type = ref_lookup, msg = Id}},
    receive
	#ref{type = ref_ok, msg = not_found} -> not_found;
	#ref{type = ref_ok, msg = Value} -> Value
    end.

reg() ->
    register(refServer, self()),
    loop(dict:new()).

loop(Dict) ->
    receive
	{Pid, #ref{type = ref_add, msg = {Id, Ref}}} ->
	    NewDict = dict:store(Id, Ref, Dict),
	    Pid ! #ref{type = ref_ok},
	    loop(NewDict);
	{Pid, #ref{type = ref_lookup, msg = Id}} ->
	    case dict:find(Id, Dict) of
		{ok, Value} -> Pid ! #ref{type = ref_ok, msg = Value};
		error -> Pid ! #ref{type = ref_ok, msg = not_found}
	    end,
	    loop(Dict);
	{Pid, #ref{type = ref_stop}} ->
	    Pid ! #ref{type = ref_ok};
	Other ->
	    io:format("refServer - unexpected message: ~p~n", [Other]),
	    loop(Dict)
    end.
