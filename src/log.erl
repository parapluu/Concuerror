%%%----------------------------------------------------------------------
%%% File    : log.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : Logging and Error Reporting Interface
%%%
%%% Created : 16 May 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%
%%% @doc: Logging and error reporting interface
%%% @end
%%%----------------------------------------------------------------------

-module(log).
%% Non gen_evt exports.
-export([internal/1, internal/2]).
%% Log API exports.
-export([start/2, stop/0, log/1, log/2, result/1]).
%% Log callback exports.
-export([init/1, terminate/2, handle_call/2, handle_info/2,
	 handle_event/2, code_change/3]).

-behavior(gen_event).

-include("gen.hrl").

-type(state() :: []).

%%%----------------------------------------------------------------------
%%% Non gen_evt functions.
%%%----------------------------------------------------------------------

%% @spec internal(string()) -> none()
%% @doc: Print an internal error message and halt.
-spec internal(string()) -> no_return().

internal(String) ->
    io:format("(Internal) " ++ String),
    halt(?RET_INTERNAL_ERROR).

%% @spec internal(string(), [term()]) -> none()
%% @doc: Like `internal/1', but prints a formatted message using arguments.
-spec internal(string(), [term()]) -> no_return().

internal(String, Args) ->
    io:format("(Internal) " ++ String, Args),
    halt(?RET_INTERNAL_ERROR).

%%%----------------------------------------------------------------------
%%% API functions
%%%----------------------------------------------------------------------

%% @spec start(atom()) -> {ok, pid()} | {error, {already_started, pid()}}
%% @doc: Starts the log event manager.
%%
%% `Mod' is the module containing the callback functions.
%% `Args' are the arguments given to the callback function `Mod:init/1'.
-spec start(module(), term()) -> {ok, pid()} |
                                 {error, {already_started, pid()}}.

start(Mod, Args) ->
    gen_event:start({local, log}),
    gen_event:add_handler(log, Mod, Args).

%% @spec stop() -> 'ok'
%% @doc: Terminates the log event manager.
-spec stop() -> 'ok'.

stop() ->
    gen_event:stop(log).

%% @spec spec log(string()) -> 'ok'
%% @doc: Logs a string.
-spec log(string()) -> 'ok'.

log(String) when is_list(String) ->
    log(String, []).

%% @spec spec log(string(), [term()]) -> 'ok'
%% @doc: Logs a formatted string.
-spec log(string(), [term()]) -> 'ok'.

log(String, Args) when is_list(String), is_list(Args) ->
    LogMsg = io_lib:format(String, Args),
    gen_event:notify(log, {msg, LogMsg}).

%% @spec spec result([term()]) -> 'ok'
%% @doc: Logs the analysis error list.
-spec result(term()) -> 'ok'.

result(Result) ->
    gen_event:notify(log, {result, Result}).

%%%----------------------------------------------------------------------
%%% Callback functions
%%%----------------------------------------------------------------------

-spec init(term()) -> {ok, state()}.

init(_State) ->
    {ok, []}.

-spec terminate(term(), state()) -> 'ok'.

terminate(_Reason, _State) ->
    ok.

-spec handle_event({msg, string()} | {result, term()}, state()) ->
			  {ok, state()}.

handle_event({msg, String}, State) ->
    io:format("~s", [String]),
    {ok, State};
handle_event({result, _Result}, State) ->
    %% Do nothing for now.
    {ok, State}.

-spec code_change(term(), term(), term()) -> no_return().

code_change(_OldVsn, _State, _Extra) ->
    log:internal("~p:~p: code_change~n", [?MODULE, ?LINE]).

-spec handle_info(term(), term()) -> no_return().

handle_info(_Info, _State) ->
    log:internal("~p:~p: handle_info~n", [?MODULE, ?LINE]).

-spec handle_call(term(), term()) -> term().

handle_call(_Request, _State) ->
    log:internal("~p:~p: handle_call~n", [?MODULE, ?LINE]).
