%% This is a collection of tests where a race between a pair of events
%% that is conditional on it being observed may constraint the
%% reversibility of a race between other operations (that can also be
%% conditional, or not).

%% The main conditional race is the one between the two {2, X} messages,
%% which are instantaneously delivered.

%% dep or indep denotates whether the race will be observed or not in
%% the 'naturally first' scheduling.

%% obs or unobs denotates whether the other race is also conditional
%% (on observability) (delivery of the {1, Y} messages) or not (ets
%% operations)

-module(observable_others).

-compile(export_all).

-concuerror_options_forced(
   [ {instant_delivery, true} % Make observable race related to program order
   , {use_receive_patterns, true}
   , {ignore_error, [deadlock]} % To retain ETS tables
   ]).

%%------------------------------------------------------------------------------

scenarios() ->
  [{T, inf, optimal} ||
    T <-
      [ dep_unobs
      , indep_unobs
      , dep_obs
      , indep_obs
      ]
  ].

%%------------------------------------------------------------------------------

%% When the race between the two '2' messages is reversed, the other
%% race becomes immediately reversible.

dep_unobs() ->
  ets:new(table, [named_table, public]),
  P = self(),
  F1 =
    fun() ->
        ets:insert(table, {key, value}),
        P ! {2, one}
    end,
  F2 =
    fun() ->
        P ! {2, two},
        [{key, value}] = ets:lookup(table, key)
    end,
  F3 =
    fun() ->
        P ! dependent
    end,
  F4 =
    fun() ->
        P ! independent
    end,
  spawn(F1),
  spawn(F2),
  spawn(F3),
  spawn(F4),
  receive
    independent -> ok;
    dependent ->
      receive
        {2, _} -> ok
      end
  end,
  block(). % To retain ETS tables

indep_unobs() ->
  ets:new(table, [named_table, public]),
  P = self(),
  F1 =
    fun() ->
        ets:insert(table, {key, value}),
        P ! {2, one}
    end,
  F2 =
    fun() ->
        P ! {2, two},
        [{key, value}] = ets:lookup(table, key)
    end,
  F3 =
    fun() ->
        P ! independent
    end,
  F4 =
    fun() ->
        P ! dependent
    end,
  spawn(F1),
  spawn(F2),
  spawn(F3),
  spawn(F4),
  receive
    independent ->
      receive
        {2, _} -> ok
      end;
    dependent ->
      ok
  end,
  block(). % To retain ETS tables

dep_obs() ->
  P = self(),
  F1 =
    fun() ->
        P ! {1, one},
        P ! {2, one}
    end,
  F2 =
    fun() ->
        P ! {2, two},
        P ! {1, two}
    end,
  F3 =
    fun() ->
        P ! dependent
    end,
  F4 =
    fun() ->
        P ! independent
    end,
  spawn(F1),
  spawn(F2),
  spawn(F3),
  spawn(F4),
  receive
    independent ->
      receive
        {1, X} -> one = X
      end;
    dependent ->
      receive
        {2, X} ->
          case X of
            one ->
              receive
                {1, Y} -> Y = X
              end;
            two -> ok
          end
      end
  end.

indep_obs() ->
  P = self(),
  F1 =
    fun() ->
        P ! {1, one},
        P ! {2, one}
    end,
  F2 =
    fun() ->
        P ! {2, two},
        P ! {1, two}
    end,
  F3 =
    fun() ->
        P ! independent
    end,
  F4 =
    fun() ->
        P ! dependent
    end,
  spawn(F1),
  spawn(F2),
  spawn(F3),
  spawn(F4),
  receive
    independent ->
      receive
        {2, X} ->
          case X of
            one ->
              receive
                {1, Y} -> Y = X
              end;
            two -> ok
          end
      end;
    dependent ->
      receive
        {1, X} -> one = X
      end
  end.

block() ->
  receive after infinity -> ok end.
