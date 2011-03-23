%%%----------------------------------------------------------------------
%%% File        : ticket.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Error ticket interface
%%% Created     : 23 Sep 2010
%%%
%%% @doc: Error ticket interface.
%%% @end
%%%----------------------------------------------------------------------

-module(ticket).

-export([new/4, get_target/1, get_files/1, get_error/1, get_state/1, sort/1]).

-export_type([ticket/0]).

-include("gen.hrl").

%% An error ticket containing all necessary information needed to replay the
%% interleaving that caused it.
-type ticket() :: {sched:analysis_target(), [file()],
		   error:error(), state:state()}.

%% @doc: Create a new error ticket.
-spec new(sched:analysis_target(), [file()], error:error(), state:state()) ->
		 ticket().

new(Target, Files, Error, ErrorState) ->
    {Target, Files, Error, ErrorState}.

-spec get_target(ticket()) -> sched:analysis_target().

get_target({Target, _Files, _Error, _ErrorState}) ->
    Target.

-spec get_files(ticket()) -> [file()].
get_files({_Target, Files, _Error, _ErrorState}) ->
    Files.

-spec get_error(ticket()) -> error:error().

get_error({_Target, _Files, Error, _ErrorState}) ->
   Error.

-spec get_state(ticket()) -> state:state().

get_state({_Target, _Files, _Error, ErrorState}) ->
    ErrorState.

%% Sort a list of tickets according to state.
-spec sort([ticket()]) -> [ticket()].

sort(Tickets) ->
    Compare = fun(T1, T2) -> get_state(T1) =< get_state(T2) end,
    lists:sort(Compare, Tickets).
