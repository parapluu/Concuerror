-module(simple_registry).

-export([simple_registry/0]).
-export([scenarios/0]).

-concuerror_options_forced(
   [ {instant_delivery, false}
   , {scheduling, oldest}
   ]).

scenarios() -> [{?MODULE, inf, dpor}].

simple_registry() ->
    start_registry(),
    register_many(3) ! {token, []},
    receive
        {token, A} ->
            stop_registry(),
            lists:member(true, A)
    end.

start_registry() ->
    Parent = self(),
    spawn(fun() -> registry(Parent) end),
    receive
        ok -> ok
    end.

stop_registry() ->
    registry ! stop.

registry(Parent) ->
    register(registry, self()),
    Parent ! ok,
    registry_loop(false).

registry_loop(Registered) ->
    receive
        stop -> ok;
        {reg, Pid} ->
            NewRegistered =
                case Registered of
                    false ->
                        monitor(process, Pid),
                        Pid ! true,
                        {true, Pid};
                    {true, OPid} ->
                        Ensure = is_process_alive(OPid),
                        case Ensure of
                            true ->
                                Pid ! false,
                                Registered;
                            false ->
                                monitor(process, Pid),
                                Pid ! true,
                                {true, Pid}
                        end
                end,
            registry_loop(NewRegistered);
        {'DOWN', _, _, Pid, _} ->
            case Registered of
                false -> registry_loop(false);
                {true, Pid} -> registry_loop(false);
                _ -> registry_loop(Registered)
            end
    end.

register_many(N) ->
    register_many(N, self()).

register_many(0, Link) -> Link;
register_many(N, Link) ->
    register_many(N-1, spawn(fun() -> worker(Link) end)).

worker(Link) ->
    registry ! {reg, self()},
    receive
        Info when is_boolean(Info) ->
            receive
                {token, L} ->
                    Link ! {token, [Info|L]}
            end
    end.
