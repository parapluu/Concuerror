-module(test_syntax_error).

-export([test0/0]).

-include("CED.hrl").

%% Syntax error.
-spec test0() -> 'ok'.

test0() ->
    wtf?! !@#$%,
    'ok'.
