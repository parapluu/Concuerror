-module(send_vs_trap_exit).

-export([send_vs_trap_exit/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

send_vs_trap_exit() ->
    P1 = self(),
    _P2 = spawn_link(
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
                  self() ! banana,
                  receive
                      banana -> ok;
                      Msg -> throw(Msg)
                  end
          end),
    catch link(P3).
