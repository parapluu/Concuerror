-module(deeper_exit).

-export([scenarios/0]).
-export([test/0]).

-concuerror_options_forced([{instant_delivery, false}]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    B = spawn(fun serve/0),
    A = spawn(fun() -> request(B) end),                       
    exit(B,kill),
    exit(A,kill).

serve() ->
    receive
        P -> P ! ok
    end.

request(P) ->
    P ! self(),
    receive
        ok -> ok
    end.
            
            
    
%% The cause itself is as follows:

%% Actor A is running something equivalent to
%% Mon = monitor(B),
%% B ! {request, A, ...},
%% receive
%%   {ok, resp} -> resp;
%%   error -> ...
%% end.

%% Actor B is running 
%% receive
%%    {request, ...} -> A!{ok, resp}
%% end.

%% Actor C is running
%% exit(B, ...),
%% exit(A, ...).

%% In the original run Concuerror's schedule is such that first
%% B runs A!{ok, resp}
%% then gets killed
%% A receives the response from B
%% and then gets killed.

%% During replay
%% B gets killed before sending the response
%% As a result A is marked as waiting, and the replay result for the exit_event on A differs (A is waiting instead of running).

%% I don't actually know how to fix this within Concuerror, but I worked around it by removing the explicit teardown.
