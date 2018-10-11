-module(monitor_order).

-export([monitor_order/0]).
-export([scenarios/0]).

-concuerror_options([{treat_as_normal, [test]},
                     {first_process_errors_only, true}
                    ]).

scenarios() -> [{?MODULE, inf, dpor}].

monitor_order() ->
  P1 = spawn(fun () -> p1(undefined) end),
  _2 = spawn(fun () -> p2(P1) end),
  P3 = spawn(fun () -> p3(P1) end),
  exit(P3, test).

p1(State) ->
  receive
    {p2, P2} ->
      erlang:send_after(0, self(), clear),
      p1({P2, monitor(process, P2)});
    p3 ->
      case State of
        undefined -> ok;
        {P2, _Mon} -> P2 ! ok
      end,
      p1(State);
    demonitor_p2 ->
      case State of
        undefined -> exit(test);
        {_P2, Mon} ->
          demonitor(Mon, [flush])
      end,
      p1(undefined);
    clear ->
      p1(undefined)
  end.

p2(P1) ->
  Ref = monitor(process, P1),
  P1 ! {p2, self()},
  receive
    ok ->
      P1 ! demonitor_p2,
      demonitor(Ref, [flush])
  end.

p3(P1) ->
  Ref = monitor(process, P1),
  P1 ! p3,
  demonitor(Ref, [flush]).
