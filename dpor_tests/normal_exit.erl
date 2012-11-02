-module(normal_exit).

-compile(export_all).

normal_exit() ->
    exit(normal).
