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

-module(concuerror_instr).
-export([delete_and_purge/0, instrument_and_compile/2, load/1,
         check_new_module_name/1, new_module_name/1, old_module_name/1]).

-export_type([macros/0]).

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
         {ets, match_object, 2},
         {ets, match_object, 3},
         {ets, match_delete, 2},
         {ets, new, 2},
         {ets, info, 1},
         {ets, info, 2},
         {ets, foldl, 3}]).

%% Instrumented mod:fun.
-define(INSTR_MOD_FUN, ?INSTR_ERL_MOD_FUN ++ ?INSTR_ETS_FUN).

%% Temp directory we use to save our module renamed code.
-define(INSTR_TEMP_DIR, '_._instr_temp_dir').

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

-type mfb() :: {module(), file:filename(), binary()}.

-type macros() :: [{atom(), term()}].

%%%----------------------------------------------------------------------
%%% Instrumentation utilities
%%%----------------------------------------------------------------------

%% ---------------------------
%% Delete and purge all modules in `?INSTR_TEMP_DIR'.
-spec delete_and_purge() -> 'ok'.
delete_and_purge() ->
    %% Unload and purge modules.
    ModsToPurge = [new_module_name(IM) || {IM} <- ets:tab2list(?NT_INSTR_MOD)],
    Fun = fun (M) -> code:purge(M), code:delete(M), code:purge(M) end,
    lists:foreach(Fun, ModsToPurge),
    %% Delete temp directory (ignore errors).
    TmpDir = get(?INSTR_TEMP_DIR),
    {ok, Files} = file:list_dir(TmpDir),
    DelFile = fun(F) -> file:delete(filename:join(TmpDir, F)) end,
    lists:foreach(DelFile, Files),
    file:del_dir(TmpDir).

%% ---------------------------
%% Rename a module for the instrumentation.
-spec new_module_name(atom() | string()) -> atom().
new_module_name(Module) when is_atom(Module) ->
    new_module_name(atom_to_list(Module));
new_module_name(Module) when is_list(Module) ->
    list_to_atom(?INSTR_PREFIX ++ Module).

-spec check_new_module_name(atom()) -> atom().
check_new_module_name(Module) ->
    case ets:member(?NT_INSTR_MOD, Module) of
        true  -> new_module_name(Module);
        false -> Module
    end.

-spec old_module_name(atom()) -> atom().
old_module_name(NewModule) ->
    case atom_to_list(NewModule) of
        (?INSTR_PREFIX ++ OldModule) -> list_to_atom(OldModule);
        _Module -> NewModule
    end.

%% ---------------------------
%% @spec instrument_and_compile(Files::[file:filename()], concuerror:options())
%%          -> {'ok', [mfb()]} | 'error'
%% @doc: Instrument and compile a list of files.
%%
%% Each file is first validated (i.e. checked whether it will compile
%% successfully). If no errors are encountered, the file gets instrumented and
%% compiled. If these actions are successfull, the function returns `{ok, Bin}',
%% otherwise `error' is returned. No `.beam' files are produced.
-spec instrument_and_compile([file:filename()], concuerror:options()) ->
    {'ok', [mfb()]} | 'error'.
