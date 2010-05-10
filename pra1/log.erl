-module(log).
-export([internal/1, internal/2, log/1, log/2]).

%% TODO: Originally defined in sched.erl.
-define(RET_INTERNAL_ERROR, 1).

-spec internal(string()) -> none().

%% Print an internal error message.
internal(String) ->
    io:format("(Internal) " ++ String),
    halt(?RET_INTERNAL_ERROR).

-spec internal(string(), [any()]) -> none().

internal(String, Args) ->
    io:format("(Internal) " ++ String, Args),
    halt(?RET_INTERNAL_ERROR).

-spec log(string()) -> 'ok'.

%% Add a message to log (for now just print to stdout).
log(String) ->
    io:format(String).

-spec log(string(), [any()]) -> 'ok'.

log(String, Args) ->
    io:format(String, Args).
