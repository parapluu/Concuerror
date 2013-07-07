%% -*- erlang-indent-level: 2 -*-

-module(concuerror_instrumenter).

-export([instrument/1]).

-define(inspect, concuerror_inspect).

-define(flag(A), (1 bsl A)).

-define(input, ?flag(1)).
-define(output, ?flag(2)).

-define(ACTIVE_FLAGS, [?input, ?output]).

%% -define(DEBUG_FLAGS, lists:foldl(fun erlang:'bor'/2, 0, ?ACTIVE_FLAGS)).
-include("concuerror.hrl").

-spec instrument(cerl:cerl()) -> cerl:cerl().

instrument(CoreCode) ->
  ?if_debug(Stripper = fun(Tree) -> cerl:set_ann(Tree, []) end),
  ?debug_flag(?input, "~s\n",
              [cerl_prettypr:format(cerl_trees:map(Stripper, CoreCode))]),
  Name = cerl:concrete(cerl:module_name(CoreCode)),
  {R, Name} = cerl_trees:mapfold(fun mapfold/2, Name, CoreCode),
  ?debug_flag(?output, "~s\n",
              [cerl_prettypr:format(cerl_trees:map(Stripper, R))]),
  R.

mapfold(Tree, ModName) ->
  NewTree =
    case cerl:type(Tree) of
      apply ->
        Op = cerl:apply_op(Tree),
        case cerl:type(Op) =:= atom of
          true -> Tree;
          false ->
            OldArgs = cerl:make_list(cerl:apply_args(Tree)),
            inspect(apply, [Op, OldArgs], Tree)
        end;
      call ->
        Module = cerl:call_module(Tree),
        Name = cerl:call_name(Tree),
        Args = cerl:call_args(Tree),
        case is_safe(ModName, Module, Name, length(Args)) of
          true -> Tree;
          false ->
            inspect(call, [Module, Name, cerl:make_list(Args)], Tree)
        end;
      'receive' ->
        Timeout = cerl:receive_timeout(Tree),
        Fun = receive_matching_fun(Tree),
        Call = inspect('receive', [Fun, Timeout], Tree),
        %% Replace original timeout with 0
        Clauses = cerl:receive_clauses(Tree),
        Action = cerl:receive_action(Tree),
        RecTree = cerl:update_c_receive(Tree, Clauses, cerl:c_int(0), Action),
        cerl:update_tree(Tree, seq, [[Call], [RecTree]]);
      _Other -> Tree
    end,
  {NewTree, ModName}.

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

is_safe(ModName, Module, Name, Arity) ->
  case
    cerl:is_literal(Module) andalso
    cerl:is_literal(Name)
  of
    false -> false;
    true ->
      NameLit = cerl:concrete(Name),
      ModuleLit = cerl:concrete(Module),
      %% Within the erlang module, variants of 'apply' are defined as
      %% erlang:apply and somehow this is not a BIF. These should be
      %% uninstrumented, or arbitrary applies will end up in an infinite loop:
      %% i.e. (erlang:apply -> concuerror -> not builtin ->
      %%       erlang:apply -> concuerror ...)
      {ModName, NameLit} =:= {'erlang', 'apply'}
        orelse
          (ModuleLit =:= erlang
           andalso
             (erl_internal:guard_bif(NameLit, Arity)
              orelse erl_internal:arith_op(NameLit, Arity)
              orelse erl_internal:bool_op(NameLit, Arity)
              orelse erl_internal:comp_op(NameLit, Arity)
              orelse erl_internal:list_op(NameLit, Arity)
             )
          )
        orelse %% The rest are defined in concuerror.hrl
        lists:member({ModuleLit, NameLit, Arity}, ?RACE_FREE_BIFS)
  end.
