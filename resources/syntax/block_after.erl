%%%----------------------------------------------------------------------
%%% File        : block_after.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Test block expression in after clause
%%% Created     : 3 Jan 2010
%%%----------------------------------------------------------------------

-module(block_after).

-export([block_after_test/0]).

block_after_test() ->
    receive
	_Any -> ok
    after 42 ->
	    foo,
	    bar
    end.
