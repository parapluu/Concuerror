---
layout: page
permalink: /download/index.html
title: "Download Concuerror"
description: "Information on how to download Concuerror."
---

## Download

### Github

Concuerror's latest stable version is available on [Github](https://github.com/parapluu/Concuerror):

{% highlight bash %}
$ git clone https://github.com/parapluu/Concuerror.git
$ cd Concuerror
$ make
{% endhighlight %}

The preferred way to start concuerror is via the `bin/concuerror` escript.

### Hex.pm

Concuerror is also available via [Hex.pm](https://hex.pm/packages/concuerror).

This means that you can include it in your project using any of the
building tools that support Hex.pm dependencies.

### Supported OTP Releases

Concuerror's developers are always working with the latest otp/master branch
available on Github. Concuerror is also expected to work on all OTP releases
starting from and including **R17**[^1]. We use
[Travis](https://travis-ci.org/parapluu/Concuerror) to test:

* The *two last* minor versions of the 'current' major Erlang/OTP release
* The *last* minor version of older major releases

You can also find an older version of Concuerror [here](https://github.com/mariachris/Concuerror.git).

[^1]: R16 is also tested for minimal functionality.
