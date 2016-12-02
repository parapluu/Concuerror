-module(workers).

-export([workers/0]).
-export([scenarios/0]).

-define(LOW, 1).
-define(HIGH, 2).
-define(ADD, 10).
-define(WORKERS, 2).

-concuerror_options_forced([{instant_delivery, false}]).

scenarios() -> [{?MODULE, inf, dpor}].

workers() ->
    Self = self(),
    Pid =
        spawn(fun() -> server(?WORKERS, lists:seq(?LOW, ?HIGH), [], Self) end),
    spawner(?WORKERS, Pid),
    receive
        {ok, Res} ->
            Xp = lists:seq(?LOW + ?ADD, ?HIGH + ?ADD),
            Res = Xp
    end.

server(0, [], Result, Parent) ->
    Parent ! {ok, lists:sort(Result)};
server(Workers, Work, Result, Parent) ->
    receive
        {res, R} ->
            server(Workers, Work, [R|Result], Parent)
    after 0 ->
            receive
                {work, Pid} ->
                    case Work of
                        [W|Ork] ->
                            Pid ! {work, W},
                            server(Workers, Ork, Result, Parent);
                        [] ->
                            Pid ! no_work,
                            server(Workers, Work, Result, Parent)
                    end;
                exit ->
                    server(Workers - 1, Work, Result, Parent)
            end
    end.

spawner(0, _Pid) -> ok;
spawner(N, Pid) ->
    spawn(fun() -> worker(Pid) end),
    spawner(N-1, Pid).

worker(Pid) ->
    Pid ! {work, self()},
    receive
        {work, N} ->
            Pid ! {res, N + ?ADD},
            worker(Pid);
        no_work ->
            Pid ! exit
    end.
