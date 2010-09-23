%%%----------------------------------------------------------------------
%%% File    : ticket.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : Error ticket interface
%%%
%%% Created : 23 Sep 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%
%%% @doc: Error ticket interface.
%%% @end
%%%----------------------------------------------------------------------

-module(ticket).

-export([new/3, get_error_string/1, get_target/1, get_state/1]).

-export_type([ticket/0]).

%% An error ticket containing information needed to replay the
%% interleaving that caused it.
-type ticket() :: {sched:analysis_target(), sched:error_descr(), sched:state()}.

%% @doc: Create a new error ticket.
-spec new(sched:analysis_target(), sched:error_descr(), sched:state()) ->
		 ticket().

new(Target, ErrorDescr, ErrorState) ->
    {Target, ErrorDescr, ErrorState}.

%% @doc: Return an error description string for the given ticket.
-spec get_error_string(ticket()) -> string().

get_error_string({_Target, ErrorDescr, _ErrorState}) ->
    error_descr_to_string(ErrorDescr).

-spec get_target(ticket()) -> sched:analysis_target().
get_target({Target, _ErrorDescr, _ErrorState}) ->
    Target.

-spec get_state(ticket()) -> sched:state().
get_state({_Target, _ErrorDescr, ErrorState}) ->
    ErrorState.

error_descr_to_string(assert) ->
    "Assertion violation";
error_descr_to_string(deadlock) ->
    "Deadlock".
