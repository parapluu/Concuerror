-module(test_syntax_error).

-export([test0/0]).

%% Syntax error.
-spec test0() -> 'ok'.

test0() ->
    wtf?! !@#$%,
    'ok'.
