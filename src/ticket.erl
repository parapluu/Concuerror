%%%----------------------------------------------------------------------
%%% File    : ticket.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%           Maria Christakis <christakismaria@gmail.com>
%%% Description : Error ticket interface
%%%
%%% Created : 23 Sep 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%
%%% @doc: Error ticket interface.
%%% @end
%%%----------------------------------------------------------------------

-module(ticket).

-export([new/4, get_error_type_str/1, get_error_descr_str/1,
         get_target/1, get_state/1]).

-export_type([ticket/0]).

%% An error ticket containing information needed to replay the
%% interleaving that caused it.
-type ticket() :: {sched:analysis_target(), sched:error_type(),
                   sched:error_descr(), state:state()}.

%% @doc: Create a new error ticket.
-spec new(sched:analysis_target(), sched:error_type(),
          sched:error_descr(), state:state()) ->
		 ticket().

new(Target, ErrorType, ErrorDescr, ErrorState) ->
    {Target, ErrorType, ErrorDescr, ErrorState}.

%% @doc: Return an error type string for the given ticket.
-spec get_error_type_str(ticket()) -> string().

get_error_type_str({_Target, ErrorType, _ErrorDescr, _ErrorState}) ->
    error_type_to_string(ErrorType).

%% @doc: Return the error description for the given ticket.
-spec get_error_descr_str(ticket()) -> string().

get_error_descr_str({_Target, _ErrorType, ErrorDescr, _ErrorState}) ->
    case ErrorDescr of
        {{assertion_failed, Details}, _Stack} ->
            [{module, Mod}, {line, L}, {expression, _Expr},
             {expected, _Exp}, {value, _Val}] = Details,
            io_lib:format("~p.erl:~p: The assertion failed~n", [Mod, L]);
        _Other -> io_lib:format("~p~n", [ErrorDescr])
    end.

-spec get_target(ticket()) -> sched:analysis_target().
get_target({Target, _ErrorType, _ErrorDescr, _ErrorState}) ->
    Target.

-spec get_state(ticket()) -> state:state().
get_state({_Target, _ErrorType, _ErrorDescr, ErrorState}) ->
    ErrorState.

error_type_to_string(assert) ->
    "Assertion violation";
error_type_to_string(deadlock) ->
    "Deadlock";
error_type_to_string(exception) ->
    "Exception".
