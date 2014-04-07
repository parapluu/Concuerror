%% The Great Computer Language Shootout
%% http://shootout.alioth.debian.org/
%%
%% Contributed by : Alkis Gotovos
%% Created        : 10 Oct 2010

-module(pidigits).

-compile([native, {hipe, [o3]}]).

-export([main/1]).

main(N) when is_integer(N) ->
    Pid = spawn_link(fun() -> io_worker() end),
    register(io_worker, Pid),
    stream({1, 0, 1}, 1, 0, N);
main([N]) -> main(list_to_integer(N)).

comp({Q, R, T}, {U, V, X}) -> {Q*U, Q*V + R*X, T*X}.

next({Q, R, T}) -> (Q*3 + R) div T.

safe({Q, R, T}, N) -> N =:= (Q*4 + R) div T.

prod({Z11, Z12, Z22}, N) -> {10*Z11, 10*(Z12 - N*Z22), Z22}.

stream(_Z, _K, N, N) -> ok;
stream(Z, K, P, N) ->
    Y = next(Z),
    case safe(Z, Y) of
	true ->
	    io_worker ! {Y, P + 1, N},
	    stream(prod(Z, Y), K, P + 1, N);
	false -> stream(comp(Z, {K, 4*K + 2, 2*K + 1}), K + 1, P, N)
    end.

io_worker() ->
    receive
	{Y, N, N} ->
	    Spaces = (10 - N rem 10) rem 10,
	    io:fwrite("~w~.*c\t:~w~n", [Y, Spaces, $ , N]),
	    erlang:halt(0);
	{Y, P, _N} when P rem 10 =:= 0 ->
	    io:fwrite("~w\t:~w~n", [Y, P]),
	    io_worker();
	{Y, _P, _N} ->
	    io:fwrite("~w", [Y]),
	    io_worker()
    end.
