%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Instrumenter
%%%----------------------------------------------------------------------

-module(instr).
-export([delete_and_purge/1, instrument_and_compile/3, load/1]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Debug
%%%----------------------------------------------------------------------

%%-define(PRINT, true).
-ifdef(PRINT).
-define(print(S_), io:put_chars(erl_prettypr:format(S_))).
-else.
-define(print(S_), ok).
-endif.

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% List of attributes that should be stripped.
-define(ATTR_STRIP, [type, spec, opaque, export_type, import_type]).

%% Instrumented auto-imported functions of 'erlang' module.
-define(INSTR_ERL_FUN,
        [{demonitor, 1},
         {demonitor, 2},
         {halt, 0},
         {halt, 1},
         {is_process_alive, 1},
         {link, 1},
         {monitor, 2},
         {process_flag, 2},
         {register, 2},
         {spawn, 1},
         {spawn, 3},
         {spawn_link, 1},
         {spawn_link, 3},
         {spawn_monitor, 1},
         {spawn_monitor, 3},
         {spawn_opt, 2},
         {spawn_opt, 4},
         {unlink, 1},
         {unregister, 1},
         {whereis, 1}]).

%% Instrumented functions called as erlang:FUNCTION.
-define(INSTR_ERL_MOD_FUN,
        [{erlang, send, 2}, {erlang, send, 3}] ++
            [{erlang, F, A} || {F, A} <- ?INSTR_ERL_FUN]).

%% Instrumented functions from ets module.
-define(INSTR_ETS_FUN,
        [{ets, insert_new, 2},
         {ets, lookup, 2},
         {ets, select_delete, 2},
         {ets, insert, 2},
         {ets, delete, 1},
         {ets, delete, 2},
         {ets, match_object, 1},
         {ets, match_object, 3},
         {ets, match_delete, 2},
         {ets, foldl, 3}]).

%% Instrumented mod:fun.
-define(INSTR_MOD_FUN, ?INSTR_ERL_MOD_FUN ++ ?INSTR_ETS_FUN).

%% Module containing replacement functions.
-define(REP_MOD, rep).

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

-type mfb() :: {module(), file(), binary()}.

%%%----------------------------------------------------------------------
%%% Instrumentation utilities
%%%----------------------------------------------------------------------

%% Delete and purge all modules in Files.
-spec delete_and_purge([file()]) -> 'ok'.

delete_and_purge(Files) ->
    ModsToPurge = [list_to_atom(filename:basename(F, ".erl")) || F <- Files],
    Fun = fun (M) -> code:purge(M), code:delete(M), code:purge(M) end,
    lists:foreach(Fun, ModsToPurge).

%% @spec instrument(Files::[file()], Includes::[file:name()],
%%              Defines::epp:macros()) -> 'ok' | 'error'
%% @doc: Instrument and compile a list of files.
%%
%% Each file is first validated (i.e. checked whether it will compile
%% successfully). If no errors are encountered, the file gets instrumented and
%% compiled. If these actions are successfull, the function returns `{ok, Bin}',
%% otherwise `error' is returned. No `.beam' files are produced.
-spec instrument_and_compile([file()], [file:name()], epp:macros()) ->
    {'ok', [mfb()]} | 'error'.

instrument_and_compile(Files, Includes, Defines) ->
    instrument_and_compile_aux(Files, Includes, Defines, []).

instrument_and_compile_aux([], _Includes, _Defines, Acc) ->
    {ok, lists:reverse(Acc)};
instrument_and_compile_aux([File|Rest], Includes, Defines, Acc) ->
    case instrument_and_compile_one(File, Includes, Defines) of
        error -> error;
        Result -> instrument_and_compile_aux(Rest,Includes,Defines,[Result|Acc])
    end.

%% Instrument and compile a single file.
instrument_and_compile_one(File, Includes, Defines) ->
    %% Compilation of original file without emitting code, just to show
    %% warnings or stop if an error is found, before instrumenting it.
    log:log("Validating file ~p...~n", [File]),
    OptIncludes = lists:map(fun(I) -> {i, I} end, Includes),
    OptDefines  = lists:map(fun({M,V}) -> {d,M,V} end, Defines),
    PreOptions = [strong_validation,verbose,return | OptIncludes++OptDefines],
    case compile:file(File, PreOptions) of
        {ok, Module, Warnings} ->
            %% Log warning messages.
            log_warning_list(Warnings),
            %% A table for holding used variable names.
            ?NT_USED = ets:new(?NT_USED, [named_table, private]),
            %% Instrument given source file.
            log:log("Instrumenting file ~p...~n", [File]),
            case instrument(File, Includes, Defines) of
                {ok, NewForms} ->
                    %% Delete `used` table.
                    ets:delete(?NT_USED),
                    %% Compile instrumented code.
                    %% TODO: More compile options?
                    log:log("Compiling instrumented code...~n"),
                    CompOptions = [binary],
                    case compile:forms(NewForms, CompOptions) of
                        {ok, Module, Binary} -> {Module, File, Binary};
                        error -> log:log("error~n"), error
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

-spec load([mfb()]) -> 'ok' | 'error'.

load([]) -> ok;
load([MFB|Rest]) ->
    case load_one(MFB) of
        ok -> load(Rest);
        error -> error
    end.

load_one({Module, File, Binary}) ->
    case code:load_binary(Module, File, Binary) of
        {module, Module} -> ok;
        {error, Error} ->
            log:log("error~n~p~n", [Error]),
            error
    end.

instrument(File, Includes, Defines) ->
    NewIncludes = [filename:dirname(File) | Includes],
    case epp:parse_file(File, NewIncludes, Defines) of
        {ok, OldForms} ->
            %% Remove `type` and `spec` attributes to avoid errors
            %% due to record expansion below.
            StrippedForms = strip_attributes(OldForms, []),
            ExpRecForms = erl_expand_records:module(StrippedForms, []),
            Tree = erl_recomment:recomment_forms(ExpRecForms, []),
            MapFun = fun(T) -> instrument_toplevel(T) end,
            Transformed = erl_syntax_lib:map_subtrees(MapFun, Tree),
            Abstract = erl_syntax:revert(Transformed),
            ?print(Abstract),
            NewForms = erl_syntax:form_list_elements(Abstract),
            {ok, NewForms};
        {error, _} = Error -> Error
    end.

%% XXX: Implementation dependent.
strip_attributes([], Acc) -> lists:reverse(Acc);
strip_attributes([{attribute, _Line, Name, _Misc} = Head|Rest], Acc) ->
    case lists:member(Name, ?ATTR_STRIP) of
        true -> strip_attributes(Rest, Acc);
        false -> strip_attributes(Rest, [Head|Acc])
    end;
strip_attributes([Head|Rest], Acc) ->
    strip_attributes(Rest, [Head|Acc]).

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
            NewTree = instrument_subtrees(Tree),
            case get_mfa(NewTree) of
                no_instr -> NewTree;
                {normal, Mfa} -> instrument_application(Mfa);
                {var, Mfa} -> instrument_var_application(Mfa)
            end;
        infix_expr ->
            Operator = erl_syntax:infix_expr_operator(Tree),
            case erl_syntax:operator_name(Operator) of
                '!' -> instrument_send(instrument_subtrees(Tree));
                _Other -> instrument_subtrees(Tree)
            end;
        receive_expr -> instrument_receive(instrument_subtrees(Tree));
        underscore -> new_underscore_variable();
        _Other -> instrument_subtrees(Tree)
    end.

%% Return {ModuleAtom, FunctionAtom, [ArgTree]} for a function call that
%% is going to be instrumented or 'no_instr' otherwise.
get_mfa(Tree) ->
    Qualifier = erl_syntax:application_operator(Tree),
    ArgTrees = erl_syntax:application_arguments(Tree),
    case erl_syntax:type(Qualifier) of
        atom ->
            Function = erl_syntax:atom_value(Qualifier),
            needs_instrument(Function, ArgTrees);
        module_qualifier ->
            ModTree = erl_syntax:module_qualifier_argument(Qualifier),
            FunTree = erl_syntax:module_qualifier_body(Qualifier),
            case has_atoms_only(ModTree) andalso
                has_atoms_only(FunTree) of
                true ->
                    Module = erl_syntax:atom_value(ModTree),
                    Function = erl_syntax:atom_value(FunTree),
                    needs_instrument(Module, Function, ArgTrees);
                false -> {var, {ModTree, FunTree, ArgTrees}}
            end;
        _Other -> no_instr
    end.

%% Returns true if Tree is an atom or a qualified name containing only atoms.
has_atoms_only(Tree) ->
    Type = erl_syntax:type(Tree),
    IsAtom = fun(T) -> erl_syntax:type(T) =:= atom end,
    IsAtom(Tree)
        orelse
          (Type =:= qualified_name andalso
           lists:all(IsAtom, erl_syntax:qualified_name_segments(Tree))).


%% Determine whether an auto-exported BIF call needs instrumentation.
needs_instrument(Function, ArgTrees) ->
    Arity = length(ArgTrees),
    case lists:member({Function, Arity}, ?INSTR_ERL_FUN) of
        true -> {normal, {erlang, Function, ArgTrees}};
        false -> no_instr
    end.

%% Determine whether a `foo:bar(...)` call needs instrumentation.
needs_instrument(Module, Function, ArgTrees) ->
    Arity = length(ArgTrees),
    case lists:member({Module, Function, Arity}, ?INSTR_MOD_FUN) of
        true -> {normal, {Module, Function, ArgTrees}};
        false -> no_instr
    end.

instrument_application({erlang, Function, ArgTrees}) ->
    RepMod = erl_syntax:atom(?REP_MOD),
    RepFun = erl_syntax:atom(list_to_atom("rep_" ++ atom_to_list(Function))),
    erl_syntax:application(RepMod, RepFun, ArgTrees);
instrument_application({Module, Function, ArgTrees}) ->
    RepMod = erl_syntax:atom(?REP_MOD),
    RepFun = erl_syntax:atom(list_to_atom("rep_" ++ atom_to_list(Module)
                                          ++ "_"
                                          ++ atom_to_list(Function))),
    erl_syntax:application(RepMod, RepFun, ArgTrees).

instrument_var_application({ModTree, FunTree, ArgTrees}) ->
    RepMod = erl_syntax:atom(?REP_MOD),
    RepFun = erl_syntax:atom(rep_var),
    ArgList = erl_syntax:list(ArgTrees),
    erl_syntax:application(RepMod, RepFun, [ModTree, FunTree, ArgList]).

%% Instrument a receive expression.
%% ----------------------------------------------------------------------
%% receive
%%   Patterns -> Actions
%% end
%%
%% is transformed into
%%
%% ?REP_MOD:rep_receive(Fun),
%% receive
%%   NewPatterns -> NewActions
%% end
%%
%% where Fun = fun(Aux) ->
%%               receive
%%                 NewPatterns -> continue
%%                 [_Fresh -> block]
%%               after 0 ->
%%                 Aux()
%%               end
%%             end
%%
%% The additional _Fresh -> block pattern is only added, if there
%% is no catch-all pattern among the original receive patterns.
%%
%% For each Pattern-Action pair two new pairs are added:
%%   - The first pair is added to handle instrumented messages:
%%       {?INSTR_MSG, Fresh, Pattern} ->
%%           ?REP_MOD:rep_receive_notify(Fresh, Pattern),
%%           Action
%%
%%   - The second pair is added to handle uninstrumented messages:
%%       Pattern ->
%%           ?REP_MOD:rep_receive_notify(Pattern),
%%           Action
%% ----------------------------------------------------------------------
%% receive
%%   Patterns -> Actions
%% after N -> AfterAction
%% end
%%
%% is transformed into
%%
%% case N of
%%   infinity -> ?REP_MOD:rep_receive(Fun),
%%               receive
%%                 NewPatterns -> NewActions
%%               end;
%%   Fresh    -> receive
%%                 NewPatterns -> NewActions
%%               after 0 -> NewAfterAction
%% end
%%
%% That is, if the timeout equals infinity then the expression is
%% equivalent to a normal receive expression as above. Otherwise,
%% any positive timeout is transformed into 0.
%% Pattens and Actions are mapped into NewPatterns and NewActions
%% as described previously for the case of a `receive' expression
%% with no `after' clause. AfterAction is transformed into
%% `?REP_MOD:rep_after_notify(), AfterAction'.
%% ----------------------------------------------------------------------
%% receive
%% after N -> AfterActions
%% end
%%
%% is transformed into
%%
%% case N of
%%   infinity -> ?REP_MOD:rep_receive_block();
%%   Fresh    -> AfterActions
%% end
%% ----------------------------------------------------------------------
instrument_receive(Tree) ->
    %% Get old receive expression's clauses.
    OldClauses = erl_syntax:receive_expr_clauses(Tree),
    case OldClauses of
        [] ->
            Timeout = erl_syntax:receive_expr_timeout(Tree),
            Action = erl_syntax:receive_expr_action(Tree),
            AfterBlock = erl_syntax:block_expr(Action),
            ModTree = erl_syntax:atom(?REP_MOD),
            FunTree = erl_syntax:atom(rep_receive_block),
            Fun = erl_syntax:application(ModTree, FunTree, []),
            transform_receive_timeout(Fun, AfterBlock, Timeout);
        _Other ->
            NewClauses = transform_receive_clauses(OldClauses),
            %% Create fun(X) -> case X of ... end end.
            FunVar = new_variable(),
            CaseClauses = transform_receive_case(NewClauses),
            Case = erl_syntax:case_expr(FunVar, CaseClauses),
            FunClause = erl_syntax:clause([FunVar], [], [Case]),
            FunExpr = erl_syntax:fun_expr([FunClause]),
            %% Create ?REP_MOD:rep_receive(fun(X) -> ...).
            Module = erl_syntax:atom(?REP_MOD),
            Function = erl_syntax:atom(rep_receive),
            RepReceive = erl_syntax:application(Module, Function, [FunExpr]),
            %% Create new receive expression.
            NewReceive = erl_syntax:receive_expr(NewClauses),
            %% Result is begin rep_receive(...), NewReceive end.
            Block = erl_syntax:block_expr([RepReceive, NewReceive]),
            case erl_syntax:receive_expr_timeout(Tree) of
                %% Instrument `receive` without `after` part.
                none -> Block;
                %% Instrument `receive` with `after` part.
                _Any ->
                    Timeout = erl_syntax:receive_expr_timeout(Tree),
                    Action = erl_syntax:receive_expr_action(Tree),
                    RepMod = erl_syntax:atom(?REP_MOD),
                    RepFun = erl_syntax:atom(rep_after_notify),
                    RepApp = erl_syntax:application(RepMod, RepFun, []),
                    NewAction = [RepApp|Action],
                    %% receive NewPatterns -> NewActions after 0 -> NewAfter end
                    ZeroTimeout = erl_syntax:integer(0),
                    AfterExpr = erl_syntax:receive_expr(NewClauses,
                                                        ZeroTimeout, NewAction),
                    transform_receive_timeout(Block, AfterExpr, Timeout)
            end
    end.

transform_receive_case(Clauses) ->
    Fun = fun(Clause, HasCatchall) ->
                  [Pattern] = erl_syntax:clause_patterns(Clause),
                  NewBody = erl_syntax:atom(continue),
                  NewHasCatchall = HasCatchall orelse
                      erl_syntax:type(Pattern) =:= variable,
                  {erl_syntax:clause([Pattern], [], [NewBody]), NewHasCatchall}
          end,
    case lists:mapfoldl(Fun, false, Clauses) of
        {NewClauses, false} ->
            Pattern = new_underscore_variable(),
            Body = erl_syntax:atom(block),
            CatchallClause = erl_syntax:clause([Pattern], [], [Body]),
            NewClauses ++ [CatchallClause];
        {NewClauses, true} -> NewClauses
    end.

transform_receive_clauses(Clauses) ->
    Trans = fun(P) -> [transform_receive_clause_regular(P),
                       transform_receive_clause_special(P)]
            end,
    Fold = fun(Clause, Acc) -> Trans(Clause) ++ Acc end,
    lists:foldr(Fold, [], Clauses).

%% Tranform a clause
%%   Pattern -> Action
%% into
%%   {Fresh, Pattern} -> ?REP_MOD:rep_receive_notify(Fresh, Pattern), Action
transform_receive_clause_regular(Clause) ->
    [OldPattern] = erl_syntax:clause_patterns(Clause),
    OldGuard = erl_syntax:clause_guard(Clause),
    OldBody = erl_syntax:clause_body(Clause),
    InstrAtom = erl_syntax:atom(?INSTR_MSG),
    PidVar = new_variable(),
    NewPattern = [erl_syntax:tuple([InstrAtom, PidVar, OldPattern])],
    Module = erl_syntax:atom(?REP_MOD),
    Function = erl_syntax:atom(rep_receive_notify),
    Arguments = [PidVar, OldPattern],
    Notify = erl_syntax:application(Module, Function, Arguments),
    NewBody = [Notify|OldBody],
    erl_syntax:clause(NewPattern, OldGuard, NewBody).

%% Transform a clause
%%   Pattern -> Action
%% into
%%   Pattern -> ?REP_MOD:rep_receive_notify(Pattern), Action
transform_receive_clause_special(Clause) ->
    [OldPattern] = erl_syntax:clause_patterns(Clause),
    OldGuard = erl_syntax:clause_guard(Clause),
    OldBody = erl_syntax:clause_body(Clause),
    Module = erl_syntax:atom(?REP_MOD),
    Function = erl_syntax:atom(rep_receive_notify),
    Arguments = [OldPattern],
    Notify = erl_syntax:application(Module, Function, Arguments),
    NewBody = [Notify|OldBody],
    erl_syntax:clause([OldPattern], OldGuard, NewBody).

transform_receive_timeout(InfBlock, FrBlock, Timeout) ->
    %% Create 'infinity -> ...' clause.
    InfPattern = erl_syntax:atom(infinity),
    InfClause = erl_syntax:clause([InfPattern], [], [InfBlock]),
    %% Create 'Fresh -> ...' clause.
    FrPattern = new_underscore_variable(),
    FrClause = erl_syntax:clause([FrPattern], [], [FrBlock]),
    %% Create 'case Timeout of ...' expression.
    AfterCaseClauses = [InfClause, FrClause],
    erl_syntax:case_expr(Timeout, AfterCaseClauses).

%% Instrument a Pid ! Msg expression.
%% Pid ! Msg is transformed into ?REP_MOD:rep_send(Pid, Msg).
instrument_send(Tree) ->
    Module = erl_syntax:atom(?REP_MOD),
    Function = erl_syntax:atom(rep_send),
    Dest = erl_syntax:infix_expr_left(Tree),
    Msg = erl_syntax:infix_expr_right(Tree),
    Arguments = [Dest, Msg],
    erl_syntax:application(Module, Function, Arguments).

%%%----------------------------------------------------------------------
%%% Helper functions
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
log_warning_list(_List) -> ok.
                                                %log_list(List, "Warning:").

%% Log a list of error or warning descriptors, as returned by compile:file/2.
log_list(List, Pre) ->
    LogFun = fun(String) -> log:log(String) end,
    _ = [LogFun(io_lib:format("~s:~p: ~s ~s\n",
                              [File, Line, Pre, Mod:format_error(Descr)]))
         || {File, Info} <- List, {Line, Mod, Descr} <- Info],
    ok.
