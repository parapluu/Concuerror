-module(test).

-export([scenarios/0]).
-export([t_simple_reg/0, t_simple_reg_or_locate/0, t_reg_or_locate2/0]).
-export([test1/0, test2/0, test3/0, test4/0]).
-export([concuerror_options/0]).

-include_lib("eunit/include/eunit.hrl").

concuerror_options() ->
	[{after_timeout, 1000}, {treat_as_normal, shutdown}, {ignore_error, deadlock}].

scenarios() ->
    [{T, inf, dpor} ||
        T <- [t_simple_reg, t_simple_reg_or_locate, t_reg_or_locate2]].

t_simple_reg() ->
    gproc_sup:start_link([]),
    ?assert(gproc:reg({n,l,name}) =:= true),
    ?assert(gproc:where({n,l,name}) =:= self()),
    ?assert(gproc:unreg({n,l,name}) =:= true),
    ?assert(gproc:where({n,l,name}) =:= undefined).

t_simple_reg_or_locate() ->
    P = self(),
    gproc_sup:start_link([]),
    ?assertMatch({P, undefined}, gproc:reg_or_locate({n,l,name})),
    ?assertMatch(P, gproc:where({n,l,name})),
    ?assertMatch({P, my_val}, gproc:reg_or_locate({n,l,name2}, my_val)),
    ?assertMatch(my_val, gproc:get_value({n,l,name2})).

t_reg_or_locate2() ->
    P = self(),
    gproc_sup:start_link([]),
    {P1,R1} = spawn_monitor(fun() ->
				    Ref = erlang:monitor(process, P),
				    gproc:reg({n,l,foo}, the_value),
				    P ! {self(), ok},
				    receive
					{'DOWN',Ref,_,_,_} -> ok
				    end
			    end),
    receive {P1, ok} -> ok end,
    ?assertMatch({P1, the_value}, gproc:reg_or_locate({n,l,foo})),
    exit(P1, kill),
    receive
	{'DOWN',R1,_,_,_} ->
	    ok
    end.

test1() ->
    Self = self(),
    gproc_sup:start_link([]),
    true = gproc:reg({n,l,name}),
    Self = gproc:where({n,l,name}),
    true = gproc:unreg({n,l,name}),
    undefined = gproc:where({n,l,name}).

test2() ->
    P = self(),
    gproc_sup:start_link([]),
    {P, undefined} = gproc:reg_or_locate({n,l,name}),
    P = gproc:where({n,l,name}),
    {P, my_val} = gproc:reg_or_locate({n,l,name2}, my_val),
    my_val = gproc:get_value({n,l,name2}).

test3() ->
    gproc_sup:start_link([]),
    gproc_chain(1) ! {token, []},
    receive
        {token, L} ->
            true = lists:member(true, L)
    end.

test3(N) ->
    gproc_sup:start_link([]),
    gproc_chain(N) ! {token, []},
    receive
        {token, L} ->
            true = lists:member(true, L)
    end,
    receive after infinity -> ok end.

test4() ->
    gproc_sup:start_link([]),
    true = gproc:reg({n,l,name}),
    gproc_chain(3) ! {token, []},
    receive
        {token, L} ->
            false = lists:member(true, L)
    end.

gproc_chain(N) ->
    gproc_chain(N, self()).

gproc_chain(0, Last) -> Last;
gproc_chain(N, Link) -> 
    gproc_chain(N-1, spawn(fun() -> gproc_chain_member(Link) end)).

gproc_chain_member(Link) ->
    R =
        try gproc:reg({n,l,name}) of
            _ -> true
        catch
            _:_ -> false
        end,
    receive
        {token, L} ->
            Link ! {token, [R|L]}
    end.

pub_sub() ->
    gproc_sup:start_link([]),
    spawn_workers(3) ! token,
    receive token -> ok end,
    gproc:send({p,l,worker}, event1),
    %gproc:send({p,l,worker}, event2),
    receive after infinity -> ok end.

spawn_workers(N) ->
    spawn_workers(N, self()).

spawn_workers(0, Link) -> Link;
spawn_workers(N, Link) ->
    spawn_workers(N-1, spawn(fun() -> worker(Link) end)).

worker(Link) ->
    gproc:reg({p, l, worker}),
    receive token -> Link ! token end,
    receive
        event1 -> ok
        %% E1 ->
        %%     receive
        %%         E2 ->
        %%             {event1, event2} = {E1, E2}
        %%     end
    end.
