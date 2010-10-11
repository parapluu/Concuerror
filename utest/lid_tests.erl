%%%----------------------------------------------------------------------
%%% File        : lid_tests.erl
%%% Author      : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : LID interface unit tests
%%% Created     : 25 Sep 2010
%%%----------------------------------------------------------------------

-module(lid_tests).

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

%% TODO: Should use a fixture for lid:start/stop.

-spec get_pid_test() -> term().

get_pid_test() ->
    lid:start(),
    Pid = c:pid(0, 2, 3),
    Lid = lid:new(Pid, noparent),
    ?assertEqual(Pid, lid:get_pid(Lid)),
    lid:stop().

-spec from_pid_test() -> term().

from_pid_test() ->
    lid:start(),
    Pid = c:pid(0, 2, 3),
    Lid = lid:new(Pid, noparent),
    ?assertEqual(Lid, lid:from_pid(Pid)),
    lid:stop().

-spec parent_child_test() -> term().

parent_child_test() ->
    lid:start(),
    ParentPid = c:pid(0, 2, 3),
    ChildPid = c:pid(0, 2, 4),
    ParentLid = lid:new(ParentPid, noparent),
    ChildLid = lid:new(ChildPid, ParentLid),
    ?assertEqual(ChildPid, lid:get_pid(ChildLid)),
    lid:stop().

-spec link_test() -> term().

link_test() ->
    lid:start(),
    Pid1 = c:pid(0, 2, 3),
    Pid2 = c:pid(0, 2, 4),
    Pid3 = c:pid(0, 2, 5),
    Lid1 = lid:new(Pid1, noparent),
    Lid2 = lid:new(Pid2, Lid1),
    Lid3 = lid:new(Pid3, Lid1),
    lid:link(Lid1, Lid2),
    lid:link(Lid2, Lid3),
    Set = sets:from_list([Lid1, Lid3]),
    ISection = sets:subtract(Set, lid:get_linked(Lid2)),
    ?assertEqual(0, sets:size(ISection)),
    lid:stop().

-spec unlink_test() -> term().

unlink_test() ->
    lid:start(),
    Pid1 = c:pid(0, 2, 3),
    Pid2 = c:pid(0, 2, 4),
    Pid3 = c:pid(0, 2, 5),
    Lid1 = lid:new(Pid1, noparent),
    Lid2 = lid:new(Pid2, Lid1),
    Lid3 = lid:new(Pid3, Lid1),
    lid:link(Lid1, Lid2),
    lid:link(Lid2, Lid3),
    lid:unlink(Lid2, Lid1),
    Set = sets:from_list([Lid3]),
    ISection = sets:subtract(Set, lid:get_linked(Lid2)),
    ?assertEqual(0, sets:size(ISection)),
    lid:stop().

-spec monitor_test() -> term().

monitor_test() ->
    lid:start(),
    Pid1 = c:pid(0, 2, 3),
    Pid2 = c:pid(0, 2, 4),
    Pid3 = c:pid(0, 2, 5),
    Lid1 = lid:new(Pid1, noparent),
    Lid2 = lid:new(Pid2, Lid1),
    Lid3 = lid:new(Pid3, Lid1),
    lid:monitor(Lid1, Lid3, make_ref()),
    lid:monitor(Lid2, Lid3, make_ref()),
    Set = sets:from_list([Lid1, Lid2]),
    ISection = sets:subtract(Set, lid:get_monitored_by(Lid3)),
    ?assertEqual(0, sets:size(ISection)),
    lid:stop().

-spec demonitor_test() -> term().

demonitor_test() ->
    lid:start(),
    Pid1 = c:pid(0, 2, 3),
    Pid2 = c:pid(0, 2, 4),
    Pid3 = c:pid(0, 2, 5),
    Lid1 = lid:new(Pid1, noparent),
    Lid2 = lid:new(Pid2, Lid1),
    Lid3 = lid:new(Pid3, Lid1),
    lid:monitor(Lid1, Lid3, Ref = make_ref()),
    lid:monitor(Lid2, Lid3, make_ref()),
    lid:demonitor(Lid1, Ref),
    Set = sets:from_list([Lid2]),
    ISection = sets:subtract(Set, lid:get_monitored_by(Lid3)),
    ?assertEqual(0, sets:size(ISection)),
    lid:stop().

-spec cleanup_1_test() -> term().

cleanup_1_test() ->
    lid:start(),
    Pid1 = c:pid(0, 2, 3),
    Pid2 = c:pid(0, 2, 4),
    Lid1 = lid:new(Pid1, noparent),
    Lid2 = lid:new(Pid2, Lid1),
    lid:link(Lid1, Lid2),
    lid:cleanup(Lid1),
    ?assertEqual('not_found', lid:from_pid(Pid1)),
    ?assertEqual('not_found', lid:get_pid(Lid1)),
    lid:stop().

-spec cleanup_2_test() -> term().

cleanup_2_test() ->
    lid:start(),
    Pid1 = c:pid(0, 2, 3),
    Pid2 = c:pid(0, 2, 4),
    Lid1 = lid:new(Pid1, noparent),
    Lid2 = lid:new(Pid2, Lid1),
    lid:link(Lid1, Lid2),
    lid:cleanup(Lid1),
    ?assertEqual(0, sets:size(lid:get_linked(Lid2))),
    lid:stop().

-spec cleanup_3_test() -> term().

cleanup_3_test() ->
    lid:start(),
    Pid1 = c:pid(0, 2, 3),
    Pid2 = c:pid(0, 2, 4),
    Lid1 = lid:new(Pid1, noparent),
    Lid2 = lid:new(Pid2, Lid1),
    lid:monitor(Lid1, Lid2, make_ref()),
    lid:cleanup(Lid1),
    ?assertEqual(0, sets:size(lid:get_monitored_by(Lid2))),
    lid:stop().

-spec fold_pids_test() -> term().

fold_pids_test() ->
    lid:start(),
    Pid1 = c:pid(0, 2, 3),
    Pid2 = c:pid(0, 2, 4),
    Lid1 = lid:new(Pid1, noparent),
    _Lid2 = lid:new(Pid2, Lid1),
    Fun = fun(P, A) -> [P|A] end,
    Result = lid:fold_pids(Fun, []),
    ?assertEqual([Pid2, Pid1], Result),
    lid:stop().
