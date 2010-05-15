%% @doc: Utility functions.

-module(util).
-export([doc/1]).

%% @spec doc(string()) -> 'ok'
%% @doc: Build documentation using edoc.
-spec doc(string()) -> 'ok'.

doc(AppDir) ->
    AppName = yet_to_be_named,
    Options = [],
    edoc:application(AppName, AppDir, Options).
