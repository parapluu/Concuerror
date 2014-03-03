-module(after_vs_trap_exit).

-export([after_vs_trap_exit/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

after_vs_trap_exit() ->
    P1 = self(),
     _ = spawn_link(
           fun() ->
                   process_flag(trap_exit, true),
                   P1 ! ok,
                   receive after infinity -> block end
           end),
    receive ok -> ok end,
    P3 =
        spawn(
          fun() ->
                  process_flag(trap_exit, true),
                  receive
                      Msg -> throw(Msg)
                  after
                      0 -> ok
                  end
          end),
    catch link(P3).
