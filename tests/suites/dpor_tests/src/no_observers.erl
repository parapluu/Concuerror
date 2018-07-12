-module(no_observers).

-compile(export_all).

-concuerror_options_forced([{use_receive_patterns, false}]).

scenarios() ->
  [ test
  ].

test() ->
  P = self(),
  Fun = fun() -> P ! self() end,
  P1 = spawn(Fun),
  P2 = spawn(Fun),
  receive
    P1 ->
      receive
        P2 ->
          ok
      end
  end.
