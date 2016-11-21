---
layout: post
title: "Testing Poolboy, Part 1: Concuerror basics"
category: tutorials
updated: 2016-05-11
---

In this tutorial we will use Concuerror to analyze a few tests written for the
[Poolboy](https://github.com/devinus/poolboy) library.

{:.no_toc}
Index
-----
1. This text will be replaced by the ToC, excluding the previous header (WOW!)
{:toc}

Setting up Concuerror, Poolboy and our first test
-------------------------------------------------

### Setting up Concuerror

[Download and make Concuerror as described in the Downloads section](/download)

For the rest of the tutorial we will assume that the `concuerror` executable
is in our path. For example, to get help for all of Concuerror's options we just
run:

{% highlight bash %}
$ concuerror -h
Usage: ./concuerror [-m <module>] [-t [<test>]] [-o [<output>]] [-h]
                    [--version] [--pa <pa>] [--pz <pz>] [-f <file>]
                    [-v <verbosity>] [-q] [--print_depth [<print_depth>]]
[...]
{% endhighlight %}

### Setting up Poolboy

We will be using version
[`1.2.2`](https://github.com/devinus/poolboy/releases/tag/1.2.2) of Poolboy.

{% highlight bash %}
$ git clone https://github.com/devinus/poolboy.git --branch 1.2.2
[...]
$ cd poolboy
poolboy $ make
==> poolboy (compile)
Compiled src/poolboy_worker.erl
Compiled src/poolboy_sup.erl
Compiled src/poolboy.erl
{% endhighlight %}

We will be using the sample worker used in Poolboy's own tests, so we should
`make` the tests as well:

{% highlight bash %}
poolboy $ make test
[...]
{% endhighlight %}

We don't care about the actual result of the tests, but we now have a
`.eunit` directory with `poolboy_test_worker.beam`.

#### No special compilation needed

Notice that we don't need to compile anything in a special way. Concuerror will
intercept calls to any module that is in Erlang's code path and instrument the
code before our test reaches it.

### Our first test

Concuerror explores all the interleavings of an arbitrary execution scenario of
a program with a single entry point. We will be extracting tests from [Poolboy's
own test
suite](https://github.com/devinus/poolboy/blob/1.2.2/test/poolboy_tests.erl).

Let's begin with an adapted version of the start/stop test, which we save as
[`poolboy_tests_1.erl`](https://gist.github.com/aronisstav/b67df16361cd9a2fa87e#file-poolboy_tests_1-erl):

{% gist aronisstav/b67df16361cd9a2fa87e %}

#### Using `.erl` files

We don't have to compile our test, as Concuerror can also analyze `.erl` files,
which are instrumented and compiled before the test starts.

We are now ready to...

Start testing!
--------------

We now have our application code compiled and ready to go, and have written a
small test. Next, we have to tell Concuerror to compile and load our test file
(using option `-f`) and then start testing from module
`poolboy_tests_1`, calling function `pool_startup`, which must have zero
arity:

{% highlight bash %}
poolboy $ concuerror -f poolboy_tests_1.erl -m poolboy_tests_1 -t pool_startup
{% endhighlight %}

Several lines should be printed on our screen. Let's focus on a few of them:

### The output file

{% highlight text %}
Concuerror started at 02 Jun 2014 09:00:00
Writing results in concuerror_report.txt
{% endhighlight %}

Concuerror mainly produces a textual log, saved by default as
`concuerror_report.txt`.  You can specify a different filename with the `-o`
option.

### Info messages

{% highlight text %}
Info: Instrumented poolboy_tests_1
{% endhighlight %}

Log messages tagged as *Info* are standard, normal operation messages.
Here, Concuerror reports that it compiled and instrumented our test file and
started to run the test.

{% highlight text %}
Info: Instrumented io_lib
Info: Instrumented poolboy
Info: Instrumented proplists
Info: Instrumented gen_server
[...]
{% endhighlight %}

Concuerror can detect which modules are being used by the test, and instruments
them automatically. You can see a few of them listed above. `io_lib` is also
included, for reasons that are not important to explain right now.

### Warning messages

{% highlight text %}
Warning: Concuerror does not fully support erlang:get_stacktrace/0 ...
{% endhighlight %}

Log messages tagged as *Warnings* are non-critical, notifying about weak
support for some feature or the use of an option that alters the output

### Tip messages

{% highlight text %}
Tip: An abnormal exit signal was sent to a process...
{% endhighlight %}

Log messages tagged as *Tips* are also non-critical, notifying of a
suggested refactoring or option that can be used to make testing more efficient.

### The interesting bits!

By default, Concuerror will stop exploration on the first error it encounters.
In this particular case, it seems that in the very first interleaving we managed
to trigger some behavior that the tool considers problematic.  If we take a look
at the output file `concuerror_report.txt`, we will see something like the
following:

{% highlight text %}
{% raw %}
* At step 49 process P.1 exited abnormally
    Reason:
      {{badmatch,
           {error,
               {'EXIT',
                   {undef,
                       [{poolboy_test_worker,start_link,
                            [[{name,{local,poolboy_test}},
                              {worker_module,poolboy_test_worker},
                              {size,1},
                              {max_overflow,...}]],
                            []},
                        {supervisor,do_start_child_i,3,
                            [{file,"supervisor.erl"},{line,330}]},
                        {supervisor,handle_call,3,[{file,[...]},{line,...}]},
                        {gen_server,handle_msg,5,[{file,...},{...}]},
                        {proc_lib,init_p_do_apply,3,[{...}|...]},
                        {concuerror_callback,process_top_loop,1,[...]}]}}}},
       [{poolboy,new_worker,1,[{file,"src/poolboy.erl"},{line,242}]},
[...]
{% endraw %}
{% endhighlight %}

### Using `-pa` to add directories in Erlang's code path

Whoops! We forgot to add the `poolboy_test_worker` module to Erlang's code
path. Concuerror uses the `--pa` option for this (notice the *two* dashes).

Running it again...

{% highlight bash %}
poolboy $ concuerror -f poolboy_tests_1.erl -m poolboy_tests_1 -t pool_startup \
 --pa .eunit
{% endhighlight %}

... yields:

{% highlight text %}
[...]
Tip: A process crashed with reason '{timeout, ...}'. This may happen when a call
  to a gen_server (or similar) does not receive a reply within some standard
  timeout. Use the '--after_timeout' option to treat after clauses that exceed some
  threshold as 'impossible'.  

Tip: An abnormal exit signal was sent to a process. This is probably the worst
  thing that can happen race-wise, as any other side-effecting operation races
  with the arrival of the signal. If the test produces too many interleavings
  consider refactoring your code.

Tip: A process crashed with reason 'shutdown'. This may happen when a supervisor
  is terminating its children. You can use '--treat_as_normal shutdown' if this is
  expected behavior.

Error: Stop testing on first error. (Check '-h keep_going').
[...]
{% endhighlight %}

Three tips and the same error. This time however, `concuerror_report.txt`
contains something like:

{% highlight text %}
{% raw %}
Erroneous interleaving 1:
* At step 52 process P exited abnormally
    Reason:
      {timeout,{gen_server,call,[P.1,stop]}}
    Stacktrace:
      [{gen_server,call,2,[{file,"gen_server.erl"},{line,182}]},
       {poolboy_tests_1,pool_startup,0,
                        [{file,"poolboy_tests_1.erl"},{line,8}]}]
* At step 76 process P.1.1.1 exited abnormally
    Reason:
      shutdown
    Stacktrace:
      []
* At step 85 process P.1.1 exited abnormally
    Reason:
      shutdown
    Stacktrace:
      [{proc_lib,exit_p,2,[{file,"proc_lib.erl"},{line,260}]}]
{% endraw %}
{% endhighlight %}

This behavior seems to be expected within the context of the test. Find out why
Concuerror reports it as problematic in the next part of this tutorial.

{:.no_toc}
# [<center><font color='green'>Continue to the next part!</font></center>]({% post_url 2014-06-03-poolboy-example-errors %})
