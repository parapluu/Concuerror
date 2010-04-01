-module(instrument).
-export([c/1, instrument/1, instrument_module/1, open/1, write/2, view/1]).

-import(erl_syntax,
        [abstract/1, application/2, application_arguments/1,
         application_operator/1, arity_qualifier/2,
         arity_qualifier_argument/1, arity_qualifier_body/1, atom/1,
         atom_value/1, block_expr/1, case_expr/2, clause/3,
         clause_body/1, clause_guard/1, clause_patterns/1,
         form_list_elements/1, fun_expr/1, function_arity/1,
         function_name/1, get_ann/1, implicit_fun/1, implicit_fun_name/1,
         infix_expr_left/1, infix_expr_operator/1, infix_expr_right/1,
         integer/1, integer_value/1, list/1, match_expr/2,
         match_expr_pattern/1, module_qualifier/2,
         module_qualifier_argument/1, module_qualifier_body/1,
         operator_name/1, receive_expr/3, receive_expr_action/1,
         receive_expr_clauses/1, receive_expr_timeout/1, revert/1,
         tuple/1, type/1, variable/1, underscore/0,
         variable_name/1]).

-import(erl_syntax_lib,
	[map_subtrees/2, new_variable_name/1,
         strip_comments/1, variables/1]).

%%
%% Some user functions.
%% 

%% Parse a file.
open(FileName) ->
    open(FileName, scheduler).

open(FileName, Scheduler) ->
    {ok, Forms} = epp:parse_file(FileName, ["."],
                                 [{'SCHEDULER', Scheduler}]),
    Comments = erl_comment_scan:file(FileName),
    erl_recomment:recomment_forms(Forms, Comments).

%% Print the Erlang program that a syntax tree represents.
print(Tree) ->
    io:put_chars(erl_prettypr:format(Tree)).

print(Tree, FileName) ->
    file:write_file(FileName, erl_prettypr:format(Tree)).

%% Compile a syntax tree.
compile(Tree) ->
    compile:forms(form_list_elements(revert(strip_comments(Tree)))).

%% Turn a module atom into an instrumented syntax tree.
instrument_module(Atom) ->
    instrument_module(Atom, scheduler).

instrument_module(Atom, Scheduler) ->
    instrument_module(Atom, Scheduler, all).

instrument_module(FileName, Scheduler, Functions) when is_list(FileName) ->
    Term = open(FileName, Scheduler),
    {FileName, instrument(Term, Scheduler, Functions, [])};
instrument_module(Atom, Scheduler, Functions) ->
    FileName = atom_to_list(Atom) ++ ".erl",
    Term = open(FileName, Scheduler),
    {FileName, instrument(Term, Scheduler, Functions, [])}.

%% Compile and load a module.
c(Atom) ->
    c(Atom, scheduler).

c(Atom, Scheduler) ->
    c(Atom, Scheduler, all).

%% c([], _Scheduler, _Functions) ->
%%     ok;
%% c([Atom | Rest], Scheduler, Functions) ->
%%     c(Atom, Scheduler, Functions),
%%     c(Rest, Scheduler, Functions);
c(Atom, Scheduler, Functions) ->
    {FileName, Instrumented} = instrument_module(Atom, Scheduler, Functions),
    {ok, Module, Binary} = compile(Instrumented),
    code:load_binary(Module, FileName, Binary),
    {Scheduler, Module}.

%% Print the instrumented version of a module.
view(Atom) ->
    view(Atom, scheduler).

view(Atom, Scheduler) ->
    view(Atom, Scheduler, all).

view(Atom, Scheduler, Functions) ->
    {_, Instrumented} = instrument_module(Atom, Scheduler, Functions),
    print(Instrumented).

write(FileName, Atom) ->
    write(FileName, Atom, scheduler).

write(FileName, Atom, Scheduler) ->
    write(FileName, Atom, Scheduler, all).

write(FileName, Atom, Scheduler, Functions) ->
    {_, Instrumented} = instrument_module(Atom, Scheduler, Functions),
    print(Instrumented, FileName).

%%
%% The instrumenter itself.
%% 

%% Instrument a syntax tree.
%% We store two values in the process dictionary:
%%   * get(scheduler) is the name of the scheduler module.
%%   * get(used) is the set of variables that appear in the tree.
instrument(Term) ->
    instrument(Term, scheduler).

