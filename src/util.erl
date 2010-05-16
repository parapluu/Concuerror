%%%----------------------------------------------------------------------
%%% File    : util.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : Utilities
%%%
%%% Created : 16 May 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

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
