-module(gen_server_bug).
-behaviour(gen_server).

-export([test_register/0, test_without_register/0, scenarios/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

scenarios() ->
    [{test_register, inf, dpor}].

test_register() ->
    ServerName = {local, 'gen_server_bug'},
    {ok, Pid1} = gen_server:start(ServerName, ?MODULE, [], []),
    gen_server:call(Pid1, stop),
    {ok, Pid2} = gen_server:start(ServerName, ?MODULE, [], []),
    gen_server:call(Pid2, stop),
    ok.

test_without_register() ->
    {ok, Pid1} = gen_server:start_link(?MODULE, [], []),
    gen_server:call(Pid1, stop),
    {ok, Pid2} = gen_server:start_link(?MODULE, [], []),
    gen_server:call(Pid2, stop),
    ok.

%% ===================================================================
%% CallBack Functions

init([]) ->
    {ok, undefined}.

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call(_Event, _From, State) ->
    {reply, ok, State}.

handle_cast(_Event, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
