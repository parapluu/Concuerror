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
%%% Description : Error ticket interface
%%%----------------------------------------------------------------------

-module(ticket).

-export([new/2, get_error/1, get_state/1, sort/1]).

-export_type([ticket/0]).

-include("gen.hrl").

%% An error ticket containing all the informations about an error
%% and the interleaving that caused it.
-type ticket() :: {error:error(), [proc_action:proc_action()]}.

%% @doc: Create a new error ticket.
-spec new(error:error(), [proc_action:proc_action()]) -> ticket().

new(Error, ErrorState) ->
    {Error, ErrorState}.

-spec get_error(ticket()) -> error:error().

get_error({Error, _ErrorState}) ->
    Error.

-spec get_state(ticket()) -> state:state().

get_state({_Error, ErrorState}) ->
    ErrorState.

%% Sort a list of tickets according to state.
-spec sort([ticket()]) -> [ticket()].

sort(Tickets) ->
    Compare = fun(T1, T2) -> get_state(T1) =< get_state(T2) end,
    lists:sort(Compare, Tickets).
