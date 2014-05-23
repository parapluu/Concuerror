-module(test).

-export([scenarios/0]).
-export([t_simple_reg/0, t_simple_reg_or_locate/0, t_reg_or_locate2/0]).
-export([concuerror_options/0]).

-include_lib("eunit/include/eunit.hrl").

concuerror_options() ->
	[{after_timeout, 1000}, {treat_as_normal, shutdown}, {ignore_error, deadlock}].

scenarios() ->
    [{T, inf, dpor} ||
        T <- [t_simple_reg, t_simple_reg_or_locate, t_reg_or_locate2]].

t_simple_reg() ->
    application:start(gproc),
    ?assert(gproc:reg({n,l,name}) =:= true),
    ?assert(gproc:where({n,l,name}) =:= self()),
    ?assert(gproc:unreg({n,l,name}) =:= true),
    ?assert(gproc:where({n,l,name}) =:= undefined).

t_simple_reg_or_locate() ->
    P = self(),
    application:start(gproc),
    ?assertMatch({P, undefined}, gproc:reg_or_locate({n,l,name})),
    ?assertMatch(P, gproc:where({n,l,name})),
    ?assertMatch({P, my_val}, gproc:reg_or_locate({n,l,name2}, my_val)),
    ?assertMatch(my_val, gproc:get_value({n,l,name2})).

t_reg_or_locate2() ->
    P = self(),
    application:start(gproc),
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