instrument_and_compile(Files, Options) ->
    Includes =
        case lists:keyfind('include', 1, Options) of
            {'include', I} -> I;
            false -> ?DEFAULT_INCLUDE
        end,
    Defines =
        case lists:keyfind('define', 1, Options) of
            {'define', D} -> D;
            false -> ?DEFAULT_DEFINE
        end,
    Verbosity =
        case lists:keyfind('verbose', 1, Options) of
            {'verbose', V} -> V;
            false -> ?DEFAULT_VERBOSITY
        end,
    %% Get the modules we are going to instrument and save
    %% them to `NT_INSTR_MOD' for future reference.
    InstrModules = [{concuerror_util:get_module_name(F)} || F <- Files],
    ets:insert(?NT_INSTR_MOD, InstrModules),
    %% Create a temp dir to save renamed code
    case create_tmp_dir() of
        {ok, DirName} ->
            put(?INSTR_TEMP_DIR, DirName),
            concuerror_log:log(0, "Instrumenting files..\n"),
            InstrOne =
                fun(File) ->
                    instrument_and_compile_one(File, Includes,
                        Defines, DirName, Verbosity)
                end,
            MFBs = concuerror_util:pmap(InstrOne, Files),
            case lists:member('error', MFBs) of
                true  -> error;
                false -> {ok, MFBs}
            end;
        error ->
            error
    end.

%% Instrument and compile a single file.
instrument_and_compile_one(File, Includes, Defines, TmpDir, Verbosity) ->
    %% Compilation of original file without emitting code, just to show
    %% warnings or stop if an error is found, before instrumenting it.
    concuerror_log:log(1, "Validating file ~p...~n", [File]),
    OptIncludes = [{i, I} || I <- Includes],
    OptDefines  = [{d, M, V} || {M, V} <- Defines],
    OptRest =
        case Verbosity >= 1 of
            true  -> [strong_validation, return, verbose];
            false -> [strong_validation, return]
        end,
    PreOptions = OptIncludes ++ OptDefines ++ OptRest,
    %% If `Verbosity' level is 2 or greater then check
    %% for uninstrumented (blackboxed) modules.
    CheckBBModules = Verbosity >= 2,
    put('check_bb_modules', CheckBBModules),
    %% Temp directory.
    put(?INSTR_TEMP_DIR, TmpDir),
    %% Compile module.
    case compile:file(File, PreOptions) of
        {ok, OldModule, Warnings} ->
            %% Log warning messages.
            log_warning_list(Warnings),
            %% Instrument given source file.
            concuerror_log:log(1, "Instrumenting file ~p...~n", [File]),
            case instrument(OldModule, File, Includes, Defines) of
                {ok, NewFile, NewForms} ->
                    %% Compile instrumented code.
                    %% TODO: More compile options?
                    CompOptions = [binary],
                    case compile:forms(NewForms, CompOptions) of
                        {ok, NewModule, Binary} ->
                            {NewModule, NewFile, Binary};
                        error ->
                            concuerror_log:log(0, "Failed to compile "
                                "instrumented file ~p.~n", [NewFile]),
                            error
                    end;
                {error, Error} ->
                    concuerror_log:log(0, "Failed to instrument "
                        "file ~p: ~p~n", [File, Error]),
                    error
            end;
        {error, Errors, Warnings} ->
            log_error_list(Errors),
            log_warning_list(Warnings),
            error
    end.

%% ---------------------------
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
            concuerror_log:log(0, "error~n~p~n", [Error]),
            error
    end.

%% ---------------------------
instrument(Module, File, Includes, Defines) ->
    NewIncludes = [filename:dirname(File) | Includes],
    %% Rename module
    case rename_module(Module, File) of
        {ok, NewFile} ->
            case epp:parse_file(NewFile, NewIncludes, Defines) of
                {ok, OldForms} ->
                    %% Remove `type` and `spec` attributes to avoid
                    %% errors due to record expansion below.
                    %% Also rename our module.
                    StrippedForms = strip_attributes(OldForms, []),
                    ExpRecForms = erl_expand_records:module(StrippedForms, []),
                    %% Convert `erl_parse tree` to `abstract syntax tree`.
                    Tree = erl_recomment:recomment_forms(ExpRecForms, []),
                    MapFun = fun(T) -> instrument_toplevel(T) end,
                    Transformed = erl_syntax_lib:map_subtrees(MapFun, Tree),
                    %% Return an `erl_parse-compatible` representation.
                    Abstract = erl_syntax:revert(Transformed),
                    ?print(Abstract),
                    NewForms = erl_syntax:form_list_elements(Abstract),
                    {ok, NewFile, NewForms};
                {error, _} = Error -> Error
            end;
        {error, _} = Error -> Error
    end.

