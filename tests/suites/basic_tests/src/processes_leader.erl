-module(processes_leader).

-export([test/0]).
-export([scenarios/0]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf, optimal}].

%%------------------------------------------------------------------------------

test() ->
  group_leader(S = self(), self()),
  W = fun W(0) -> ok;
          W(N) -> spawn_monitor(fun () -> W(N - 1) end)
      end,
  W(2),
  [exit(P, kill)
   || P <- processes(),
      P =/= S,
      {group_leader, S} =:= process_info(P, group_leader)
  ].
