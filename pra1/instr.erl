-module(instr).
-compile(export_all).

instrument(File) ->
    %% TODO: For now using an empty include path. In the future we have to
    %%       provide a means for an externally defined include path (like the
    %%       erlc -I flag).
    case epp:parse_file(File, [], []) of
	{ok, Forms} ->
	    Tree = erl_recomment:recomment_forms(Forms, []),
	    MapFun = fun(T) -> instrument_toplevel(T) end,
	    Transformed = erl_syntax_lib:map_subtrees(MapFun, Tree),
	    io:put_chars(erl_prettypr:format(erl_syntax:revert(Transformed)));
	{error, Error} ->
	    io:format("parse_file error: ~p~n", [Error])
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
%% 
instrument_function(Tree) ->
    Vars = erl_syntax_lib:variables(Tree),
    instrument_subtrees(Tree, Vars).

instrument_subtrees(Tree, Used) ->
    MapFun = fun(T) -> instrument_term(T, Used) end,
    erl_syntax_lib:map_subtrees(MapFun, Tree).

%% Instrument a term.
instrument_term(Tree, Used) ->
    case erl_syntax:type(Tree) of
	clause -> instrument_subtrees(Tree, Used);
	infix_expr ->
	    Operator = erl_syntax:infix_expr_operator(Tree),
	    case erl_syntax:operator_name(Operator) of
		'!' -> instrument_send(instrument_subtrees(Tree, Used), Used);
		_Other -> Tree
	    end;
	_Other -> Tree
    end.

%% Instrument a Pid ! Msg expression, given that Pid and Msg are already
%% instrumented.
%% Pid ! Msg is transformed into rep:send(Pid, Msg).
instrument_send(Tree, _Used) ->
    Module = erl_syntax:atom(sched),
    Function = erl_syntax:atom(rep_send),
    Pid = erl_syntax:infix_expr_left(Tree),
    Msg = erl_syntax:infix_expr_right(Tree),
    Arguments = [Pid, Msg],
    erl_syntax:application(Module, Function, Arguments).

test() ->
    instrument("/home/alkis/Chess/pra1/test.erl").
