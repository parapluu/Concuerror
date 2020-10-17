%%% @private
-module(concuerror_instrumenter).

-export([instrument/3]).

-define(inspect, concuerror_inspect).

-define(flag(A), (1 bsl A)).

-define(input, ?flag(1)).
-define(output, ?flag(2)).

-define(ACTIVE_FLAGS, [?input, ?output]).

%% -define(DEBUG_FLAGS, lists:foldl(fun erlang:'bor'/2, 0, ?ACTIVE_FLAGS)).
-include("concuerror.hrl").

-spec instrument(module(), erl_syntax:forms(), concuerror_loader:instrumented())
                -> {erl_syntax:forms(), [iodata()]}.

instrument(?inspect, AbstractCode, _Instrumented) ->
  %% The inspect module should never be instrumented.
  {AbstractCode, []};
instrument(Module, AbstractCode, Instrumented) ->
  ?if_debug(Stripper = fun(Node) -> erl_syntax:set_ann(Node, []) end),
  ?debug_flag(?input, "~s~n",
              [[erl_prettypr:format(erl_syntax_lib:map(Stripper, A))
                || A <- AbstractCode]]),
  true = ets:insert(Instrumented, {{current}, Module}),
  Acc =
    #{ file => ""
     , instrumented => Instrumented
     , warnings => []
     },
  {Is, #{warnings := Warnings}} = fold(AbstractCode, Acc, []),
  true = ets:delete(Instrumented, {current}),
  ?debug_flag(?output, "~s~n",
              [[erl_prettypr:format(erl_syntax_lib:map(Stripper, I))
                || I <- Is]]),
  {Is, warn_to_string(Module, lists:usort(Warnings))}.

%% Replace with form_list please.
fold([], Arg, Acc) ->
  {erl_syntax:revert_forms(lists:reverse(Acc)), Arg};
fold([H|T], Arg, Acc) ->
  ArgIn = Arg#{var => erl_syntax_lib:variables(H)},
  {R, NewArg} = erl_syntax_lib:mapfold(fun mapfold/2, ArgIn, H),
  fold(T, NewArg, [R|Acc]).

mapfold(Node, Acc) ->
  #{ file := File
   , instrumented := Instrumented
   , warnings := Warnings
   , var := Var
   } = Acc,
  Type = erl_syntax:type(Node),
  NewNodeAndMaybeWarn =
    case Type of
      application ->
        Args = erl_syntax:application_arguments(Node),
        LArgs = erl_syntax:list(Args),
        Op = erl_syntax:application_operator(Node),
        OpType = erl_syntax:type(Op),
        case OpType of
          module_qualifier ->
            Module = erl_syntax:module_qualifier_argument(Op),
            Name = erl_syntax:module_qualifier_body(Op),
            case is_safe(Module, Name, length(Args), Instrumented) of
              has_load_nif -> {newwarn, Node, has_load_nif};
              true -> Node;
              false ->
                inspect(call, [Module, Name, LArgs], Node, Acc)
            end;
          atom -> Node;
          _ ->
            inspect(apply, [Op, LArgs], Node, Acc)
        end;
      infix_expr ->
        Op = erl_syntax:infix_expr_operator(Node),
        COp = erl_syntax:operator_name(Op),
        case COp of
          '!' ->
            Left = erl_syntax:infix_expr_left(Node),
            Right = erl_syntax:infix_expr_right(Node),
            Args = erl_syntax:list([Left, Right]),
            inspect(call, [abstr(erlang), abstr('!'), Args], Node, Acc);
          _ -> Node
        end;
      receive_expr ->
        Fun = receive_matching_fun(Node),
        Timeout = erl_syntax:receive_expr_timeout(Node),
        TArg =
          case Timeout =:= none of
            true -> abstr(infinity);
            false -> Timeout
          end,
        Call = inspect('receive', [Fun, TArg], Node, Acc),
        case Timeout =:= none of
          true ->
            %% Leave receives without after clauses unaffected, so
            %% that the compiler can expose matched patterns to the
            %% rest of the program
            erl_syntax:block_expr([Call, Node]);
          false ->
            %% Otherwise, replace original timeout with a fresh
            %% variable to make the after clause immediately reachable
            %% when needed.
            Clauses = erl_syntax:receive_expr_clauses(Node),
            Action = erl_syntax:receive_expr_action(Node),
            TimeoutVar =
              erl_syntax:variable(erl_syntax_lib:new_variable_name(Var)),
            Match = erl_syntax:match_expr(TimeoutVar, Call),
            RecNode = erl_syntax:receive_expr(Clauses, TimeoutVar, Action),
            Block = erl_syntax:block_expr([Match, RecNode]),
            {newvar, Block, TimeoutVar}
        end;
      _ -> Node
    end,
  {NewNode, NewVar, NewWarnings} =
    case NewNodeAndMaybeWarn of
      {newwarn, NN, W} -> {NN, Var, [W|Warnings]};
      {newvar, NN, V} -> {NN, sets:add_element(V, Var), Warnings};
      _ -> {NewNodeAndMaybeWarn, Var, Warnings}
    end,
  NewFile =
    case Type of
      attribute ->
        case erl_syntax_lib:analyze_attribute(Node) of
          {file, {NF, _}} -> NF;
          _ -> File
        end;
      _ -> File
    end,
  NewAcc =
    Acc
    #{ file => NewFile
     , warnings => NewWarnings
     , var => NewVar
     },
  {NewNode, NewAcc}.


