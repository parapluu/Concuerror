-module(refServer).
-export([start/1, stop/0, add/1, lookup/1]).

-include("gui.hrl").

%% Start server linked to calling process
start(Link) ->
    case Link of
	true ->
	    spawn_link(fun reg/0);
	false ->
	    spawn(fun reg/0)
    end.

stop() ->
    Pid = whereis(refServer),
    unregister(refServer),
    Pid ! {self(), #gui{type = ref_stop}},
    receive
	#gui{type = ref_ok} -> ok
    end.

add({Id, Ref}) ->
    refServer ! {self(), #gui{type = ref_add, msg = {Id, Ref}}},
    receive
	#gui{type = ref_ok} -> ok
    end.
	
lookup(Id) ->
    refServer ! {self(), #gui{type = ref_lookup, msg = Id}},
    receive
	#gui{type = ref_ok, msg = {_, Ref}} -> Ref;
	#gui{type = ref_ok, msg = Other} -> Other
    end.

reg() ->
    register(refServer, self()),
    loop([]).

loop(Dict) ->
    receive
	{Pid, #gui{type = ref_add, msg = {Id, Ref}}} ->
	    Pid ! #gui{type = ref_ok},
	    loop([{Id, Ref} | Dict]);
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
