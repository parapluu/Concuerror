%%% @private
-module(concuerror_instrumenter).

-export([instrument/3, is_unsafe/1]).

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
              not is_unsafe({ModuleLit, NameLit, Arity});
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

%%------------------------------------------------------------------------------

-spec is_unsafe({atom(), atom(), non_neg_integer()}) -> boolean().

is_unsafe({erlang, exit, 2}) ->
  true;
is_unsafe({erlang, pid_to_list, 1}) ->
  true; %% Instrumented for symbolic PIDs pretty printing.
is_unsafe({erlang, fun_to_list, 1}) ->
  true; %% Instrumented for fun pretty printing.
is_unsafe({erlang, F, A}) ->
  case
    (erl_internal:guard_bif(F, A)
     orelse erl_internal:arith_op(F, A)
     orelse erl_internal:bool_op(F, A)
     orelse erl_internal:comp_op(F, A)
     orelse erl_internal:list_op(F, A)
     orelse is_data_type_conversion_op(F))
  of
    true -> false;
    false ->
      StringF = atom_to_list(F),
      not erl_safe(StringF)
  end;
is_unsafe({erts_internal, garbage_collect, _}) ->
  false;
is_unsafe({Safe, _, _})
  when
    Safe =:= binary
    ; Safe =:= lists
    ; Safe =:= maps
    ; Safe =:= math
    ; Safe =:= re
    ; Safe =:= string
    ; Safe =:= unicode
    ->
  false;
is_unsafe({error_logger, warning_map, 0}) ->
  false;
is_unsafe({file, native_name_encoding, 0}) ->
  false;
is_unsafe({net_kernel, dflag_unicode_io, 1}) ->
  false;
is_unsafe({os, F, A})
  when
    {F, A} =:= {get_env_var, 1};
    {F, A} =:= {getenv, 1}
    ->
  false;
is_unsafe({prim_file, internal_name2native, 1}) ->
  false;
is_unsafe(_) ->
  true.

is_data_type_conversion_op(Name) ->
  StringName = atom_to_list(Name),
  case re:split(StringName, "_to_") of
    [_] -> false;
    [_, _] -> true
  end.

erl_safe("adler32"               ++ _) -> true;
erl_safe("append"                ++ _) -> true;
erl_safe("apply"                     ) -> true;
erl_safe("bump_reductions"           ) -> true;
erl_safe("crc32"                 ++ _) -> true;
erl_safe("decode_packet"             ) -> true;
erl_safe("delete_element"            ) -> true;
erl_safe("delete_module"             ) -> true;
erl_safe("dt_"                   ++ _) -> true;
erl_safe("error"                     ) -> true;
erl_safe("exit"                      ) -> true;
erl_safe("external_size"             ) -> true;
erl_safe("fun_info"              ++ _) -> true;
erl_safe("function_exported"         ) -> true;
erl_safe("garbage_collect"           ) -> true;
erl_safe("get_module_info"           ) -> true;
erl_safe("hibernate"                 ) -> false; %% Must be instrumented.
erl_safe("insert_element"            ) -> true;
erl_safe("iolist_size"               ) -> true;
erl_safe("is_builtin"                ) -> true;
erl_safe("load_nif"                  ) -> true;
erl_safe("make_fun"                  ) -> true;
erl_safe("make_tuple"                ) -> true;
erl_safe("match_spec_test"           ) -> true;
erl_safe("md5"                   ++ _) -> true;
erl_safe("phash"                 ++ _) -> true;
erl_safe("raise"                     ) -> true;
erl_safe("seq_"                  ++ _) -> true;
erl_safe("setelement"                ) -> true;
erl_safe("split_binary"              ) -> true;
erl_safe("subtract"                  ) -> true;
erl_safe("throw"                     ) -> true;
erl_safe(                           _) -> false.
