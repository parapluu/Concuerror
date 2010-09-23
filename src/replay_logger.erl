%%%----------------------------------------------------------------------
%%% File    : replay_logger.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : Replay Logger
%%%
%%% Created : 1 Jun 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%
%%% @doc: Replay logger
%%% @end
%%%----------------------------------------------------------------------

-module(replay_logger).

%% API exports
-export([start/0, stop/0, start_replay/0, log/1, get_replay/0]).
%% Callback exports
-export([init/1, terminate/2, handle_cast/2, handle_call/3,
	 code_change/3, handle_info/2]).

-behaviour(gen_server).

-include("gen.hrl").

-type state() :: [sched:proc_action()].

%%%----------------------------------------------------------------------
%%% Eunit related
%%%----------------------------------------------------------------------

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

%%%----------------------------------------------------------------------
%%% API functions
%%%----------------------------------------------------------------------

-spec start() -> {'ok', pid()} | 'ignore' |
                 {'error', {'already_started', pid()} | term()}.

start() ->
    gen_server:start({local, ?RP_REPLAY_LOGGER}, ?MODULE, [], []).

-spec stop() -> 'ok'.

stop() ->
    gen_server:cast(?RP_REPLAY_LOGGER, stop).

-spec start_replay() -> 'ok'.

start_replay() ->
    gen_server:cast(?RP_REPLAY_LOGGER, start_replay).

-spec log(sched:proc_action()) -> 'ok'.

log(Msg) ->
    gen_server:cast(?RP_REPLAY_LOGGER, {log_replay, Msg}).

-spec get_replay() -> state().

get_replay() ->
    gen_server:call(?RP_REPLAY_LOGGER, get_replay).

%%%----------------------------------------------------------------------
%%% Callback functions
%%%----------------------------------------------------------------------

-spec init(term()) -> {'ok', state()}.

init(_Args) ->
    {ok, []}.

-spec terminate(term(), state()) -> 'ok'.

terminate(_Reason, _State) ->
    ok.

-spec handle_cast('start_replay' | 'stop' | {'log_replay', sched:proc_action()},
                  state()) ->
			 {'noreply', state()}.

handle_cast(start_replay, _State) ->
    {noreply, []};
handle_cast({log_replay, Msg}, State) ->
    {noreply, [Msg|State]};
handle_cast(stop, State) ->
    {stop, normal, State}.

-spec handle_call('get_replay', {pid(), term()}, state()) ->
			 {'reply', state(), state()}.

handle_call(get_replay, _From, State) ->
    Details = lists:reverse(State),
    {reply, Details, State}.

-spec code_change(term(), term(), term()) -> no_return().

code_change(_OldVsn, _State, _Extra) ->
    log:internal("~p:~p: code_change~n", [?MODULE, ?LINE]).

-spec handle_info(term(), term()) -> no_return().

handle_info(_Info, _State) ->
    log:internal("~p:~p: handle_info~n", [?MODULE, ?LINE]).

%%%----------------------------------------------------------------------
%%% Unit tests
%%%----------------------------------------------------------------------

-spec replay_test_() -> term().

replay_test_() ->
    [{"test1",
      ?_test(begin
		 start(),
		 start_replay(),
		 Msg1 = {spawn, "P1", "P1.1"},
		 Msg2 = {send, "P1", "P1.1", ahoi},
		 log(Msg1),
		 log(Msg2),
		 ?assertEqual(get_replay(), [Msg1, Msg2]),
		 stop()
	     end)}
    ].