%% ---------------------------
rename_module(Module, File) ->
    ModuleStr = atom_to_list(Module),
    NewModuleStr = atom_to_list(new_module_name(Module)),
    TmpDir = get(?INSTR_TEMP_DIR),
    NewFile = filename:join(TmpDir, NewModuleStr ++ ".erl"),
    case file:read_file(File) of
        {ok, Binary} ->
            %% Replace the first occurrence of `-module(Module).'
            Pattern = binary:list_to_bin(
                "-module(" ++ ModuleStr ++ ")."),
            Replacement = binary:list_to_bin(
                "-module(" ++ NewModuleStr ++ ")."),
            NewBinary = binary:replace(Binary, Pattern, Replacement),
            %% Write new file in temp directory
            case file:write_file(NewFile, NewBinary) of
                ok    -> {ok, NewFile};
                Error -> Error
            end;
        Error ->
            Error
    end.

%% ---------------------------
%% Create an unique temp directory based on (starting with) Stem.
%% A directory name of the form <Stem><Number> is generated.
%% We use this directory to save our renamed code.
create_tmp_dir() ->
    DirName = temp_name("./.conc_temp_"),
    concuerror_log:log(1, "Create temp dir ~p..\n", [DirName]),
    case file:make_dir(DirName) of
        ok ->
            {ok, DirName};
        {error, eexist} ->
            %% Directory exists, try again
            create_tmp_dir();
        {error, Reason} ->
            concuerror_log:log(0, "error: ~p\n", [Reason]),
            error
    end.

temp_name(Stem) ->
    {A, B, C}   = erlang:now(),
    RandomNum   = A bxor B bxor C,
    RandomName  = Stem ++ integer_to_list(RandomNum),
    RandomName.


%% ---------------------------
%% XXX: Implementation dependent.
strip_attributes([], Acc) ->
    lists:reverse(Acc);
strip_attributes([{attribute, _Line, Name, _Misc}=Head | Rest], Acc) ->
    case lists:member(Name, ?ATTR_STRIP) of
        true -> strip_attributes(Rest, Acc);
        false -> strip_attributes(Rest, [Head|Acc])
    end;
strip_attributes([Head|Rest], Acc) ->
    strip_attributes(Rest, [Head|Acc]).

%% ---------------------------
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
    %% A set of all variables used in the function.
    Used = erl_syntax_lib:variables(Tree),
    %% Insert the used set into `used` dictionary.
    put(?NT_USED, Used),
    instrument_tree(Tree).

%% Instrument a Tree.
instrument_tree(Tree) ->
    MapFun = fun(T) -> instrument_term(T) end,
    erl_syntax_lib:map(MapFun, Tree).

%% Instrument a term.
instrument_term(Tree) ->
    case erl_syntax:type(Tree) of
        application ->
            case get_mfa(Tree) of
                no_instr      -> Tree;
                {rename, Mfa} -> instrument_rename(Mfa);
                {normal, Mfa} -> instrument_application(Mfa);
                {var, Mfa}    -> instrument_var_application(Mfa)
            end;
        infix_expr ->
            Operator = erl_syntax:infix_expr_operator(Tree),
            case erl_syntax:operator_name(Operator) of
                '!' -> instrument_send(Tree);
                _Other -> Tree
            end;
        receive_expr -> instrument_receive(Tree);
        underscore -> new_underscore_variable();
        _Other -> Tree
    end.

%% Return {ModuleAtom, FunctionAtom, [ArgTree]} for a function call that
%% is going to be instrumented or 'no_instr' otherwise.
get_mfa(Tree) ->
    Qualifier = erl_syntax:application_operator(Tree),
    ArgTrees  = erl_syntax:application_arguments(Tree),
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
    %% Add `Module' to the called modules table.
    %% XXX: Well we expect `Module' to be an atom() but it turns
    %% out that `erl_syntax:atom_value/1' doesn't return always an
    %% atom(). In particular, `eunit.hrl' uses the module `.erlang'
    %% which when parsed by concuerror (and transformed with
    %% `erl_syntax:atom_value/1') it returns
    %% [{atom, Line, ''}, {atom, Line, erlang}].
    if
        is_atom(Module) ->
            ets:insert(?NT_CALLED_MOD, {old_module_name(Module)});
        true ->
            true
    end,
    Arity = length(ArgTrees),
    case lists:member({Module, Function, Arity}, ?INSTR_MOD_FUN) of
        true ->
            {normal, {Module, Function, ArgTrees}};
        false ->
            %% Check if module needs to be renamed
            case ets:member(?NT_INSTR_MOD, Module) of
                true  -> {rename, {Module, Function, ArgTrees}};
                false -> no_instr
            end
    end.

instrument_application({erlang, Function, ArgTrees}) ->
    RepMod = erl_syntax:atom(?REP_MOD),
    RepFun = erl_syntax:atom(list_to_atom("rep_" ++ atom_to_list(Function))),
    erl_syntax:application(RepMod, RepFun, ArgTrees);
instrument_application({Module, Function, ArgTrees}) ->
    RepMod = erl_syntax:atom(?REP_MOD),
    RepFun = erl_syntax:atom(list_to_atom("rep_" ++ atom_to_list(Module)
            ++ "_" ++ atom_to_list(Function))),
    erl_syntax:application(RepMod, RepFun, ArgTrees).

instrument_var_application({ModTree, FunTree, ArgTrees}) ->
    RepMod = erl_syntax:atom(?REP_MOD),
    RepFun = erl_syntax:atom(rep_var),
    ArgList = erl_syntax:list(ArgTrees),
    CheckBBModules = erl_syntax:abstract(get('check_bb_modules')),
    erl_syntax:application(RepMod, RepFun,
        [ModTree, FunTree, ArgList, CheckBBModules]).

instrument_rename({Module, Function, ArgTrees}) ->
    RepMod = erl_syntax:atom(new_module_name(Module)),
    RepFun = erl_syntax:atom(Function),
    erl_syntax:application(RepMod, RepFun, ArgTrees).

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
            Timeout = erl_syntax:receive_expr_timeout(Tree),
            HasNoTimeout = Timeout =:= none,
            HasTimeoutExpr =
                case HasNoTimeout of
                    true -> erl_syntax:atom(infinity);
                    false -> Timeout
                end,
            RepReceive =
                erl_syntax:application(Module, Function,
                                       [FunExpr, HasTimeoutExpr]),
            %% Create new receive expression.
            NewReceive = erl_syntax:receive_expr(NewClauses),
            %% Result is begin rep_receive(...), NewReceive end.
            Block = erl_syntax:block_expr([RepReceive, NewReceive]),
            case HasNoTimeout of
                %% Instrument `receive` without `after` part.
                true -> Block;
                %% Instrument `receive` with `after` part.
                false ->
                    Action = erl_syntax:receive_expr_action(Tree),
                    RepMod = erl_syntax:atom(?REP_MOD),
                    RepFun = erl_syntax:atom(rep_after_notify),
                    RepApp = erl_syntax:application(RepMod, RepFun, []),
                    NewAction = [RepApp|Action],
                    %% receive NewPatterns -> NewActions after 0 -> NewAfter end
                    ZeroTimeout = erl_syntax:integer(0),
                    AfterExpr = erl_syntax:receive_expr(NewClauses,
                                                        ZeroTimeout, NewAction),
                    AfterBlock = erl_syntax:block_expr([RepReceive,AfterExpr]),
                    transform_receive_timeout(Block, AfterBlock, Timeout)
            end
    end.

transform_receive_case(Clauses) ->
    Fun =
        fun(Clause) ->
            [Pattern] = erl_syntax:clause_patterns(Clause),
            NewBody = erl_syntax:atom(continue),
            erl_syntax:clause([Pattern], [], [NewBody])
        end,
    NewClauses = lists:map(Fun, Clauses),
    Pattern = new_underscore_variable(),
    Body = erl_syntax:atom(block),
    CatchallClause = erl_syntax:clause([Pattern], [], [Body]),
    NewClauses ++ [CatchallClause].

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
    CV = new_variable(),
    NewPattern = [erl_syntax:tuple([InstrAtom, PidVar, CV, OldPattern])],
    Module = erl_syntax:atom(?REP_MOD),
    Function = erl_syntax:atom(rep_receive_notify),
    Arguments = [PidVar, CV, OldPattern],
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
    Dest = erl_syntax:infix_expr_left(Tree),
    Msg = erl_syntax:infix_expr_right(Tree),
    instrument_application({erlang, send, [Dest, Msg]}).

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

new_variable() ->
    Used = get(?NT_USED),
    Fresh = erl_syntax_lib:new_variable_name(Used),
    put(?NT_USED, sets:add_element(Fresh, Used)),
    erl_syntax:variable(Fresh).

new_underscore_variable() ->
    Used = get(?NT_USED),
    new_underscore_variable(Used).

new_underscore_variable(Used) ->
    Fresh1 = erl_syntax_lib:new_variable_name(Used),
    String = "_" ++ atom_to_list(Fresh1),
    Fresh2 = list_to_atom(String),
    case is_fresh(Fresh2, Used) of
        true ->
            put(?NT_USED, sets:add_element(Fresh2, Used)),
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
    log_list(List, "", 0).

%% Log a list of warnings, as returned by compile:file/2.
log_warning_list(List) ->
    log_list(List, "Warning:", 1).

%% Log a list of error or warning descriptors, as returned by compile:file/2.
log_list(List, Pre, Verbosity) ->
    Strings = [io_lib:format("~s:~p: ~s ~s\n",
                    [File, Line, Pre, Mod:format_error(Descr)])
              || {File, Info} <- List, {Line, Mod, Descr} <- Info],
    concuerror_log:log(Verbosity, lists:flatten(Strings)),
    ok.
