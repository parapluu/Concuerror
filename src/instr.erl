%%%----------------------------------------------------------------------
%%% File    : instr.erl
%%% Authors : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%           Maria Christakis <christakismaria@gmail.com>
%%% Description : Instrumenter
%%%
%%% Created : 16 May 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%
%%% @doc: Instrumenter
%%% @end
%%%----------------------------------------------------------------------

-module(instr).
-export([instrument_and_load/1]).

-include("gen.hrl").

-define(INCLUDE_DIR, filename:absname("include")).

%% @spec instrument_and_load(Files::[file()]) -> 'ok' | 'error'
%% @doc: Instrument, compile and load a list of files.
%%
%% Each file is first validated (i.e. checked whether it will compile
%% successfully). If no errors are encountered, the file gets instrumented,
%% compiled and loaded. If all of these actions are successfull, the function
%% returns `ok', otherwise `error' is returned. No `.beam' files are produced.
-spec instrument_and_load([file()]) -> 'ok' | 'error'.

instrument_and_load([]) ->
    log:log("No files instrumented~n"),
    ok;
instrument_and_load([File]) ->
    instrument_and_load_one(File);
instrument_and_load([File | Rest]) ->
    case instrument_and_load_one(File) of
	ok -> instrument_and_load(Rest);
	error -> error
    end.

%% Instrument and load a single file.
instrument_and_load_one(File) ->
    %% Compilation of original file without emitting code, just to show
    %% warnings or stop if an error is found, before instrumenting it.
    log:log("Validating file ~p...~n", [File]),
    PreOptions = [strong_validation, verbose, return, {i, ?INCLUDE_DIR}],
    case compile:file(File, PreOptions) of
	{ok, Module, Warnings} ->
	    %% Log warning messages.
	    log_warning_list(Warnings),
	    %% A table for holding used variable names.
	    ets:new(?NT_USED, [named_table, private]),
	    %% Instrument given source file.
	    log:log("Instrumenting file ~p...~n", [File]),
	    case instrument(File) of
		{ok, NewForms} ->
		    %% Delete `used` table.
		    ets:delete(?NT_USED),
		    %% Compile instrumented code.
		    %% TODO: More compile options?
		    log:log("Compiling instrumented code...~n"),
		    CompOptions = [binary],
		    case compile:forms(NewForms, CompOptions) of
			{ok, Module, Binary} ->
			    log:log("Loading module `~p`...~n", [Module]),
			    case code:load_binary(Module, File, Binary) of
				{module, Module} ->
				    ok;
				{error, Error} ->
				    log:log("error~n~p~n", [Error]),
				    error
			    end;
			error ->
			    log:log("error~n"),
			    error
		    end;
		{error, Error} ->
		    log:log("error: ~p~n", [Error]),
		    %% Delete `used` table.
		    ets:delete(?NT_USED),
		    error
	    end;
	{error, Errors, Warnings} ->
	    log_error_list(Errors),
	    log_warning_list(Warnings),
	    log:log("error~n"),
	    error
    end.

instrument(File) ->
    %% TODO: For now using the default and the test directory include path.
    %%       In the future we have to provide a means for an externally
    %%       defined include path (like the erlc -I flag).
    case epp:parse_file(File, [?INCLUDE_DIR, filename:dirname(File)], []) of
	{ok, OldForms} ->
	    Tree = erl_recomment:recomment_forms(OldForms, []),
	    MapFun = fun(T) -> instrument_toplevel(T) end,
	    Transformed = erl_syntax_lib:map_subtrees(MapFun, Tree),
	    Abstract = erl_syntax:revert(Transformed),
	    %% io:put_chars(erl_prettypr:format(Abstract)),
	    NewForms = erl_syntax:form_list_elements(Abstract),
	    {ok, NewForms};
	{error, Error} -> {error, Error}
    end.

%% Instrument a "top-level" element.
%% Of the "top-level" elements, i.e. functions, specs, etc., only functions are
%% transformed, so leave everything else as is.
instrument_toplevel(Tree) ->
    case erl_syntax:type(Tree) of
	function -> instrument_function(Tree);
	_Other -> Tree
    end.

