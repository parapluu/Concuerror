-module(log).
-export([internal/1, internal/2, log/1, log/2]).

-include("gen.hrl").

-spec internal(string()) -> no_return().

%% Print an internal error message.
internal(String) ->
    io:format("(Internal) " ++ String),
    halt(?RET_INTERNAL_ERROR).

-spec internal(string(), [term()]) -> no_return().

internal(String, Args) ->
    io:format("(Internal) " ++ String, Args),
    halt(?RET_INTERNAL_ERROR).

-spec log(string()) -> 'ok'.

%% Add a message to log (for now just print to stdout).
log(String) ->
    io:format(String).

-spec log(string(), [term()]) -> 'ok'.

log(String, Args) ->
    io:format(String, Args).
