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

-spec to_pid_test() -> term().

to_pid_test() ->
    lid:start(),
    Pid = c:pid(0, 2, 3),
    Lid = lid:new(Pid, noparent),
    ?assertEqual(Pid, lid:to_pid(Lid)),
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
    ?assertEqual(ChildPid, lid:to_pid(ChildLid)),
    lid:stop().

%% NOTE: Implementation dependent.
-spec two_children_impl_test() -> term().

two_children_impl_test() ->
    lid:start(),
    ParentPid = c:pid(0, 2, 3),
    FirstChildPid = c:pid(0, 2, 4),
    SecondChildPid = c:pid(0, 2, 5),
    ParentLid = lid:new(ParentPid, noparent),
    FirstChildLid = lid:new(FirstChildPid, ParentLid),
    SecondChildLid = lid:new(SecondChildPid, ParentLid),
    ?assertEqual(FirstChildLid, ParentLid ++ ".1"),
    ?assertEqual(SecondChildLid, ParentLid ++ ".2"),
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

-spec trap_exit_test() -> term().

trap_exit_test() ->
    lid:start(),
    Pid1 = c:pid(0, 2, 3),
    Pid2 = c:pid(0, 2, 4),
    Pid3 = c:pid(0, 2, 5),
    Lid1 = lid:new(Pid1, noparent),
    _Lid2 = lid:new(Pid2, Lid1),
    Lid3 = lid:new(Pid3, Lid1),
    lid:update_flags(Lid1, {trap_exit, true}),
    lid:update_flags(Lid3, {trap_exit, true}),
    Set = sets:from_list([Lid1, Lid3]),
    ISection = sets:subtract(Set, lid:get_trapping_exits()),
    ?assertEqual(0, sets:size(ISection)),
    lid:stop().

-spec cleanup_test() -> term().

cleanup_test() ->
    lid:start(),
    Pid1 = c:pid(0, 2, 3),
    Pid2 = c:pid(0, 2, 4),
    Lid1 = lid:new(Pid1, noparent),
    Lid2 = lid:new(Pid2, Lid1),
    lid:link(Lid1, Lid2),
    lid:cleanup(Lid1),
    ?assertEqual('not_found', lid:from_pid(Pid1)),
    ?assertEqual('not_found', lid:to_pid(Lid1)),
    ?assertEqual(0, sets:size(lid:get_linked(Lid2))),
    lid:stop().
