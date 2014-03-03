-module(i_hate_myself).

-export([i_hate_myself/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

i_hate_myself() ->
    Name = list_to_atom(lists:flatten(io_lib:format("~p",[make_ref()]))),
    spawn(fun() -> Name ! message end),
    register(Name, self()),
    receive
        message -> ok
    end.
