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

-export([extract/1]).

extract(Files) ->
    S1 = lists:map(fun extractOne/1, Files),
    S2 = lists:flatten(S1),
    lists:foreach(fun(S) -> io:format("~p\n", [S]) end, S2).

extractOne(File) ->
    Module = list_to_atom(filename:basename(File, ".erl")),
    %% Get the scenarios for one module
    Scenarios = apply(Module, scenarios, []),
    %% Put module name to it
    FunMap =
        fun(Scenario) ->
                case Scenario of
                    {Fun, Preb} ->
                        {Module, Fun, Preb, full};
                    {Fun, Preb, Flag} when Flag=:=full; Flag=:=dpor ->
                        {Module, Fun, Preb, Flag}
                end
        end,
    lists:map(FunMap, Scenarios).
