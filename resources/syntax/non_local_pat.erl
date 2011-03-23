%%%----------------------------------------------------------------------
%%% File        : non_local_pat.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Test assignment to non-local variables in patterns
%%% Created     : 3 Jan 2010
%%%----------------------------------------------------------------------

-module(non_local_pat).

-export([non_local_pat_test/0]).

non_local_pat_test() ->
    Pid1 = spawn(fun() -> ok end),
    Pid2 = spawn(fun() -> ok end),
    receive
	C1 = {Pid1, _} -> nil
    end,
    receive
	C2 = {Pid2, _} ->
	    Pid1 ! C2,
	    Pid2 ! C1
    end.
