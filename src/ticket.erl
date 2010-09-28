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

-export([new/3, get_error_type_str/1, get_error_descr_str/1,
         get_target/1, get_state/1]).

-export_type([ticket/0]).

%% Error descriptor.
-type error() :: {sched:error_type(), sched:error_descr()}.

%% An error ticket containing information needed to replay the
%% interleaving that caused it.
-type ticket() :: {sched:analysis_target(), error(), state:state()}.

%% @doc: Create a new error ticket.
-spec new(sched:analysis_target(), error(), state:state()) ->
		 ticket().

new(Target, Error, ErrorState) ->
    {Target, Error, ErrorState}.

%% @doc: Return an error type string for the given ticket.
-spec get_error_type_str(ticket()) -> string().

get_error_type_str({_Target, {ErrorType, _ErrorDescr}, _ErrorState}) ->
    error_type_to_string(ErrorType).

%% @doc: Return the error description for the given ticket.
-spec get_error_descr_str(ticket()) -> string().

get_error_descr_str({_Target, {ErrorType, ErrorDescr}, _ErrorState}) ->
    case ErrorType of
        assert ->
            {{assertion_violation, Details}, Stack} = ErrorDescr,
            [{module, Mod}, {line, L}, {expression, Expr},
             {expected, Exp}, {value, Val}] = Details,
            assert_to_string(Mod, L, Expr, Val, Exp, Stack);
        deadlock -> deadlock_to_string(ErrorDescr);
        exception -> exception_to_string(ErrorDescr)
    end.

-spec get_target(ticket()) -> sched:analysis_target().
get_target({Target, _Error, _ErrorState}) ->
    Target.

-spec get_state(ticket()) -> state:state().
get_state({_Target, _Error, ErrorState}) ->
    ErrorState.

error_type_to_string(assert) ->
    "Assertion violation";
error_type_to_string(deadlock) ->
    "Deadlock";
error_type_to_string(exception) ->
    "Exception".

assert_to_string(Mod, L, Expr, Val, Exp, Stack) ->
    io_lib:format("~p.erl:~p: "
                  ++ "The expression '~s' evaluates to '~p' instead of '~p'~n"
                  ++ "Stack trace: ~p~n",
                  [Mod, L, Expr, Val, Exp, Stack]).

deadlock_to_string([P]) ->
    io_lib:format("Process ~s blocks~n", [P]);
deadlock_to_string(Ps) ->
    Str = processes_to_string(Ps),
    io_lib:format("Processes ~s block~n", [Str]).

processes_to_string([P1, P2]) ->
    io_lib:format("~s and ~s", [P1, P2]);
processes_to_string([P|Ps]) ->
    io_lib:format("~s, ", [P]) ++
        processes_to_string(Ps).

exception_to_string(E) ->
    io_lib:format("~p~n", [E]).
