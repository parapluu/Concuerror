-module(ets_select).

-concuerror_options_forced([show_races]).

-export([match_against_matching_keys/0,
         match_against_matching_tuples/0,
         match_against_matching_matchspec/0,
         match_against_different_keys/0,
         match_against_different_tuples/0,
         match_against_different_matchspec/0,
         match_object_against_matching_keys/0,
         match_object_against_matching_tuples/0,
         match_object_against_matching_matchspec/0,
         match_object_against_different_keys/0,
         match_object_against_different_tuples/0,
         match_object_against_different_matchspec/0,
         select_against_matching_keys/0,
         select_against_matching_tuples/0,
         select_against_matching_matchspec/0,
         select_against_different_keys/0,
         select_against_different_tuples/0,
         select_against_different_matchspec/0,
         select_delete_against_matching_keys/0,
         select_delete_against_matching_tuples/0,
         select_delete_against_matching_any/0,
         select_delete_against_matching_matchspec/0,
         select_delete_against_different_keys/0,
         select_delete_against_different_tuples/0,
         select_delete_against_different_any/0,
         select_delete_against_different_matchspec/0
        ]).

-export([scenarios/0]).

-define(match_foo, {foo, '_'}).
-define(match_even, {'_', 0}).
-define(select_even(Res), [{{'$1', '$2'},        % match head
                            [{'andalso',         % guard
                              {'is_integer', '$1'},
                              {'=:=', '$2', 0}
                             }],
                            [Res]                % body
                           }]).
-define(select_atom(Res), [{{'$1', '$2'},        % match head
                            [{'andalso',         % guard
                              {'is_atom', '$1'},
                              {'=:=', '$1', '$2'}
                             }],
                            [Res]                % body
                           }]).

scenarios() ->
  [{list_to_atom(Op ++ "_against_" ++ Mode ++ "_" ++ Data), inf, dpor}
   || Op <- ["match", "match_object", "select", "select_delete"],
      Mode <- ["matching", "different"],
      Data <- ["keys", "tuples", "any", "matchspec"],

      %% Only allow mutating ops against any!
      %%
      %% The only mutating ets op that would affect all keys is
      %% give_away/2, which is not suitable for these tests
      Data =/= "any" orelse Op =:= "select_delete"
  ].

%% match
match_against_matching_keys() ->
  test(match, ?match_even, delete, 2).

match_against_matching_tuples() ->
  test(match, ?match_even, insert, {20, 0}).

match_against_matching_matchspec() ->
  test(match, ?match_even, select_delete, ?select_even(true)).

match_against_different_keys() ->
  test(match, ?match_foo, delete, 2).

match_against_different_tuples() ->
  test(match, ?match_even, insert, {21, 1}).

match_against_different_matchspec() ->
  test(match, ?match_foo, select_delete, ?select_even(true)).

%% match_object
match_object_against_matching_keys() ->
  test(match_object, ?match_even, delete, 2).

match_object_against_matching_tuples() ->
  test(match_object, ?match_even, insert, {20, 0}).

match_object_against_matching_matchspec() ->
  test(match_object, ?match_even, select_delete, ?select_even(true)).

match_object_against_different_keys() ->
  test(match_object, ?match_foo, delete, 2).

match_object_against_different_tuples() ->
  test(match_object, ?match_even, insert, {21, 1}).

match_object_against_different_matchspec() ->
  test(match_object, ?match_foo, select_delete, ?select_even(true)).

%% select
select_against_matching_keys() ->
  test(select, ?select_even('$_'), delete, 2).

select_against_matching_tuples() ->
  test(select, ?select_even('$_'), insert, {20, 0}).

select_against_matching_matchspec() ->
  test(select, ?select_even('$_'), select_delete, ?select_even(true)).

select_against_different_keys() ->
  test(select, ?select_even('$_'), delete, foo).

select_against_different_tuples() ->
  test(select, ?select_even('$_'), insert, {21, 1}).

select_against_different_matchspec() ->
  test(select, ?select_even('$_'), select_delete, ?select_atom(true)).

%% select_delete
select_delete_against_matching_keys() ->
  test(select_delete, ?select_even(true), lookup, 2).

select_delete_against_matching_tuples() ->
  %% Note: this may not be a perfect test case, as insert is also a
  %% mutating op. So it may happen that Concuerror checks the insert
  %% against the matchspec instead of the select_delete against the
  %% tuples.
  test(select_delete, ?select_even(true), insert, {20, 0}).

select_delete_against_matching_any() ->
  test(select_delete, ?select_even(true), next, 1).

select_delete_against_matching_matchspec() ->
  test(select_delete, ?select_even(true), match, ?match_even).

select_delete_against_different_keys() ->
  test(select_delete, ?select_even(true), lookup, foo).

select_delete_against_different_tuples() ->
  %% Note: this may not be a perfect test case, as insert is also a
  %% mutating op. So it may happen that Concuerror checks the insert
  %% against the matchspec instead of the select_delete against the
  %% tuples.
  test(select_delete, ?select_even(true), insert, {21, 1}).

select_delete_against_different_any() ->
  test(select_delete, ?select_even(true), next, 2).

select_delete_against_different_matchspec() ->
  test(select_delete, ?select_even(true), match, ?match_foo).

%% generic test implementation
test(Op1, Arg1, Op2, Arg2) ->
  %% Prepare a table
  T = ets:new(table, [public, ordered_set]),
  ets:insert(T, [{N, N rem 2} || N <- lists:seq(1, 10)]),
  ets:insert(T, [{foo, foo}, {bar, bar}, {baz, baz}]),

  %% Perform the two operations in parallel
  {Pid, Ref} = spawn_monitor(ets, Op1, [T, Arg1]),
  apply(ets, Op2, [T, Arg2]),

  %% Wait for the other operation to finish before destroying the table
  receive {'DOWN', Ref, process, Pid, _} -> ok end,
  receive after infinity -> ok end.
