[![Build Status](https://travis-ci.org/parapluu/Concuerror.svg?branch=master)](https://travis-ci.org/parapluu/Concuerror)
[![Issues Ready for Development](https://badge.waffle.io/parapluu/concuerror.png?label=ready&title=Ready)](https://waffle.io/parapluu/concuerror)

# Concuerror

Concuerror is a stateless model checking tool for Erlang programs. It can be used to systematically test programs for concurrency errors, detect and report errors that only occur on few, specific schedulings or **verify** their absence.

## Supported OTP Releases

Concuerror's developers are always working with the latest otp/master branch
available on Github. Concuerror is also expected to work on all OTP releases
starting from and including *R16*. We use
[Travis](https://travis-ci.org/parapluu/Concuerror) to test:

* The *two last* minor versions of the 'current' major Erlang/OTP release
* The *last* minor version of older major releases

## How do I get Concuerror?

```bash
$ git clone https://github.com/parapluu/Concuerror.git
$ cd Concuerror
$ make -j
```

## How do I use Concuerror?

Bare minimum: `concuerror --help`

[Read how to use Concuerror!](http://parapluu.github.io/Concuerror/#how-do-i-use-concuerror)

## How do I contribute to Concuerror?

* Run the testsuite : `make tests`
* Dialyze           : `make dialyze`
* Cleanup           : `make clean`

Copyright and License
----------------------
Copyright (c) 2014-2017,
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
