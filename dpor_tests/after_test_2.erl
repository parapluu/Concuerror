-module(after_test_2).

-compile(export_all).

after_test_2() ->
    Parent = self(),
    spawn(fun() -> Parent ! one end),
    receive
        two -> throw(two)
    after
        0 -> ok
    end,
    receive
        one -> ok
    after
        0 -> ok
    end,
    receive
        deadlock -> ok
    end.    
                    
                    
                    
            
