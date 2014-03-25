-module(main_and_backup).

-export([main_and_backup/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

main_and_backup() ->
    register(parent, self()),
    spawn(fun spawner/0),
    spawn(fun spawner/0),
    receive
        ok ->
            receive
                ok -> ok
            end
    end,
    server_backup ! ok,
    server ! ok.

spawner() ->
    case whereis(server) of
        undefined ->
            Spid = spawn(fun server/0),
            %% In race condition there can be only one that succeeds to register
            try
                register(server, Spid) % We are it
            catch
                _:_ -> % Server registered, register as backup
                    register(server_backup, Spid)
            end;
        _ -> % Server registered, start backup
            Bpid = spawn(fun server/0),
            register(server_backup, Bpid)
    end,
    parent ! ok.

server() ->
    receive
        ok -> ok
    end.
