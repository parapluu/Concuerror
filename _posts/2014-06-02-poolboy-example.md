---
layout: post
title: "Application example: Poolboy (Part 1)"
category: tutorials
---

In this tutorial we will use Concuerror to analyze a few tests written for the
[Poolboy](https://github.com/devinus/poolboy) library.

{:.no_toc}

1. This text will be replaced by the ToC, excluding the previous header (WOW!)
{:toc}

Setting up Concuerror, Poolboy and our first test
-------------------------------------------------

### Setting up Concuerror

[Download and make Concuerror as described in the Downloads section](/download)

For the rest of the tutorial we will assume that the ```concuerror``` executable
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
[```1.2.1```](https://github.com/devinus/poolboy/releases/tag/1.2.1) of Poolboy:

{% highlight bash %}
$ git clone https://github.com/devinus/poolboy.git --branch 1.2.1
[...]
$ cd poolboy
poolboy $ make
==> poolboy (compile)
Compiled src/poolboy_worker.erl
Compiled src/poolboy_sup.erl
Compiled src/poolboy.erl
{% endhighlight %}

We will be using the sample worker used in Poolboy's own tests, so we should
```make``` the tests as well:

{% highlight bash %}
poolboy $ make test
[...]
{% endhighlight %}

We don't care about the actual result of the tests, but we now have a
```.eunit``` directory with ```poolboy_test_worker.beam```.

#### No special compilation is needed!

Notice that we don't need to compile anything in a special way! Concuerror will
intercept calls to any module that is in Erlang's code path and instrument the
code before our test reaches it.

### Setting up our first test

Concuerror explores all the interleavings of an arbitrary execution scenario of
a program with a single entry point. We will be extracting tests from [Poolboy's
own test
suite](https://github.com/devinus/poolboy/blob/1.2.1/test/poolboy_tests.erl).

Let's begin with an adapted version of the start/stop test, which we save as
[```poolboy_tests_1.erl```](https://gist.github.com/aronisstav/b67df16361cd9a2fa87e#file-poolboy_tests_1-erl):

{% gist aronisstav/b67df16361cd9a2fa87e %}

#### Also works for ```.erl``` files

We don't need to compile our test, as Concuerror can also include ```.erl```
modules, which it compiles using the Erlang compiler.

We are now ready to...

Start testing!
--------------

We now have our application code compiled and ready to go, and have written a
small test. Next, we have to tell Concuerror to compile and load our test file
(using option ```-f```) and then start testing from module
```poolboy_tests_1```, calling function ```pool_startup```, which must have zero
arity:

{% highlight bash %}
poolboy $ concuerror -f poolboy_tests_1.erl -m poolboy_tests_1 -t pool_startup
{% endhighlight %}

Several lines should be printed on our screen. Let's focus on a few of them:

### The output file

{% highlight text %}
Concuerror started at 02 Jun 2014 09:00:00
Writing results in results.txt
{% endhighlight %}

As of the writing of this tutorial, Concuerror mainly produces a textual log,
saved by default as ```concuerror_report.txt```. You can specify a different
filename with the ```-o``` option.

### Info messages

{% highlight text %}
Info: Instrumented poolboy_tests_1
{% endhighlight %}

Log messages tagged as ```Info``` are standard, normal operation messages.
Here, Concuerror reports that it compiled and instrumented our test file and
started to run the test!

{% highlight text %}
Info: Instrumented io_lib
Info: Instrumented poolboy
Info: Instrumented proplists
Info: Instrumented gen_server
[...]
{% endhighlight %}

Concuerror can detect which modules are being used by the test, and instruments
them automatically. You can see a few of them listed above. ```io_lib``` is also
included, for reasons that are not important to explain right now.

### Warning messages

{% highlight text %}
Warning: Concuerror does not fully support erlang:get_stacktrace/0 ...
{% endhighlight %}

Log messages tagged as ```Warnings``` are non-critical, notifying about weak
support for some feature or the use of an option that alters the output

### Tip messages

{% highlight text %}
Tip: An abnormal exit signal was sent to a process...
{% endhighlight %}

Log messages tagged as ```Tips``` are also non-critical, notifying of a
suggested refactoring or option that can be used to make testing more efficient.

### Error messages

Log messages tagged as ```Errors``` are critical and lead to the interruption of
the exploration. Our first test should crash here, with the following error:

{% highlight text %}
Error: The first interleaving of your test had errors. Check the output
file. You may then use -i to tell Concuerror to continue or use other options to
filter out the reported errors, if you consider them acceptable behaviours.
{% endhighlight %}

Concuerror is a tool for detecting *concurrency errors*. It seems that in the
first interleaving we managed to trigger some behaviour that the tool considers
problematic. If we take a look at the output file we will see something like the
following:

*Under progress!*

<!---
{% highlight text %}
Tralala
{% endhighlight %}
--->