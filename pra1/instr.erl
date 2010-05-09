-module(instr).
-compile(export_all).

%% TODO: Maybe use compile with `parse_transform` option instead.
load(File) ->
    %% Instrument given source file.
    Transformed = instrument(File),
    case compile:forms(Transformed, [binary]) of
	{ok, Module, Binary} ->
	    code:load_binary(Module, File, Binary),
	    {ok, Module, []};
	{ok, Module, Binary, Warnings} ->
	    code:load_binary(Module, File, Binary),
	    {ok, Module, Warnings};
	{error, Errors, Warnings} ->
	    {error, Errors, Warnings};
	_Any ->
	    {error, [unknown], []}
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
	    io:put_chars(erl_prettypr:format(Abstract)),
	    NewForms = erl_syntax:form_list_elements(Abstract),
	    NewForms;
	{error, Error} ->
	    log:internal("parse_file error: ~p~n", [Error])
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
    _Vars = erl_syntax_lib:variables(Tree),
    %% TODO: Add anonymous variable replacement.
    instrument_subtrees(Tree).

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
			spawn -> instrument_spawn(instrument_subtrees(Tree));
			_Other -> Tree
		    end;
		_Other -> Tree
	    end;
	clause -> instrument_subtrees(Tree);
	infix_expr ->
	    Operator = erl_syntax:infix_expr_operator(Tree),
	    case erl_syntax:operator_name(Operator) of
		'!' -> instrument_send(instrument_subtrees(Tree));
		_Other -> Tree
	    end;
	receive_expr ->
	    instrument_receive(instrument_subtrees(Tree));
	_Other -> instrument_subtrees(Tree)
    end.

%% Instrument a receive expression.
instrument_receive(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_receive),
    %% Get old receive expression's clauses.
    OldClauses = erl_syntax:receive_expr_clauses(Tree),
    %% TODO: Tuplify (sic) old clauses.
    NewClauses = lists:map(fun(Clause) -> transform_receive_clause(Clause) end,
			   OldClauses),
    %% `receive ... after` not supported for now.
    case erl_syntax:receive_expr_timeout(Tree) of
	none -> continue;
	_Any -> log:internal("`receive ... after` expressions not supported.~n")
    end,
    %% Create new receive expression adding the `after 0` part.
    Timeout = erl_syntax:integer(0),
    %% TODO: Replace "Aux" with unique variable name.
    FunVar = erl_syntax:variable("Aux"),
    Action = erl_syntax:application(FunVar, []),
    NewRecv = erl_syntax:receive_expr(NewClauses, Timeout, [Action]),
    %% Create a new fun to be the argument of rep_receive.
    FunClause = erl_syntax:clause([FunVar], [], [NewRecv]),
    FunExpr = erl_syntax:fun_expr([FunClause]),
    %% Call sched:rep_receive.
    erl_syntax:application(Module, Function, [FunExpr]).

%% Tranforms a clause
%%   Msg -> [Actions]
%% to
%%   {SenderPid, Msg} -> {SenderPid, Msg, [Actions]}
%%
%% (temporarily Msg -> {Msg, [Actions]})
transform_receive_clause(Clause) ->
    OldPatterns = erl_syntax:clause_patterns(Clause),
    OldGuard = erl_syntax:clause_guard(Clause),
    OldBody = erl_syntax:clause_body(Clause),
    %% TODO: Patterns left the same for now.
    NewPatterns = OldPatterns,
    NewBody = [erl_syntax:tuple([erl_syntax:block_expr(OldPatterns),
				 erl_syntax:block_expr(OldBody)])],
    erl_syntax:clause(NewPatterns, OldGuard, NewBody).

%% Instrument a Pid ! Msg expression.
%% Pid ! Msg is transformed into rep:send(Pid, Msg).
instrument_send(Tree) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_send),
    Pid = erl_syntax:infix_expr_left(Tree),
    Msg = erl_syntax:infix_expr_right(Tree),
    Arguments = [Pid, Msg],
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

test() ->
    load("/home/alkis/Chess/pra1/test.erl").