instrument(Term, Scheduler) ->
    instrument(Term, Scheduler, all).

instrument(Term, Scheduler, Functions) ->
    instrument(Term, Scheduler, Functions, []).

instrument(Term, Scheduler, Functions, Name) ->
    put(skip, []),
    put(functions, Functions),
    put(scheduler, Scheduler),
    put(used, variables(Term)),
    Result = map_subtrees(fun(T) -> instrument_toplevel(T, Name) end, Term),
    report_skipped(lists:reverse(get(skip))),
    Result.

report_skipped([]) ->
    ok;
report_skipped([X|Xs]) ->
    io:format("Skipped "),
    format_function(X),
    report_rest(Xs).
report_rest([]) ->
    io:format(".~n");
report_rest([X]) ->
    io:format(" and "),
    format_function(X),
    io:format(".~n");
report_rest([X|Xs]) ->
    io:format(", "),
    format_function(X),
    report_rest(Xs).
format_function(Term) ->
    io:format("~p/~p", [atom_value(function_name(Term)), function_arity(Term)]).

%% Instrument a top-level form.
instrument_toplevel(Term, Name) ->
    case type(Term) == function of
        true ->
            case name_is_member(Term, get(functions)) of
                true ->
                    instrument_term(Term,
                                    [atom_value(function_name(Term))|Name]);
                false ->
                    put(skip, [Term|get(skip)]),
                    Term
            end;
        false ->
            Term
    end.

name_is_member(_, all) ->
    true;
name_is_member(Term, Xs) ->
    lists:member(atom_value(function_name(Term)), Xs).

%% Instrument all the subterms of a term.
instrument_subterms(Term, Name) ->
    map_subtrees(fun(T) -> instrument_term(T, Name) end, Term).

%% Find a fresh variable name.
new_var() ->
    Used = get(used),
    Var = new_variable_name(Used),
    put(used, sets:add_element(Var, Used)),
    variable(Var).

%% Return the name of the scheduler module.
scheduler() ->
    Result = get(scheduler),
    case code:is_loaded(Result) of
        false ->
            exit({module_is_not_loaded, Result});
        _ ->
            Result
    end.

%% Produce a syntax tree that represents ?scheduler:Fun(Args).
%% Fun should be an atom, and Args a list of syntax trees.
scheduler(Fun, Args) ->
    call(scheduler(), Fun, Args).

%% Produce a syntax tree that represents Module:Fun(Args).
%% Module and Fun should be atoms, and Args a list of syntax trees.
call(Module, Name, Args) ->
    application(
      module_qualifier(atom(Module),
                       atom(Name)),
      Args).

%% The list of syntax types that need nothing special from the
%% instrumenter.
boring_types() ->
    [arity_qualifier, atom, attribute, binary, binary_field,
     block_expr, case_expr, catch_expr, char, class_qualifier,
     clause, comment, cond_expr, conjunction, disjunction,
     eof_marker, error_marker, float, form_list, fun_expr,
     function, generator, if_expr, integer, list, list_comp,
     macro, module_qualifier, nil, operator,
     parentheses, prefix_expr, query_expr, record_access,
     record_expr, record_field, record_index_expr, rule,
     size_qualifier, string, text, try_expr, tuple,
     underscore, variable, warning_marker].

%% Instrument a term.
instrument_term(Term, Name) ->
    Type = type(Term),
    Boring = lists:member(Type, boring_types()),
    OpName = (catch operator_name(infix_expr_operator(Term))),
    MatchType = (catch type(match_expr_pattern(Term))),
    MatchVar = (catch variable_name(match_expr_pattern(Term))),
    if
        Type == infix_expr, OpName == '!' ->
            instrument_send(instrument_subterms(Term, Name));
        Type == infix_expr ->
            instrument_subterms(Term, Name);
        Type == receive_expr ->
            instrument_receive(instrument_subterms(Term, Name));
        Type == application ->
            instrument_call(instrument_subterms(Term, Name), Name);
        Type == implicit_fun ->
            instrument_implicit_fun(Term, Name);
        Type == match_expr, MatchType == variable ->
            instrument_subterms(Term, [MatchVar|Name]);
        Type == match_expr ->
            instrument_subterms(Term, Name);
        Boring ->
            instrument_subterms(Term, Name);
        true ->
            exit({unknown_type, Type, revert(Term)})
    end.

