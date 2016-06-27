[![Build Status](https://travis-ci.org/parapluu/Concuerror.svg?branch=master)](https://travis-ci.org/parapluu/Concuerror)
[![Stories in Ready](https://badge.waffle.io/parapluu/concuerror.png?label=ready&title=Ready)](https://waffle.io/parapluu/concuerror)

Concuerror
==========

Concuerror is a systematic testing tool for concurrent Erlang programs.

Copyright and License
----------------------
Copyright (c) 2014-2016,
Stavros Aronis (<aronisstav@gmail.com>) and
Kostis Sagonas (<kostis@cs.ntua.gr>).
All rights reserved

Copyright (c) 2011-2013,
Alkis Gotovos (<el3ctrologos@hotmail.com>),
Maria Christakis (<mchrista@softlab.ntua.gr>) and
Kostis Sagonas (<kostis@cs.ntua.gr>).
All rights reserved.

Concuerror is distributed under the Simplified BSD License.
Details can be found in the LICENSE file.

How to
------

* Build Concuerror   : `make`
* Run Concuerror     : `concuerror --help`
* Run testsuite      : `make tests`
* Dialyze            : `make dialyze`
* Cleanup            : `make clean`

Supported OTP Releases
----------------------

Concuerror's developers are normally working with the latest otp/master branch
available on Github. Concuerror is also expected to work on all OTP releases
starting from and including *R16*. We use
[Travis](https://travis-ci.org/parapluu/Concuerror) to test:

* 'Current' major release: latest *two* minor versions
* Older major releases: *last* minor version
