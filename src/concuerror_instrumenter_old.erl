%%% @private
-module(concuerror_instrumenter_old).

-export([instrument/3]).

-define(inspect, concuerror_inspect).

-define(flag(A), (1 bsl A)).

-define(input, ?flag(1)).
-define(output, ?flag(2)).

-define(ACTIVE_FLAGS, [?input, ?output]).

%% -define(DEBUG_FLAGS, lists:foldl(fun erlang:'bor'/2, 0, ?ACTIVE_FLAGS)).
-include("concuerror.hrl").

-spec instrument(module(), cerl:cerl(), concuerror_loader:instrumented())
                -> {cerl:cerl(), [iodata()]}.

instrument(?inspect, CoreCode, _Instrumented) ->
  %% The inspect module should never be instrumented.
  {CoreCode, []};
instrument(Module, CoreCode, Instrumented) ->
  ?if_debug(Stripper = fun(Tree) -> cerl:set_ann(Tree, []) end),
  ?debug_flag(?input, "~s\n",
              [cerl_prettypr:format(cerl_trees:map(Stripper, CoreCode))]),
  true = ets:insert(Instrumented, {{current}, Module}),
  {R, {Instrumented, _, Warnings}} =
    cerl_trees:mapfold(fun mapfold/2, {Instrumented, 1, []}, CoreCode),
  true = ets:delete(Instrumented, {current}),
  ?debug_flag(?output, "~s\n",
              [cerl_prettypr:format(cerl_trees:map(Stripper, R))]),
  {R, warn_to_string(Module, lists:usort(Warnings))}.

mapfold(Tree, {Instrumented, Var, Warnings}) ->
  Type = cerl:type(Tree),
  NewTreeAndMaybeWarn =
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
          has_load_nif -> {warn, Tree, has_load_nif};
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
  {NewTree, NewWarnings} =
    case NewTreeAndMaybeWarn of
      {warn, NT, W} -> {NT, [W|Warnings]};
      _ -> {NewTreeAndMaybeWarn, Warnings}
    end,
  NewVar =
    case Type of
      'receive' -> Var + 1;
      _ -> Var
    end,
  {NewTree, {Instrumented, NewVar, NewWarnings}}.

inspect(Tag, Args, Tree) ->
  CTag = cerl:c_atom(Tag),
  CArgs = cerl:make_list(Args),
  cerl:update_tree(Tree, call,
                   [[cerl:c_atom(?inspect)],
                    [cerl:c_atom(inspect)],
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
