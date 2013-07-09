-module(foobar).

-export([foo/0]).

foo() ->
    bar().

bar() ->
    ok.
