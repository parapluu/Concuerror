-module(my_test).

-export([test/1]).

test(small) ->
    foo_test();
test(large) ->
    foobar_test().

foo_test() ->
    dialyzer:run([{files, ["/home/stavros/git/Concuerror/foo.erl"]}, {from, src_code}]).

foobar_test() ->
    dialyzer:run([{files, ["/home/stavros/git/Concuerror/foobar.erl"]}, {from, src_code}]).
