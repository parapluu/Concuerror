%%%----------------------------------------------------------------------
%%% File        : error.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Error interface
%%% Created     : 28 Sep 2010
%%%
%%% @doc: Error interface.
%%% @end
%%%----------------------------------------------------------------------

-module(error).

-export([new/2, deadlock/1, format_error_type/1, format_error_descr/1,
         type/1, type_from_descr/1]).

-export_type([error/0, assertion/0, exception/0]).

%% Error type.
-type error_type() :: 'assertion_violation' | 'deadlock' | 'exception'.

%% Error descriptor.
-type error_descr() :: term().

%% Assertion violation.
-type assertion() :: {'assertion_violation',
                   {{'assertion_violation', [{atom(), term()}]}, [term()]}}.

%% Deadlock.
-type deadlock() :: {'deadlock', [string()]}.

%% Exception.
-type exception() :: {'exception', term()}.

%% Error.
-type error() :: assertion() | deadlock() | exception().

%% @doc: Create a new error.
-spec new(error_type(), error_descr()) -> error().

new(ErrorType, ErrorDescr) ->
    {ErrorType, ErrorDescr}.

%% @doc: Create a new deadlock.
-spec deadlock(set()) -> deadlock().

deadlock(Blocked) ->
    BlockedList = lists:sort(sets:to_list(Blocked)),
    {deadlock, BlockedList}.

%% @doc: Format the error type for the given error.
-spec format_error_type(error()) -> string().

format_error_type({ErrorType, _ErrorDescr}) ->
    error_type_to_string(ErrorType).

%% @doc: Format the error description for the given error.
-spec format_error_descr(error()) -> string().

format_error_descr({ErrorType, ErrorDescr}) ->
    case ErrorType of
        assertion_violation ->
            {{assertion_violation, Details}, Stack} = ErrorDescr,
            [{module, Mod}, {line, L}, {expression, Expr},
             {expected, Exp}, {value, Val}] = Details,
            assertion_to_string(Mod, L, Expr, Val, Exp, Stack);
        deadlock -> deadlock_to_string(ErrorDescr);
        exception -> exception_to_string(ErrorDescr)
    end.

%% @doc: Return the error type for the given error.
-spec type(term()) -> term().

type({assertion_violation, _ErrorDescr}) ->
    assertion_violation;
type({deadlock, _ErrorDescr}) -> deadlock;
type({exception, _ErrorDescr}) -> exception;
type(Other) -> Other.

%% @doc: Return the error type for the given description.
-spec type_from_descr(term()) -> 'assertion_violation' | 'exception'.

type_from_descr({{assertion_violation, _Details}, _Stack}) ->
    assertion_violation;
type_from_descr(_Other) -> exception.

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

error_type_to_string(assertion_violation) ->
    "Assertion violation";
error_type_to_string(deadlock) ->
    "Deadlock";
error_type_to_string(exception) ->
    "Exception".

assertion_to_string(Mod, L, Expr, Val, Exp, Stack) ->
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

exception_to_string({Reason, Stack} = E) ->
    case is_generated_exception(Reason) of
        true -> io_lib:format("~p~n", [E]);
        false ->
            io_lib:format("Reason: ~p~nStack trace: ~p~n",
                          [Reason, Stack])
    end;         
exception_to_string(E) ->
    io_lib:format("~p~n", [E]).

is_generated_exception(R) ->
    case R of
        badarg -> false;
        badarith -> false;
        {badmatch, _V} -> false;
        function_clause -> false;
        {case_clause, _V} -> false;
        if_clause -> false;
        {try_clause, _V} -> false;
        undef -> false;
        {badfun, _F} -> false;
        {badarity, _F} -> false;
        timeout_value -> false;
        noproc -> false;
        {nocatch, _V} -> false;
        system_limit -> false;
        _Other -> true
    end.
