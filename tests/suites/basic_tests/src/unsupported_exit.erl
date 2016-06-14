-module(unsupported_exit).

-export([scenarios/0]).
-export([exceptional/0]).

-export([test/0]).

scenarios() ->
    [{test, inf, dpor, crash}].

test() ->
    try
        erlang:monitor_node(node(), false)
    catch
        _:_ -> ok
    end.
            
exceptional() ->
  fun(_Expected, Actual) ->
      String =
        "Concuerror does not support calls to built-in erlang:monitor_node/2",
      Cmd = "grep \"" ++ String ++ "\" ",
      [_,_,_|_] = os:cmd(Cmd ++ Actual),
      true
  end.
