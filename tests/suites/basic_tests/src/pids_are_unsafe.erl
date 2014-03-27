-module(pids_are_unsafe).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    {Last, Switches} = spawn_switches_and_togglers(2),
    freeze = broadcast(Switches, freeze),
    Last ! {token, []},
    receive
        {token, _Status} -> ok
    end.

spawn_switches_and_togglers(N) ->
    spawn_switches_and_togglers(N, self(), sets:new()).

spawn_switches_and_togglers(0, Last, Switches) ->
    {Last, Switches};
spawn_switches_and_togglers(N, Link, Switches) ->
    Switch = spawn(fun() -> switch(Link) end),
    spawn(fun() -> toggler(Switch) end),
    NewSwitches = sets:add_element(Switch, Switches),
    spawn_switches_and_togglers(N-1, Switch, NewSwitches).

switch(Link) ->
    switch(Link, false).

switch(Link, Status) ->
    receive
        toggle -> switch(Link, not Status);
        freeze ->
            receive
                {token, Status} ->
                    Link ! {token, [Link|Status]}
            end
    end.

toggler(Switch) ->
    Switch ! toggle.

broadcast(Switches, Message) ->
    sets:fold(fun(X, M) -> X ! M end, Message, Switches).
