-module(ets_info_details).

-compile(export_all).

-include_lib("eunit/include/eunit.hrl").

scenarios() ->
  [ test
  ].

test() ->
  OptionCombos =
    [lists:append([Protection, Naming]) ||
      Protection <- [[], [private], [public], [protected]],
      Naming <- [[], [named_table]]
    ],
  test_combos(OptionCombos).

test_combos([]) ->
  ok;
test_combos([Options|Rest]) ->
  test_no_heir(Options),
  test_heir(Options),
  test_combos(Rest).

test_no_heir(Options) ->
  Tid = ets:new(table, Options),
  check_details(Tid, Options),
  check_owner(Tid, self()),
  ets:delete(Tid).

test_heir(Options) ->
  P = self(),
  Message = foo,
  FullOptions = [{heir, P, Message}|Options],
  Fun =
    fun() ->
        Tid = ets:new(table, FullOptions),
        check_details(Tid, FullOptions),
        check_owner(Tid, self()),
        P ! {check, Tid},
        receive ok -> ok end
    end,
  Q = spawn(Fun),
  Tid =
    receive
      {check, T} ->
        check_details(T, FullOptions),
        check_owner(T, Q),
        Q ! ok,
        T
    end,
  receive
    {'ETS-TRANSFER', Tid, Q, Message} ->
      check_details(Tid, FullOptions),
      check_owner(Tid, self())
  end,
  ets:delete(Tid).

check_owner(Tid, Owner) ->
  ?assertEqual(Owner, ets:info(Tid, owner)).

check_details(Tid, []) ->
  Info = ets:info(Tid),
  Fun =
    fun(Field) ->
        ?assertNotEqual(false, lists:keyfind(Field, 1, Info))
    end,
  lists:foreach(
    Fun,
    [ owner
    , heir
    , name
    , named_table
    , type
    , keypos
    , protection
    ]);
check_details(Tid, [Opt|Rest]) ->
  case Opt of
    Protection
      when
        Protection =:= private;
        Protection =:= protected;
        Protection =:= public
        ->
      ?assertEqual(Protection, ets:info(Tid, protection));
    named_table ->
      ?assertEqual(true, ets:info(Tid, named_table));
    {heir, P, _} ->
      ?assertEqual(P, ets:info(Tid, heir))
  end,
  check_details(Tid, Rest).
