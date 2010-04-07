%%%----------------------------------------------------------------------
%%% File    : funs.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : 
%%%
%%% Created : 31 Mar 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

-module(funs).
-export([stringList/1, tupleList/1]).

-spec tupleList(string()) -> [{atom(), arity()}].
                       
tupleList(Module) ->
    {ok, Form} = epp_dodger:quick_parse_file(Module),
    getFuns(Form, []).

-spec stringList(string()) -> [string()].

stringList(Module) ->
    Funs = tupleList(Module),
    stringList(Funs, []).

stringList([], Strings) ->
    Strings;
stringList([{Name, Arity} | Rest], Strings) ->
    stringList(Rest, [lists:concat([Name, "/", Arity]) | Strings]).

getFuns([], Funs) ->
    Funs;
getFuns([Node | Rest] = L, Funs) ->
    case erl_syntax:type(Node) of
	attribute ->
	    Name = erl_syntax:atom_name(erl_syntax:attribute_name(Node)),
	    case Name of
		"export" ->
		    [List] = erl_syntax:attribute_arguments(Node),
		    Args = erl_syntax:list_elements(List),
		    NewFuns = getExports(Args, []),
		    getFuns(Rest, NewFuns ++ Funs);
		_Other -> getFuns(Rest, Funs)
	    end;	
	function ->
	    case Funs of
		[] -> getAllFuns(L, []);
		_Other -> Funs
	    end;
	_Other -> getFuns(Rest, Funs)
    end.

getExports([], Exp) ->
    Exp;
getExports([Fun|Rest], Exp) ->
    Name = erl_syntax:atom_name(erl_syntax:arity_qualifier_body(Fun)),
    Arity = erl_syntax:integer_value(erl_syntax:arity_qualifier_argument(Fun)),
    getExports(Rest, [{list_to_atom(Name), Arity}|Exp]).

getAllFuns([], Funs) ->
    Funs;
getAllFuns([Node|Rest], Funs) ->
    case erl_syntax:type(Node) of
	function ->
	    Name = erl_syntax:atom_name(erl_syntax:function_name(Node)),
	    Arity = erl_syntax:function_arity(Node),
	    getAllFuns(Rest, [{list_to_atom(Name), Arity}|Funs]);
	_Other -> getAllFuns(Rest, Funs)
    end.
