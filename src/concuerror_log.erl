%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Logging and error reporting interface
%%%----------------------------------------------------------------------

-module(concuerror_log).
%% Non gen_evt exports.
-export([internal/1, internal/2]).
%% Log API exports.
-export([attach/2, detach/2, start/0, stop/0, log/1, log/2,
         progress/1, reset/0]).
%% Log callback exports.
-export([init/1, terminate/2, handle_call/2, handle_info/2,
         handle_event/2, code_change/3]).

-behaviour(gen_event).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Callback types
%%%----------------------------------------------------------------------

-type event() :: {'msg', string()}
               | {'progress', 'ok' | concuerror_ticket:ticket()}.
-type state() :: [].

-export_type([event/0, state/0]).

%%%----------------------------------------------------------------------
%%% Non gen_evt functions.
%%%----------------------------------------------------------------------

%% @spec internal(string()) -> no_return()
%% @doc: Print an internal error message and halt.
-spec internal(string()) -> no_return().

internal(String) ->
    io:format("(Internal) " ++ String),
    halt(?RET_INTERNAL_ERROR).

%% @spec internal(string(), [term()]) -> no_return()
%% @doc: Like `internal/1', but prints a formatted message using arguments.
-spec internal(string(), [term()]) -> no_return().

internal(String, Args) ->
    io:format("(Internal) " ++ String, Args),
    halt(?RET_INTERNAL_ERROR).

%%%----------------------------------------------------------------------
%%% API functions
%%%----------------------------------------------------------------------

%% Attach an event handler module.
-spec attach(module(), term()) -> 'ok' | {'EXIT', term()}.

attach(Mod, Args) ->
    gen_event:add_handler(concuerror_log, Mod, Args).

%% Detach an event handler module.
-spec detach(module(), term()) -> 'ok' | {'error', 'module_not_found'}.

detach(Mod, Args) ->
    gen_event:delete_handler(concuerror_log, Mod, Args).

%% @spec start(atom(), term()) -> {'ok', pid()} |
%%                                  {'error', {'already_started', pid()}}
%% @doc: Starts the log event manager.
%%
%% `Mod' is the module containing the callback functions.
%% `Args' are the arguments given to the callback function `Mod:init/1'.
-spec start() -> {'ok', pid()} | {'error', {'already_started', pid()}}.

start() ->
    gen_event:start({local, concuerror_log}).

%% @spec stop() -> 'ok'
%% @doc: Terminates the log event manager.
-spec stop() -> 'ok'.

stop() ->
    gen_event:stop(concuerror_log).

%% @spec log(string()) -> 'ok'
%% @doc: Logs a string.
-spec log(string()) -> 'ok'.

log(String) when is_list(String) ->
    log(String, []).

%% @spec log(string(), [term()]) -> 'ok'
%% @doc: Logs a formatted string.
-spec log(string(), [term()]) -> 'ok'.

log(String, Args) when is_list(String), is_list(Args) ->
    LogMsg = io_lib:format(String, Args),
    gen_event:notify(concuerror_log, {msg, LogMsg}).

%% @spec progress(concuerror_ticket:ticket() | 'ok') -> 'ok'
%% @doc: Shows analysis progress.
-spec progress(concuerror_ticket:ticket() | 'ok') -> 'ok'.

progress(ok) ->
    gen_event:notify(concuerror_log, {progress, ok});
progress(Ticket) ->
    gen_event:notify(concuerror_log, {progress, Ticket}).

%% @spec reset() -> 'ok'
%% @doc: Reset logger's internal state.
-spec reset() -> 'ok'.

reset() ->
    gen_event:notify(concuerror_log, 'reset').
%%%----------------------------------------------------------------------
%%% Callback functions
%%%----------------------------------------------------------------------

-spec init(term()) -> {'ok', state()}.

init(_State) ->
    {ok, []}.

-spec terminate(term(), state()) -> 'ok'.

terminate(_Reason, _State) ->
    ok.

-spec handle_event(event(), state()) -> {'ok', state()}.

handle_event({msg, String}, State) ->
    io:format("~s", [String]),
    {ok, State};
handle_event({progress, _Result}, State) ->
    {ok, State};
handle_event('reset', _State) ->
    {ok, []}.

-spec code_change(term(), term(), term()) -> no_return().

code_change(_OldVsn, _State, _Extra) ->
    internal("~p:~p: code_change~n", [?MODULE, ?LINE]).

-spec handle_info(term(), term()) -> no_return().

handle_info(_Info, _State) ->
    internal("~p:~p: handle_info~n", [?MODULE, ?LINE]).

-spec handle_call(term(), term()) -> no_return().

handle_call(_Request, _State) ->
    internal("~p:~p: handle_call~n", [?MODULE, ?LINE]).