%% Instrument a send.
%% p ! x -> ?SCHEDULER:send(p, x).
instrument_send(Term) ->
    Left = infix_expr_left(Term),
    Right = infix_expr_right(Term),
    scheduler(send, [Left, Right]).

%% Instrument a receive.
%% This is the most difficult transformation.
%%   receive (P -> C)* end
%% ->
%%   {X, V*} = ?SCHEDULER:receiving(fun(Retry) ->
%%     receive
%%       (P -> X = C, {X, V*})*
%%     after ?SCHEDULER:'after'() ->
%%       Retry()
%%     end
%%   end,
%%   {X, V*} = {X, V*} % to prevent warnings about unused variables
%%   X
%% where V* is the set of all variables bound in the receive block.
%%
%% If no variables are bound, we use the simpler transformation
%%   receive ... end
%% ->
%%   ?SCHEDULER:receiving(fun(Retry) ->
%%     receive ...
%%     after ?SCHEDULER:'after'() ->
%%       Retry()
%%     end
%%   end).
%%
%%   receive (P -> C)* after 0 -> E end
%% ->
%%   {X, V*} = ?SCHEDULER:receivingAfter0(fun(Retry) ->
%%     receive
%%       (P -> X = C, {X, V*})*
%%     after 0 -> Retry()
%%     end
%%   end,
%%   fun() -> X = E, {X, V*} end),
%%   {X, V*} = {X, V*},
%%   X.
instrument_receive(Term) ->
    Retry = new_var(),
    Result = new_var(),
    Bound = [ variable(X) || X <- bound_vars_in_receive(Term) ],
    Tuple = tuple([Result|Bound]),

    %% Add the variable capture stuff to a clause body.
    TransformBody =
        fun(Body) ->
                case Bound of
                    [] ->
                        Body;
                    _ ->
                        [match_expr(Result,
                                    block_expr(Body)),
                         Tuple]
                end
        end,

    TransformClause =
        fun(Clause) ->
                %% We want to change Pat -> Expr*
                %% into (X = Pat) -> scheduler:consumed(X), Expr*
                
                %% Only one pattern seems to be allowed per receive-clause...
                [CP] = clause_patterns(Clause),
                Var = new_var(),
                NewCP = match_expr(Var,CP),
                NewBody = [scheduler(consumed, [Var]) |
                           TransformBody(clause_body(Clause))], 
                clause([NewCP],
                       clause_guard(Clause),
                       NewBody)
        end,

    Clauses = lists:map(TransformClause, receive_expr_clauses(Term)),

    case timeout(Term) of
        infinity ->
            Timeout = scheduler('after', []),
            Call = fun(Fun) -> scheduler(receiving, [Fun]) end;
        0 ->
            Timeout = abstract(0),
            ActionFun = fun_expr([clause([], none,
                                        TransformBody(receive_expr_action(Term)))]),
            Call = fun(Fun) -> scheduler(receivingAfter0, [Fun, ActionFun]) end;
        T ->
            exit({unsupported_timeout, T}),
            %% To make the compiler happy...
            Timeout = exit(oops),
            Call = exit(oops)
    end,

    %% receive ... after ?SCHEDULER:after() -> Retry() end.
    FunctionBody = receive_expr(Clauses, Timeout, [application(Retry, [])]),

    %% fun(Retry) -> ... end.
    Function =
        fun_expr([clause
                  ([Retry],
                   none,
                   [FunctionBody])]),

    case Bound of
        [] ->
            Call(Function);
        _ ->
            block_expr
              ([match_expr(Tuple, Call(Function)),
                match_expr(Tuple, Tuple),
                Result])
    end.

%% Find the timeout of a receive. Returns either an integer, infinity,
%% or, as a last resort, a syntax tree.
timeout(Term) ->
    Timeout = receive_expr_timeout(Term),
    Infinity = Timeout == none orelse
        (type(Timeout) == atom andalso
         atom_value(Timeout) == infinity),
    Integer = Timeout /= none andalso type(Timeout) == integer,
    if
        Infinity -> infinity;
        Integer -> integer_value(Timeout);
        true -> Timeout
    end.

%% Find the variables that are assigned in a term, which must have
%% been annotated with erl_syntax_lib:annotate_bindings beforehand.
bound_vars(Term) ->
    case lists:keysearch(bound, 1, get_ann(Term)) of
        {value, {bound, X}} -> X;
        false -> []
    end.

%% Find the variables that are bound in all clauses of a receive,
%% including the 'after' clause.
bound_vars_in_receive(Term) ->
    Annotated = erl_syntax_lib:annotate_bindings(Term, []),
    Terms = erl_syntax:receive_expr_clauses(Annotated) ++
        case timeout(Term) of
            infinity ->
                [];
            _ ->
                [erl_syntax_lib:annotate_bindings(
                   erl_syntax:block_expr(erl_syntax:receive_expr_action(Term)),
                   [])]
        end,
    case Terms of
        [] -> [];
        _ ->
            ordsets:intersection([bound_vars(V) || V <- Terms])
    end.

%% Instrument a call. The main aim is to replace calls to Erlang BIFs,
%% e.g. spawn, by calls to scheduler functions, e.g. scheduler:spawn.
instrument_call(Term, Name) ->
    Function = application_operator(Term),
    Arguments = application_arguments(Term),
    %% Hack: Ignore the function's arity if it's a literal.
    {Module, Atom, _} = function_parts(Function),
    %% Hack: handle the case where Module is {}.
    case {catch type(Module), type(Atom)} of
        {atom, atom} ->
            instrument_direct_call(Module, Atom, Arguments, Name);
        {{'EXIT', _}, atom} ->
            instrument_direct_call(Module, Atom, Arguments, Name);
        _ ->
            instrument_indirect_call(
              case Module of
                  {} -> tuple([]);
                  _ -> Module
              end, Atom, Arguments, Name)
    end.

%% Instrument a call where the Module and Atom are known at
%% compile-time.
instrument_direct_call(Module, Atom, Arguments, Name) ->
    Arity = length(Arguments),
    {IModule, IAtom, NeedName, NeedYield} =
        look_up_function(scheduler(),
                         module_value(Module), atom_value(Atom), Arity),
    Inner = application(qualified_function(IModule, atom(IAtom)),
                        case NeedName of
                            true -> [atom(choose_name(Name))|Arguments];
                            false -> Arguments
                        end),
    case NeedYield of
        true ->
	    scheduler(side_effect,[atom(IModule),atom(IAtom),list(Arguments)]);
        false ->
            Inner
    end.

module_value({}) ->
    {};
module_value(Module) ->
    atom_value(Module).

qualified_function({}, Atom) ->
    Atom;
qualified_function(Module, Atom) ->
    module_qualifier(atom(Module), Atom).

%% Instrument a call where the Module and Atom are only known at
%% runtime.
%% The transformation is
%%   M:E(Arg*)
%% =>
%%   {Module, Atom, NeedName, NeedYield} =
%%       instrument:look_up_function(scheduler, M, E, N),
%%   case NeedYield of
%%       true -> ?SCHEDULER:yield();
%%       false -> ok
%%   end,
%%   case {Module, NeedName} of
%%       {{}, true} -> Atom(Name, Arg*);
%%       {{}, false} -> Atom(Arg*);
%%       {_, true} -> Module:Atom(Name, Arg*);
%%       {_, false} -> Module:Atom(Arg*)
%%   end.
instrument_indirect_call(Module, Atom, Arguments, Name) ->
    ModVar = new_var(),
    AtomVar = new_var(),
    NeedNameVar = new_var(),
    NeedYieldVar = new_var(),
    NameTerm = atom(choose_name(Name)),
    Arity = length(Arguments),
    block_expr(
      [match_expr(tuple([ModVar, AtomVar, NeedNameVar, NeedYieldVar]),
                  application(module_qualifier(atom(?MODULE),
                                               atom(look_up_function)),
                              [atom(scheduler()),
                               Module,
                               Atom,
                               integer(Arity)])),
       case_expr(NeedYieldVar,
                 [clause([atom(true)], none,
                         [scheduler(yield, [])]),
                  clause([atom(false)], none,
                         [atom(ok)])]),
       case_expr(tuple([ModVar, NeedNameVar]),
                 [clause([tuple([tuple([]), atom(true)])], none,
                         [application(AtomVar, [NameTerm|Arguments])]),
                  clause([tuple([tuple([]), atom(false)])], none,
                         [application(AtomVar, Arguments)]),
                  clause([tuple([underscore(), atom(true)])], none,
                         [application(module_qualifier(ModVar, AtomVar),
                                      [NameTerm|Arguments])]),
                  clause([tuple([underscore(), atom(false)])], none,
                         [application(module_qualifier(ModVar, AtomVar),
                                      Arguments)])])]).

%% Instrument something of the form "fun Module:Atom/N".
%% If the instrumented version needs a Name parameter,
%% produces fun(Args) -> scheduler:Atom(Name, Args) end.
instrument_implicit_fun(Term, Name) ->
    {Module, Atom, Arity} = function_parts(implicit_fun_name(Term)),
    {IModule, IAtom, NeedName, NeedYield} =
        look_up_function(scheduler(), module_value(Module), atom_value(Atom),
                         integer_value(Arity)),
    case {NeedName, NeedYield} of
        {false, false} ->
            Fun = qualified_function(IModule,
                                     arity_qualifier(atom(IAtom), Arity)),
            implicit_fun(Fun);
        _ ->
            Vars = [ new_var() || _ <- seq(1, integer_value(Arity)) ],
            Fun = qualified_function(IModule, atom(IAtom)),
            Args = case NeedName of
                       true -> [atom(choose_name(Name)) | Vars];
                       false -> Vars
                   end,
            Body = [application(Fun, Args)],
            fun_expr([clause(Vars, none,
                             case NeedYield of
                                 true -> [scheduler(yield, []) | Body];
                                 false -> Body
                             end)])
    end.

seq(From, To) when From > To ->
    [];
seq(From, To) ->
    lists:seq(From, To).

%% Split a function into module + expression + arity.
%% The returned module can be {} (meaning no module qualifier), and
%% the returned arity can be unknown.
function_parts(Fun) ->
    function_parts_from({}, Fun, unknown).
function_parts_from(Module, Fun, Arity) ->
    case type(Fun) of
        module_qualifier ->
            function_parts_from(module_qualifier_argument(Fun),
                                module_qualifier_body(Fun),
                                Arity);
        arity_qualifier ->
            function_parts_from(Module,
                                arity_qualifier_body(Fun),
                                arity_qualifier_argument(Fun));
        _ ->
            {Module, Fun, Arity}
    end.

%% Look up a function in an instrumentation list.
%% The module should be an atom or {}, meaning no module qualifier.
%% The function should be an atom or an Erlang fun.
%% 
%% The function returns a tuple {Module, Fun, NeedName, NeedYield},
%% where NeedName indicates whether the instrumented function expects
%% to be passed an extra Name parameter and NeedYield indicates whether
%% you should call ?SCHEDULER:yield() before the instrumented function.
look_up_function(Sched, {}, Fun, Arity) when is_atom(Fun) ->
    case erl_internal:bif(Fun, Arity) of
        true ->
            look_up_function_2(Sched, Sched:instrumented(), erlang, Fun);
        false ->
            look_up_function_2(Sched, Sched:instrumented(), {}, Fun)
    end;
look_up_function(Sched, Module, Fun, _Arity) ->
    look_up_function_2(Sched, Sched:instrumented(), Module, Fun).
look_up_function_2(_, [], Module, Fun) ->
    {Module, Fun, false, false};
look_up_function_2(Sched, [{Module, Fun, Flags}|_], Module, Fun) ->
    case {lists:member(dont_capture, Flags),
          lists:keysearch(replace_with, 1, Flags)} of
        {true, false} -> {NewModule, NewFun} = {Module, Fun};
        {false, false} -> {NewModule, NewFun} = {Sched, Fun};
        {false, {value, {replace_with, NewModule, NewFun}}} -> ok
    end,
    {NewModule, NewFun, lists:member(name, Flags), lists:member(yield, Flags)};
look_up_function_2(Sched, [_|Xs], Module, Fun) ->
    look_up_function_2(Sched, Xs, Module, Fun).

choose_name([]) ->
    "";
choose_name([X]) ->
    atom_to_list(X);
choose_name([X|Xs]) ->
    choose_name(Xs) ++ "." ++ atom_to_list(X).
