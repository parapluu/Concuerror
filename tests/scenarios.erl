%%%----------------------------------------------------------------------
%%% Copyright (c) 2012, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Tsitsimpis Ilias <iliastsi@hotmail.com>
%%% Description : Interface to extract scenarios from our tests
%%%----------------------------------------------------------------------

-module(scenarios).

-export([extract/1, exceptional/1]).

extract(Files) ->
  S1 = lists:map(fun extractOne/1, Files),
  S2 = lists:flatten(S1),
  lists:foreach(fun(S) -> io:format("~w\n", [S]) end, S2).

extractOne(File) ->
  Module = list_to_atom(filename:basename(File, ".erl")),
  %% Get the scenarios for one module
  Scenarios = Module:scenarios(),
  %% Put module name to it
  FunMap =
    fun(Scenario) ->
        list_to_tuple([Module | tuple_to_list(Scenario)])
    end,
  lists:map(FunMap, Scenarios).

-spec exceptional([filename:filename()]) -> no_return().

exceptional([Name, Expected, Actual]) ->
  Module = list_to_atom(Name),
  %% Get the scenarios for one module
  try
    Fun = Module:exceptional(),
    true = Fun(Expected, Actual),
    halt(0)
  catch
    _:_ ->
      halt(1)
  end.
