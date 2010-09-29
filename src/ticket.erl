%%%----------------------------------------------------------------------
%%% File        : ticket.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Error ticket interface
%%% Created     : 23 Sep 2010
%%%
%%% @doc: Error ticket interface.
%%% @end
%%%----------------------------------------------------------------------

-module(ticket).

-export([new/3, get_target/1, get_error/1, get_state/1, sort/1]).

-export_type([ticket/0]).

%% An error ticket containing information needed to replay the
%% interleaving that caused it.
-type ticket() :: {sched:analysis_target(), error:error(), state:state()}.

%% @doc: Create a new error ticket.
-spec new(sched:analysis_target(), error:error(), state:state()) ->
		 ticket().

new(Target, Error, ErrorState) ->
    {Target, Error, ErrorState}.

-spec get_target(ticket()) -> sched:analysis_target().

get_target({Target, _Error, _ErrorState}) ->
    Target.

-spec get_error(ticket()) -> error:error().

get_error({_Target, Error, _ErrorState}) ->
   Error.

-spec get_state(ticket()) -> state:state().

get_state({_Target, _Error, ErrorState}) ->
    ErrorState.

%% Sort a list of tickets according to state.
-spec sort([ticket()]) -> [ticket()].

sort(Tickets) ->
    Compare = fun(T1, T2) -> get_state(T1) =< get_state(T2) end,
    lists:sort(Compare, Tickets).
