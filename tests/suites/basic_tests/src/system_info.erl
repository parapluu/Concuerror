-module(system_info).

-export([test/0]).

-export([scenarios/0]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf, optimal}].

%%------------------------------------------------------------------------------

%% This is a dummy test function.
test() ->
  {registered_name, user} = erlang:process_info(whereis(user), registered_name).
