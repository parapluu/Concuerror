%% Dpor should be able to detect dependencies based on
%% dynamic data (e.g. the key for the table).

-module(ets_ref_keys).

-export([ets_ref_keys/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

ets_ref_keys() ->
    Parent = self(),
    Ref = make_ref(),
    table = ets:new(table,[named_table, public]),
    P1 = spawn(fun() ->
                       receive
                           continue ->
                               ets:insert(table, {Ref, p1}),
                               Parent ! continue
                       end
               end),
    P2 = spawn(fun() ->
                       ets:insert(table, {Ref, p2}),
                       P1 ! continue
               end),
    P3 = spawn(fun() -> P1 ! continue end),
    receive
        continue ->
            [{Ref, p1}] = ets:lookup(table, Ref)
    end,
    receive
    after
        infinity -> deadlock
    end.
