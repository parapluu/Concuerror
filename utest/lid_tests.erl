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

%% Should use a fixture for lid:start/stop.
-spec to_pid_test() -> term().

to_pid_test() ->
    lid:start(),
    Pid = c:pid(0, 2, 3),
    Lid = lid:new(Pid, noparent),
    ?assertEqual(Pid, lid:to_pid(Lid)),
    lid:stop().

%% Should use a fixture for lid:start/stop.
-spec from_pid_test() -> term().

from_pid_test() ->
    lid:start(),
    Pid = c:pid(0, 2, 3),
    Lid = lid:new(Pid, noparent),
    ?assertEqual(Lid, lid:from_pid(Pid)),
    lid:stop().

%% NOTE: Implementation dependent.
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