inspect(Tag, Args, Node, Acc) ->
  #{ file := File} = Acc,
  Pos = erl_syntax:get_pos(Node),
  PosInfo = [Pos, {file, File}],
  CTag = abstr(Tag),
  CArgs = erl_syntax:list(Args),
  App =
    erl_syntax:application( abstr(?inspect)
                          , abstr(inspect)
                          , [ CTag
                            , CArgs
                            , abstr(PosInfo)]),
  erl_syntax:copy_attrs(Node, App).

receive_matching_fun(Node) ->
  Clauses = erl_syntax:receive_expr_clauses(Node),
  NewClauses = extract_patterns(Clauses),
  %% We need a case in a fun to avoid shadowing
  %% i.e. if the receive uses a bound var in a clause and we insert it
  %%      bare as a clause into a new fun it will shadow the original
  %%      and change the code's meaning
  Var = erl_syntax:variable('__Concuerror42'),
  NewCase = erl_syntax:case_expr(Var, NewClauses),
  erl_syntax:fun_expr([erl_syntax:clause([Var], abstr(true), [NewCase])]).

extract_patterns(Clauses) ->
  extract_patterns(Clauses, []).

extract_patterns([], Acc) ->
  Pat = [erl_syntax:underscore()],
  Guard = abstr(true),
  Body = [abstr(false)],
  lists:reverse([erl_syntax:clause(Pat, Guard, Body)|Acc]);
extract_patterns([Node|Rest], Acc) ->
  Body = [abstr(true)],
  Pats = erl_syntax:clause_patterns(Node),
  Guard = erl_syntax:clause_guard(Node),
  NClause = erl_syntax:clause(Pats, Guard, Body),
  extract_patterns(Rest, [erl_syntax:copy_attrs(Node, NClause)|Acc]).

is_safe(Module, Name, Arity, Instrumented) ->
  case
    erl_syntax:is_literal(Module) andalso
    erl_syntax:is_literal(Name)
  of
    false -> false;
    true ->
      NameLit = concr(Name),
      ModuleLit = concr(Module),
      case {ModuleLit, NameLit, Arity} of
        %% erlang:apply/3 is safe only when called inside of erlang.erl
        {erlang, apply, 3} ->
          ets:lookup_element(Instrumented, {current}, 2) =:= erlang;
        {erlang, load_nif, 2} ->
          has_load_nif;
        _ ->
          case erlang:is_builtin(ModuleLit, NameLit, Arity) of
            true ->
              not concuerror_callback:is_unsafe({ModuleLit, NameLit, Arity});
            false ->
              ets:lookup(Instrumented, ModuleLit) =/= []
          end
      end
  end.

abstr(Term) ->
  erl_syntax:abstract(Term).

concr(Tree) ->
  erl_syntax:concrete(Tree).

warn_to_string(Module, Tags) ->
  [io_lib:format("Module ~w ~s", [Module, tag_to_warn(T)]) || T <- Tags].

%%------------------------------------------------------------------------------

tag_to_warn(has_load_nif) ->
  "contains a call to erlang:load_nif/2."
    " Concuerror cannot reliably execute operations that are implemented as"
    " NIFs."
    " Moreover, Concuerror cannot even detect if a NIF is used by the test."
    " If your test uses NIFs, you may see error messages of the form"
    " 'replaying a built-in returned a different result than expected'."
    " If your test does not use NIFs you have nothing to worry about.".