%% Instrument a function.
instrument_function(Tree) ->
    %% Delete previous entry in `used` table (if any).
    ets:delete_all_objects(?NT_USED),
    %% A set of all variables used in the function.
    Used = erl_syntax_lib:variables(Tree),
    %% Insert the used set into `used` table.
    ets:insert(?NT_USED, {used, Used}),
    instrument_subtrees(Tree).

%% Instrument all subtrees of Tree.
instrument_subtrees(Tree) ->
    MapFun = fun(T) -> instrument_term(T) end,
    erl_syntax_lib:map_subtrees(MapFun, Tree).

%% Instrument a term.
instrument_term(Tree) ->
    case erl_syntax:type(Tree) of
	application ->
	    Qualifier = erl_syntax:application_operator(Tree),
	    case erl_syntax:type(Qualifier) of
		atom ->
		    Function = erl_syntax:atom_value(Qualifier),
		    case Function of
			link ->
			    instrument_link(instrument_subtrees(Tree));
			spawn ->
			    instrument_spawn(instrument_subtrees(Tree));
			spawn_link ->
			    instrument_spawn_link(instrument_subtrees(Tree));
			_Other -> instrument_subtrees(Tree)
		    end;
                module_qualifier ->
                    Argument = erl_syntax:module_qualifier_argument(Qualifier),
                    Body = erl_syntax:module_qualifier_body(Qualifier),
                    case erl_syntax:type(Argument) =:= atom andalso
                        erl_syntax:type(Body) =:= atom of
                        true ->
                            Module = erl_syntax:atom_value(Argument),
                            case Module of
                                erlang ->
                                    Function = erl_syntax:atom_value(Body),
                                    case Function of
                                        link ->
                                            instrument_link(
                                              instrument_subtrees(Tree));
                                        spawn ->
                                            instrument_spawn(
                                              instrument_subtrees(Tree));
                                        spawn_link ->
                                            instrument_spawn_link(
                                              instrument_subtrees(Tree));
                                        yield -> instrument_yield();
                                        _Other -> instrument_subtrees(Tree)
                                    end; 
                                _Other -> instrument_subtrees(Tree)
                            end;
                        false -> instrument_subtrees(Tree)
                    end;
		_Other -> instrument_subtrees(Tree)
	    end;
	infix_expr ->
	    Operator = erl_syntax:infix_expr_operator(Tree),
	    case erl_syntax:operator_name(Operator) of
		'!' -> instrument_send(instrument_subtrees(Tree));
		_Other -> instrument_subtrees(Tree)
	    end;
	receive_expr ->
	    instrument_receive(instrument_subtrees(Tree));
	%% Replace every underscore with a new (underscore-prefixed) variable.
	underscore -> new_underscore_variable();
	_Other -> instrument_subtrees(Tree)
    end.

