%% -*- erlang-indent-level: 2 -*-

-module(concuerror_instrumenter).

-export([instrument/2]).

-define(inspect, concuerror_inspect).

-define(flag(A), (1 bsl A)).

-define(input, ?flag(1)).
-define(output, ?flag(2)).

-define(ACTIVE_FLAGS, [?input, ?output]).

%% -define(DEBUG_FLAGS, lists:foldl(fun erlang:'bor'/2, 0, ?ACTIVE_FLAGS)).
-include("concuerror.hrl").

-spec instrument(cerl:cerl(), ets:tid()) -> cerl:cerl().

instrument(CoreCode, Instrumented) ->
  ?if_debug(Stripper = fun(Tree) -> cerl:set_ann(Tree, []) end),
  ?debug_flag(?input, "~s\n",
              [cerl_prettypr:format(cerl_trees:map(Stripper, CoreCode))]),
  {R, {Instrumented, _}} =
    cerl_trees:mapfold(fun mapfold/2, {Instrumented, 1}, CoreCode),
  ?debug_flag(?output, "~s\n",
              [cerl_prettypr:format(cerl_trees:map(Stripper, R))]),
  R.

mapfold(Tree, {Instrumented, Var}) ->
  Type = cerl:type(Tree),
  NewTree =
    case Type of
      apply ->
        Op = cerl:apply_op(Tree),
        case cerl:is_c_fname(Op) of
          true -> Tree;
          false ->
            OldArgs = cerl:make_list(cerl:apply_args(Tree)),
            inspect(apply, [Op, OldArgs], Tree)
        end;
      call ->
        Module = cerl:call_module(Tree),
        Name = cerl:call_name(Tree),
        Args = cerl:call_args(Tree),
        case is_safe(Module, Name, length(Args), Instrumented) of
          true -> Tree;
          false ->
            inspect(call, [Module, Name, cerl:make_list(Args)], Tree)
        end;
      'receive' ->
        Clauses = cerl:receive_clauses(Tree),
        Timeout = cerl:receive_timeout(Tree),
        Action = cerl:receive_action(Tree),
        Fun = receive_matching_fun(Tree),
        Call = inspect('receive', [Fun, Timeout], Tree),
        case Timeout =:= cerl:c_atom(infinity) of
          false ->
            %% Replace original timeout with a fresh variable to make it
            %% skippable on demand.
            TimeoutVar = cerl:c_var(Var),
            RecTree = cerl:update_c_receive(Tree, Clauses, TimeoutVar, Action),
            cerl:update_tree(Tree, 'let', [[TimeoutVar], [Call], [RecTree]]);
          true ->
            %% Leave infinity timeouts unaffected, as the default code generated
            %% by the compiler does not bind any additional variables in the
            %% after clause.
            cerl:update_tree(Tree, seq, [[Call], [Tree]])
        end;
      _ -> Tree
    end,
  NewVar =
    case Type of
      'receive' -> Var + 1;
      _ -> Var
    end,
  {NewTree, {Instrumented, NewVar}}.

inspect(Tag, Args, Tree) ->
  CTag = cerl:c_atom(Tag),
  CArgs = cerl:make_list(Args),
  cerl:update_tree(Tree, call,
                   [[cerl:c_atom(?inspect)],
                    [cerl:c_atom(instrumented)],
                    [CTag, CArgs, cerl:abstract(cerl:get_ann(Tree))]]).

receive_matching_fun(Tree) ->
  Msg = cerl:c_var(message),
  Clauses = extract_patterns(cerl:receive_clauses(Tree)),
  Body = cerl:update_tree(Tree, 'case', [[Msg], Clauses]),
  cerl:update_tree(Tree, 'fun', [[Msg], [Body]]).

extract_patterns(Clauses) ->
  extract_patterns(Clauses, []).

extract_patterns([], Acc) ->
  Pat = [cerl:c_var(message)],
  Guard = cerl:c_atom(true),
  Body = cerl:c_atom(false),
  lists:reverse([cerl:c_clause(Pat, Guard, Body)|Acc]);
extract_patterns([Tree|Rest], Acc) ->
  Body = cerl:c_atom(true),
  Pats = cerl:clause_pats(Tree),
  Guard = cerl:clause_guard(Tree),
  extract_patterns(Rest, [cerl:update_c_clause(Tree, Pats, Guard, Body)|Acc]).

is_safe(Module, Name, Arity, Instrumented) ->
  case
    cerl:is_literal(Module) andalso
    cerl:is_literal(Name)
  of
    false -> false;
    true ->
      NameLit = cerl:concrete(Name),
      ModuleLit = cerl:concrete(Module),
      case erlang:is_builtin(ModuleLit, NameLit, Arity) of
        true ->
          (ModuleLit =:= erlang
           andalso
             (erl_internal:guard_bif(NameLit, Arity)
              orelse erl_internal:arith_op(NameLit, Arity)
              orelse erl_internal:bool_op(NameLit, Arity)
              orelse erl_internal:comp_op(NameLit, Arity)
              orelse erl_internal:list_op(NameLit, Arity)
             )
          ) orelse
            ModuleLit =:= binary
            orelse
            ModuleLit =:= maps
            orelse
            ModuleLit =:= unicode
            orelse %% The rest are defined in concuerror.hrl
            lists:member({ModuleLit, NameLit, Arity}, ?RACE_FREE_BIFS);
        false ->
          %% This special test is needed as long as erlang:apply/3 is not
          %% classified as a builtin in case we instrument erlang before we find
          %% a call to it. We need to not instrument it in erlang.erl itself,
          %% though.
          (ets:lookup_element(Instrumented, {current}, 2) =:= erlang
           orelse
           {ModuleLit, NameLit, Arity} =/= {erlang, apply, 3})
            andalso
            ets:lookup(Instrumented, ModuleLit) =/= []
      end
  end.
