-module(workers_2).

-export([workers_2/0]).
-export([scenarios/0]).

-define(LOW, 1).
-define(HIGH, 2).
-define(ADD, 10).
-define(WORKERS, 2).
-define(RETRIES, 2).

scenarios() -> [{?MODULE, inf, dpor}].

workers_2() ->
    Self = self(),
    Pid = spawn(fun() -> server(Self) end),
    spawner(?WORKERS, Pid),
    receive
        {ok, Res} ->
            Xp =
                lists:seq(?LOW + (1 + ?RETRIES) * ?ADD,
                          ?HIGH + (1 + ?RETRIES) * ?ADD),
            Xp = Res
    end.

server(Self) ->
    server(?WORKERS, ?RETRIES, lists:seq(?LOW, ?HIGH), Self).

server(0, 0, [], Parent) ->
    Parent ! {ok, lists:sort(collect_res())};
server(Workers, Retries, Work, Parent) ->
    receive
        {work, Pid} ->
            case Work of
                [W|Ork] ->
                    Pid ! {work, W},
                    server(Workers, Retries, Ork, Parent);
                [] ->
                    case Retries =:= 0 of
                        true ->
                            Pid ! no_work,
                            server(Workers, Retries, Work, Parent);
                        false ->
                            [R|Esult] = collect_res(),
                            Pid ! {work, R},
                            server(Workers, Retries - 1, Esult, Parent)
                    end
            end;
        exit ->
            server(Workers - 1, Retries, Work, Parent)
    end.

collect_res() ->
    collect_res([], ?HIGH - ?LOW + 1).

collect_res(Acc, 0) -> Acc;
collect_res(Acc, N) ->
    receive
        {res, R} -> collect_res([R|Acc], N-1)
    end.

spawner(0, Pid) -> ok;
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
