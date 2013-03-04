-module(monitor_demonitor).

-export([monitor_demonitor/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

monitor_demonitor() ->
    Pid1 = spawn(fun() -> receive ok -> ok end end),
    spawn(fun() ->
                  Pid1 ! ok,
                  Ref = monitor(process, Pid1),
                  receive
                      {'DOWN', Ref, process, Pid1, normal} ->
                          ok
                  end
          end),
    Pid3 = spawn(fun() -> receive ok -> ok end end),
    spawn(fun() ->
                  Ref = monitor(process, Pid3),
                  Pid3 ! ok,
                  demonitor(Ref),
                  receive
                      {'DOWN', Ref, process, Pid3, normal} ->
                          receive
                              deadlock -> ok
                          end
                  after
                      0 -> ok
                  end
          end).
