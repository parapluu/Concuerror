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

-export([new/2, deadlock/1, error_reason_to_string/2,
         error_stack_to_string/1, error_type_to_string/1,
         type/1, type_from_description/1]).

%% Exports for testing.
-export([stub/0]).

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

%% @doc: Convert the error reason to string.
-spec error_reason_to_string(error(), 'short' | 'long') -> string().

error_reason_to_string({ErrorType, ErrorDescr}, Details) ->
    case ErrorType of
        assertion_violation ->
            {{assertion_violation, Dets}, _Stack} = ErrorDescr,
            [{module, Mod}, {line, L}, {expression, Expr},
             {expected, Exp}, {value, Val}] = Dets,
            assertion_reason_to_string(Mod, L, Expr, Val, Exp, Details);
        deadlock ->
            deadlock_reason_to_string(ErrorDescr, Details);
        exception ->
            exception_reason_to_string(ErrorDescr, Details)
    end.

%% @doc: Convert the error stack to string.
-spec error_stack_to_string(error()) -> string().

error_stack_to_string({ErrorType, ErrorDescr}) ->
    case ErrorType of
        assertion_violation ->
            {{assertion_violation, _Dets}, Stack} = ErrorDescr,
            assertion_stack_to_string(Stack);
        deadlock ->
            deadlock_stack_to_string();
        exception ->
            exception_stack_to_string(ErrorDescr)
    end.

%% @doc: Convert the error type to string.
-spec error_type_to_string(error()) -> string().

error_type_to_string({ErrorType, _ErrorDescr}) ->
    Str =
        case ErrorType of
            assertion_violation -> "Assertion violation";
            deadlock            -> "Deadlock";
            exception           -> "Exception"
        end,
    io_lib:format("~s~n", [Str]).

%% @doc: Return the error type for the given error.
-spec type(term()) -> term().

type({assertion_violation, _ErrorDescr}) ->
    assertion_violation;
type({deadlock, _ErrorDescr}) -> deadlock;
type({exception, _ErrorDescr}) -> exception;
type(Other) -> Other.

%% @doc: Return the error type for the given description.
-spec type_from_description(term()) -> 'assertion_violation' | 'exception'.

type_from_description({{assertion_violation, _Details}, _Stack}) ->
    assertion_violation;
type_from_description(_Other) -> exception.

%%%----------------------------------------------------------------------
%%% Testing functions
%%%----------------------------------------------------------------------

%% @doc: Return an error stub for testing purposes.
-spec stub() -> error().

stub() ->
    ErrorType = assertion_violation,
    ErrorDescr = {{assertion_violation, [{module, mymodule}, {line, 42},
                                         {expression, "true =:= false"},
                                         {expected, true}, {value, false}]},
		  []},
    error:new(ErrorType, ErrorDescr).

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

assertion_reason_to_string(Mod, L, Expr, Val, Exp, Details) ->
    case Details of
        short ->
            io_lib:format("Module: ~p, Line: ~p", [Mod, L]);
        long ->
            io_lib:format("On line ~p of module ~p, "
                          ++ "the expression ~s evaluates to ~p "
                          ++ "instead of ~p~n",
                          [L, Mod, Expr, Val, Exp])
    end.

assertion_stack_to_string(Stack) ->
    io_lib:format("~p", [Stack]).

deadlock_reason_to_string(Ps, Details) ->
    Str = processes_to_string(Ps),
    case Details of
        short ->
            case Ps of
                [_] ->
                    io_lib:format("Process: ~s", [Str]);
                _More ->
                    io_lib:format("Processes: ~s", [Str])
            end;
        long ->
            case Ps of
                [_] ->
                    io_lib:format("Process ~s blocks~n", [Str]);
                _More ->
                    io_lib:format("Processes ~s block~n", [Str])
            end
    end.

deadlock_stack_to_string() ->
    "".

exception_reason_to_string({Reason, _Stack} = E, Details) ->
    case is_generated_exception(Reason) of
        true ->
            case Details of
                short -> io_lib:format("Exit: ~p", [E]);
                long ->  io_lib:format("~p~n", [E])
            end;
        false ->
            case Details of
                short -> io_lib:format("Exit: ~p", [Reason]);
                long -> io_lib:format("~p~n", [Reason])
            end
    end;         
exception_reason_to_string(E, Details) ->
    case Details of
        short -> io_lib:format("Exit: ~p", [E]);
        long -> io_lib:format("~p~n", [E])
    end.

exception_stack_to_string({Reason, Stack}) ->
    case is_generated_exception(Reason) of
        true -> "";
        false -> io_lib:format("~p", [Stack])
    end;
exception_stack_to_string(_E) -> "".

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

processes_to_string([P]) -> P;
processes_to_string([P1, P2]) ->
    io_lib:format("~s and ~s", [P1, P2]);
processes_to_string([P|Ps]) ->
    io_lib:format("~s, ", [P]) ++
        processes_to_string(Ps).