%% Instrument a link/1 call.
%% link(Pid) is transformed into sched:rep_link(Pid).
instrument_link(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_link),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a receive expression.
%% receive
%%    Msg -> Actions
%% end
%% is transformed into
%% sched:rep_receive(Fun),
%% where Fun = fun(Aux) ->
%%               receive
%%                 {SenderPid, Msg} ->
%%                   {SenderPid, Msg, Actions}
%%               after 0 ->
%%                 Aux()
%%               end
%%             end
instrument_receive(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_receive),
    %% Get old receive expression's clauses.
    OldClauses = erl_syntax:receive_expr_clauses(Tree),
    case OldClauses of
        %% Keep only the action of any `receive after' construct
        %% without patterns.
        [] ->
            Action = erl_syntax:receive_expr_action(Tree),
            erl_syntax:block_expr(Action);
        _Other ->
            NewClauses = [transform_receive_clause(Clause)
                          || Clause <- OldClauses],
            %% `receive ... after` not supported for now.
            case erl_syntax:receive_expr_timeout(Tree) of
                none -> continue;
                _Any -> log:internal("`receive ... after` expressions " ++
                                     "not supported.~n")
            end,
            %% Create new receive expression adding the `after 0` part.
            Timeout = erl_syntax:integer(0),
            %% Create new variable to use as 'Aux'.
            FunVar = new_variable(),
            Action = erl_syntax:application(FunVar, []),
            NewRecv = erl_syntax:receive_expr(NewClauses, Timeout, [Action]),
            %% Create a new fun to be the argument of rep_receive.
            FunClause = erl_syntax:clause([FunVar], [], [NewRecv]),
            FunExpr = erl_syntax:fun_expr([FunClause]),
            %% Call sched:rep_receive.
            erl_syntax:application(Module, Function, [FunExpr])
    end.

%% Tranform a clause
%%   Msg -> [Actions]
%% to
%%   {SenderPid, Msg} -> {SenderPid, Msg, [Actions]}
transform_receive_clause(Clause) ->
    [OldPattern] = erl_syntax:clause_patterns(Clause),
    OldGuard = erl_syntax:clause_guard(Clause),
    OldBody = erl_syntax:clause_body(Clause),
    %% Create new variable to use as 'SenderPid'.
    PidVar = new_variable(),
    NewPattern = [erl_syntax:tuple([PidVar, OldPattern])],
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_receive_notify),
    Arguments = [PidVar, OldPattern],
    Notify = erl_syntax:application(Module, Function, Arguments),
    NewBody = [Notify | OldBody],
    erl_syntax:clause(NewPattern, OldGuard, NewBody).

%% Instrument a Pid ! Msg expression.
%% Pid ! Msg is transformed into rep:send(Pid, Msg).
instrument_send(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_send),
    Pid = erl_syntax:infix_expr_left(Tree),
    Msg = erl_syntax:infix_expr_right(Tree),
    Sender = erl_syntax:application(erl_syntax:atom(self), []),
    Arguments = [Pid, erl_syntax:tuple([Sender, Msg])],
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a spawn/1 call.
%% `spawn(Fun)' is transformed into `sched:rep_spawn(Fun)'.
instrument_spawn(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_spawn),
    %% Fun expression arguments of the (before instrumentation) spawn call.
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a spawn_link/1 call.
%% `spawn_link(Fun)' is transformed into `sched:rep_spawn_link(Fun)'.
instrument_spawn_link(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_spawn_link),
    %% Fun expression arguments of the (before instrumentation) spawn call.
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument an erlang:yield/0 call.
%% `erlang:yield' is transformed into `true'.
instrument_yield() ->
    erl_syntax:atom(true).

%%%----------------------------------------------------------------------
%%% Utilities
%%%----------------------------------------------------------------------

new_variable() ->
    [{used, Used}] = ets:lookup(?NT_USED, used),
    Fresh = erl_syntax_lib:new_variable_name(Used),
    ets:insert(?NT_USED, {used, sets:add_element(Fresh, Used)}),
    erl_syntax:variable(Fresh).

new_underscore_variable() ->
    [{used, Used}] = ets:lookup(?NT_USED, used),
    new_underscore_variable(Used).

new_underscore_variable(Used) ->
    Fresh1 = erl_syntax_lib:new_variable_name(Used),
    String = "_" ++ atom_to_list(Fresh1),
    Fresh2 = list_to_atom(String),
    case is_fresh(Fresh2, Used) of
        true ->
            ets:insert(?NT_USED, {used, sets:add_element(Fresh2, Used)}),
            erl_syntax:variable(Fresh2);
        false ->
            new_underscore_variable(Used)
    end.

is_fresh(Atom, Set) ->
    not sets:is_element(Atom, Set).

%%%----------------------------------------------------------------------
%%% Logging
%%%----------------------------------------------------------------------

%% Log a list of errors, as returned by compile:file/2.
log_error_list(List) ->
    log_list(List, "").

%% Log a list of warnings, as returned by compile:file/2.
log_warning_list(List) ->
    log_list(List, "Warning:").

%% Log a list of error or warning descriptors, as returned by compile:file/2.
log_list(List, Pre) ->
    LogFun = fun(String) -> log:log(String) end,
    [LogFun(io_lib:format("~s:~p: ~s ", [File, Line, Pre]) ++
                Mod:format_error(Descr) ++ "\n") || {File, Info} <- List,
                                                    {Line, Mod, Descr} <- Info].
