-module(ets_whereis).

-compile(export_all).

%%------------------------------------------------------------------------------

scenarios() ->
  case get_current_otp() > 20 of
    true ->
      [ whereis_good
      , whereis_bad
      , whereis_badarg
      , whereis_system
      , whereis_race_wr
      , whereis_race_ww
      , whereis_race_exit
      , whereis_race_del
      , race_whereis_r
      , race_whereis_w
      ];
    false -> []
  end.

get_current_otp() ->
  case erlang:system_info(otp_release) of
    "R" ++ _ -> 16; %% ... or earlier
    [D,U|_] -> list_to_integer([D,U])
  end.

%% Throw a coin in the air, if it lands early choose A, else choose B.
%% Concuerror will explore both. ;-)
flip(A, B) ->
  P = self(),
  spawn(fun() -> P ! coin end),
  receive
    coin -> A
  after
    0 ->
      receive
        coin -> B
      end
  end.

%%------------------------------------------------------------------------------

whereis_good() ->
  ets:new(table, [named_table]),
  true = undefined =/= ets:whereis(table).

whereis_bad() ->
  true = undefined =:= ets:whereis(table).

whereis_badarg() ->
  try
    ets:whereis(1.0),
    exit(fail)
  catch
    error:badarg -> ok
  end.

whereis_system() ->
  true = undefined =/= ets:whereis(logger).

whereis_race_wr() ->
  P = self(),
  table = ets:new(table, [public, named_table]),
  T = ets:whereis(table),
  C1 = flip(table, T),
  C2 = flip(table, T),
  P1 = spawn(fun() -> catch ets:insert(C1, {x, 1}), P ! {self(), ok} end),
  P2 = spawn(fun() -> catch ets:lookup(C2, x), P ! {self(), ok} end),
  receive
    {P1, ok} -> ok
  end,
  receive
    {P2, ok} -> ok
  end.

whereis_race_ww() ->
  P = self(),
  table = ets:new(table, [public, named_table]),
  T = ets:whereis(table),
  C1 = flip(table, T),
  C2 = flip(table, T),
  P1 = spawn(fun() -> catch ets:insert(C1, {x, 1}), P ! {self(), ok} end),
  P2 = spawn(fun() -> catch ets:insert(C2, {x, 2}), P ! {self(), ok} end),
  receive
    {P1, ok} -> ok
  end,
  receive
    {P2, ok} -> ok
  end.

whereis_race_exit() ->
  table = ets:new(table, [public, named_table]),
  T = ets:whereis(table),
  C1 = flip(table, T),
  spawn(fun() -> catch ets:insert(C1, {x, 1}) end).

whereis_race_del() ->
  table = ets:new(table, [public, named_table]),
  T = ets:whereis(table),
  C1 = flip(table, T),
  C2 = flip(table, T),
  spawn(fun() -> catch ets:insert(C1, {x, 1}) end),
  ets:delete(C2).

race_whereis_r() ->
  table = ets:new(table, [public, named_table]),
  spawn_monitor(fun() -> ets:lookup(table, x) end),
  ets:whereis(table),
  receive _ -> ok end.

race_whereis_w() ->
  table = ets:new(table, [public, named_table]),
  spawn_monitor(fun() -> ets:insert(table, {x, 1}) end),
  ets:whereis(table),
  receive _ -> ok end.
