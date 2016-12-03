-module(sleep_set_block_not_bad).

-export([test/0]).

-export([scenarios/0]).

-concuerror_options_forced([{keep_going, false}, {ignore_error, deadlock}]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf, persistent}].

%%------------------------------------------------------------------------------

test() -> readers(2).

readers(N) ->
    ets:new(tab, [public, named_table]),
    Writer = fun() -> ets:insert(tab, {x, 42}) end,
    Reader = fun(I) -> ets:lookup(tab, I), ets:lookup(tab, x) end,
    spawn(Writer),
    [spawn(fun() -> Reader(I) end) || I <- lists:seq(1, N)],
    receive after infinity -> deadlock end.
