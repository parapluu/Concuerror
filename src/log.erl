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
-export([internal/1, internal/2, log/1, log/2]).

-include("gen.hrl").

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

%% @spec log(string()) -> 'ok'
%% @doc: Add a message to log (for now just print to stdout).
-spec log(string()) -> 'ok'.

log(String) ->
    io:format(String).

%% @spec log(string(), [term()]) -> 'ok'
%% @doc: Like `log/1', but prints a formatted message using arguments.
-spec log(string(), [term()]) -> 'ok'.

log(String, Args) ->
    io:format(String, Args).
