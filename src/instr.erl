%%%----------------------------------------------------------------------
%%% File        : instr.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Instrumenter
%%% Created     : 16 May 2010
%%%
%%% @doc: Instrumenter
%%% @end
%%%----------------------------------------------------------------------

-module(instr).
-export([delete_and_purge/1, instrument_and_load/1]).

-include("gen.hrl").

-define(INCLUDE_DIR, filename:absname("include")).

%% Delete and purge all modules in Files.
-spec delete_and_purge([file()]) -> 'ok'.

delete_and_purge(Files) ->
    ModsToPurge = [list_to_atom(filename:basename(F, ".erl")) || F <- Files],
    [begin code:delete(M), code:purge(M) end || M <- ModsToPurge],
    ok.

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
                        demonitor ->
                            instrument_demonitor(instrument_subtrees(Tree));
                        halt ->
			    instrument_halt(instrument_subtrees(Tree));
			link ->
			    instrument_link(instrument_subtrees(Tree));
                        monitor ->
                            instrument_monitor(instrument_subtrees(Tree));
                        process_flag ->
                            instrument_process_flag(instrument_subtrees(Tree));
                        register ->
                            instrument_register(instrument_subtrees(Tree));
			spawn ->
			    instrument_spawn(instrument_subtrees(Tree));
			spawn_link ->
			    instrument_spawn_link(instrument_subtrees(Tree));
                        spawn_monitor ->
                            instrument_spawn_monitor(instrument_subtrees(Tree));
                        unlink ->
                            instrument_unlink(instrument_subtrees(Tree));
                        unregister ->
                            instrument_unregister(instrument_subtrees(Tree));
                        whereis ->
                            instrument_whereis(instrument_subtrees(Tree));
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
                                        demonitor ->
                                            instrument_demonitor(
                                              instrument_subtrees(Tree));
                                        halt ->
					    instrument_halt(
					      instrument_subtrees(Tree));
                                        link ->
                                            instrument_link(
                                              instrument_subtrees(Tree));
                                        monitor ->
                                            instrument_monitor(
                                              instrument_subtrees(Tree));
                                        process_flag ->
                                            instrument_process_flag(
                                              instrument_subtrees(Tree));
                                        register ->
                                            instrument_register(
                                              instrument_subtrees(Tree));
                                        spawn ->
                                            instrument_spawn(
                                              instrument_subtrees(Tree));
                                        spawn_link ->
                                            instrument_spawn_link(
                                              instrument_subtrees(Tree));
                                        spawn_monitor ->
                                            instrument_spawn_monitor(
                                              instrument_subtrees(Tree));
                                        unlink ->
                                            instrument_unlink(
                                              instrument_subtrees(Tree));
                                        unregister ->
                                            instrument_unregister(
                                              instrument_subtrees(Tree));
                                        whereis ->
                                            instrument_whereis(
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

%% Instrument a demonitor/{1,2} call.
%% demonitor(Args) is transformed into sched:rep_demonitor(Args).
instrument_demonitor(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_demonitor),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a halt/{0,1} call.
%% halt(Args) is transformed into sched:rep_halt().
instrument_halt(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_halt),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a link/1 call.
%% link(Pid) is transformed into sched:rep_link(Pid).
instrument_link(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_link),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a monitor/1 call.
%% monitor(Ref) is transformed into sched:rep_monitor(Ref).
instrument_monitor(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_monitor),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a receive expression.
%% -----------------------------------------------------------------------------
%% receive
%%    Patterns -> Actions
%% end
%%
%% is transformed into
%%
%% sched:rep_receive(Fun),
%% where Fun = fun(Aux) ->
%%               receive
%%                   NewPatterns -> NewActions
%%               after 0 ->
%%                 Aux()
%%               end
%%             end
%%
%% Pattern -> NewPattern maps are divided into the following categories:
%%
%%   - Patterns consisting of size-3 tuples, i.e. `{X, Y, Z}' are kept as
%%     they are and additionally a pattern `{Fresh, {X, Y, Z}}' is added.
%%     That way possible `{'EXIT', Pid, Reason}' messages are caught
%%     if the receiver has trap_exit set to true.
%%
%%   - Same as above for size-5 tuples, to catch possible 'DOWN' messages.
%%
%%   - Same as above for catch-all patterns, i.e. `Var' or `_' patterns.
%%
%%   - All other patterns `Pattern' are transformed into {Fresh, Pattern}.
%%
%% `Action' is normally transformed into
%% `sched:rep_receive(Fresh, Pattern), Action'.
%% In the case of size-3, size-5 and catch-all patterns, the patterns that
%% are duplicated as they were originally, will have a NewAction of
%% `sched:rep_receive(Pattern), Action'.
%% -----------------------------------------------------------------------------
%% receive
%%   Patterns -> Actions
%% after N -> AfterActions
%%
%% is transformed into
%%
%% receive
%%   NewPatterns -> NewActions
%% after 0 -> AfterActions
%%
%% Pattens and Actions are mapped into NewPatterns and NewActions as described
%% previously for the case of a `receive' expression with no `after' clause.
%% -----------------------------------------------------------------------------
%% receive
%% after N -> AfterActions
%%
%% is transformed into
%%
%% AfterActions
%%
%% That is, the `receive' expression and the delay are dropped off completely.
%% -----------------------------------------------------------------------------
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
	    Fold = fun(Old, Acc) ->
			   case transform_receive_clause(Old) of
			       [One] -> [One|Acc];
			       [One, Two] -> [One, Two|Acc]
			   end
		   end,
	    NewClauses = lists:foldr(Fold, [], OldClauses),
            %% Create new receive expression adding the `after 0` part.
            Timeout = erl_syntax:integer(0),
            case erl_syntax:receive_expr_timeout(Tree) of
                %% Instrument `receive` without `after` part.
                none ->
                    %% Create new variable to use as 'Aux'.
                    FunVar = new_variable(),
                    Action = [erl_syntax:application(FunVar, [])],
                    NewRecv = erl_syntax:receive_expr(NewClauses, Timeout,
                                                      Action),
                    %% Create a new fun to be the argument of rep_receive.
                    FunClause = erl_syntax:clause([FunVar], [], [NewRecv]),
                    FunExpr = erl_syntax:fun_expr([FunClause]),
                    %% Call sched:rep_receive.
                    erl_syntax:application(Module, Function, [FunExpr]);
                %% Instrument `receive` with `after` part.
                _Any ->
                    Action = erl_syntax:receive_expr_action(Tree),
                    erl_syntax:receive_expr(NewClauses, Timeout, Action)
            end
    end.

%% Transform a Pattern -> Action clause, according to its Pattern.
transform_receive_clause(Clause) ->
    [Pattern] = erl_syntax:clause_patterns(Clause),
    Fnormal = fun(P) -> [transform_receive_clause_regular(P)] end,
    Fspecial = fun(P) -> [transform_receive_clause_regular(P),
     			  transform_receive_clause_special(P)]
    	       end,
    case erl_syntax:type(Pattern) of
	tuple ->
	    case erl_syntax:tuple_size(Pattern) of
		3 -> Fspecial(Clause);
		5 -> Fspecial(Clause);
		_OtherSize -> Fnormal(Clause)
	    end;
	variable -> Fspecial(Clause);
	_OtherType -> Fnormal(Clause)
    end.    

%% Tranform a clause
%%   Pattern -> Action
%% into
%%   {Fresh, Pattern} -> sched:rep_receive_notify(Fresh, Pattern), Action
transform_receive_clause_regular(Clause) ->
    [OldPattern] = erl_syntax:clause_patterns(Clause),
    OldGuard = erl_syntax:clause_guard(Clause),
    OldBody = erl_syntax:clause_body(Clause),
    PidVar = new_variable(),
    NewPattern = [erl_syntax:tuple([PidVar, OldPattern])],
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_receive_notify),
    Arguments = [PidVar, OldPattern],
    Notify = erl_syntax:application(Module, Function, Arguments),
    NewBody = [Notify|OldBody],
    erl_syntax:clause(NewPattern, OldGuard, NewBody).

%% Transform a clause
%%   Pattern -> Action
%% into
%%   Pattern -> sched:rep_receive_notify(Pattern), Action
transform_receive_clause_special(Clause) ->
    [OldPattern] = erl_syntax:clause_patterns(Clause),
    OldGuard = erl_syntax:clause_guard(Clause),
    OldBody = erl_syntax:clause_body(Clause),
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_receive_notify),
    Arguments = [OldPattern],
    Notify = erl_syntax:application(Module, Function, Arguments),
    NewBody = [Notify|OldBody],
    erl_syntax:clause([OldPattern], OldGuard, NewBody).

%% Instrument a Pid ! Msg expression.
%% Pid ! Msg is transformed into rep:send(Pid, Msg).
instrument_send(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_send),
    Dest = erl_syntax:infix_expr_left(Tree),
    Msg = erl_syntax:infix_expr_right(Tree),
    Arguments = [Dest, Msg],
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a process_flag/2 call.
%% process_flag(Flag, Value) is transformed into
%% sched:rep_process_flag(Flag, Value).
instrument_process_flag(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_process_flag),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a register/2 call.
%% register(RegName, P) is transformed into sched:rep_register(RegName, P).
instrument_register(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_register),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a spawn/{1,2,3,4} call.
%% spawn(Fun) is transformed into sched:rep_spawn(Fun).
instrument_spawn(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_spawn),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a spawn_link/{1,2,3,4} call.
%% spawn_link(Args) is transformed into sched:rep_spawn_link(Args).
instrument_spawn_link(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_spawn_link),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a spawn_monitor/{1,3} call.
%% spawn_monitor(Args) is transformed into sched:rep_spawn_monitor(Args).
instrument_spawn_monitor(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_spawn_monitor),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument an unlink/1 call.
%% unlink(Pid) is transformed into sched:rep_unlink(Pid).
instrument_unlink(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_unlink),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument an unregister/1 call.
%% unregister(RegName) is transformed into sched:rep_unregister(RegName).
instrument_unregister(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_unregister),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument a whereis/1 call.
%% whereis(RegName) is transformed into sched:rep_whereis(RegName).
instrument_whereis(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_whereis),
    Arguments = erl_syntax:application_arguments(Tree),
    erl_syntax:application(Module, Function, Arguments).

%% Instrument an erlang:yield/0 call.
%% erlang:yield is transformed into true.
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
