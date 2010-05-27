%%%----------------------------------------------------------------------
%%% File    : instr.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : Instrumenter
%%%
%%% Created : 16 May 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

%% @doc: The instrumenter.

-module(instr).
-export([instrument_and_load/1]).

-include("gen.hrl").

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
    %% Compilation of original file without emiting code, just to emit all
    %% warnings or stop if an error is found, before instrumenting it.
    log:log("Validating file ~p...~n", [File]),
    PreOptions = [strong_validation, verbose, report_errors, report_warnings],
    case compile:file(File, PreOptions) of
	{ok, Module} ->
	    %% A table for holding used variable names.
	    ets:new(?NT_USED, [named_table, private]),
	    %% Instrument given source file.
	    log:log("Instrumenting file ~p... ", [File]),
	    case instrument(File) of
		{ok, NewForms} ->
		    log:log("ok~n"),
		    %% Delete `used` table.
		    ets:delete(?NT_USED),
		    %% Compile instrumented code.
		    %% TODO: More compile options?
		    log:log("Compiling instrumented code...~n"),
		    CompOptions = [binary, verbose,
				   report_errors, report_warnings],
		    case compile:forms(NewForms, CompOptions) of
			{ok, Module, Binary} ->
			    log:log("Loading module `~p`... ", [Module]),
			    case code:load_binary(Module, File, Binary) of
				{module, Module} ->
				    log:log("ok~n"),
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
	error ->
	    log:log("error~n"),
	    error
    end.

instrument(File) ->
    %% TODO: For now using an empty include path. In the future we have to
    %%       provide a means for an externally defined include path (like the
    %%       erlc -I flag).
    case epp:parse_file(File, [], []) of
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
			spawn ->
			    instrument_spawn(instrument_subtrees(Tree));
			link ->
			    instrument_link(instrument_subtrees(Tree));
			_Other -> instrument_subtrees(Tree)
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
	underscore ->
	    [{used, Used}] = ets:lookup(?NT_USED, used),
	    Fresh = erl_syntax_lib:new_variable_name(Used),
	    String = "_" ++ atom_to_list(Fresh),
	    erl_syntax:variable(String);
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
instrument_receive(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_receive),
    %% Get old receive expression's clauses.
    OldClauses = erl_syntax:receive_expr_clauses(Tree),
    NewClauses = [transform_receive_clause(Clause) || Clause <- OldClauses],
    %% `receive ... after` not supported for now.
    case erl_syntax:receive_expr_timeout(Tree) of
	none -> continue;
	_Any -> log:internal("`receive ... after` expressions not supported.~n")
    end,
    %% Create new receive expression adding the `after 0` part.
    Timeout = erl_syntax:integer(0),
    %% Create new variable to use as 'Aux'.
    [{used, Used}] = ets:lookup(?NT_USED, used),
    Fresh = erl_syntax_lib:new_variable_name(Used),
    FunVar = erl_syntax:variable(Fresh),
    Action = erl_syntax:application(FunVar, []),
    NewRecv = erl_syntax:receive_expr(NewClauses, Timeout, [Action]),
    %% Create a new fun to be the argument of rep_receive.
    FunClause = erl_syntax:clause([FunVar], [], [NewRecv]),
    FunExpr = erl_syntax:fun_expr([FunClause]),
    %% Call sched:rep_receive.
    erl_syntax:application(Module, Function, [FunExpr]).

%% Tranform a clause
%%   Msg -> [Actions]
%% to
%%   {SenderPid, Msg} -> {SenderPid, Msg, [Actions]}
transform_receive_clause(Clause) ->
    [OldPattern] = erl_syntax:clause_patterns(Clause),
    OldGuard = erl_syntax:clause_guard(Clause),
    OldBody = erl_syntax:clause_body(Clause),
    %% Create new variable to use as 'SenderPid'.
    [{used, Used}] = ets:lookup(?NT_USED, used),
    Fresh = erl_syntax_lib:new_variable_name(Used),
    PidVar = erl_syntax:variable(Fresh),
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

%% Instrument a spawn expression (only in the form spawn(fun() -> Body end
%% for now).
%% spawn(Fun) is transformed into sched:rep_spawn(Fun).
instrument_spawn(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_spawn),
    %% Fun expression arguments of the (before instrumentation) spawn call.
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).
