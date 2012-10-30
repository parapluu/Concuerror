-module(late_hope).

-compile(export_all).

late_hope() ->
    P = self(),
    Q = spawn(fun() -> ok end),
    spawn(fun() -> Q ! ignore,
                   P ! hope end),
    receive
        hope -> throw(saved)
    after
        100 -> hopeless
    end.
