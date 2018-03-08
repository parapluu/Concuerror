[![Travis][travis badge]][travis]
[![Coveralls][coveralls badge]][coveralls]
[![Erlang Versions][erlang versions badge]][travis]
[![Help wanted!][help wanted badge]][help wanted]
[![License][license badge]][license]

# Concuerror

Concuerror is a stateless model checking tool for Erlang programs. It can be used to systematically test programs for concurrency errors, detect and report errors that only occur on few, specific schedulings or **verify** their absence.

To find out more [visit the website!][website]

## How to build

* Compile             : `make`
* Run the testsuites  : `make tests tests-real`
* Run Dialyzer        : `make dialyze`
* Check code coverage : `make cover`
* Cleanup             : `make clean`

The preferred way to start concuerror is via the `bin/concuerror` escript.

## Is there a changelog?

[Yes!][changelog]

## Copyright and License

Copyright (c) 2014-2018,
Stavros Aronis (<aronisstav@gmail.com>) and
Kostis Sagonas (<kostis@cs.ntua.gr>).
All rights reserved

Copyright (c) 2011-2013,
Alkis Gotovos (<el3ctrologos@hotmail.com>),
Maria Christakis (<mchrista@softlab.ntua.gr>) and
Kostis Sagonas (<kostis@cs.ntua.gr>).
All rights reserved.

Concuerror is distributed under the Simplified BSD License.
Details can be found in the [LICENSE][license] file.

<!-- Links -->
[changelog]: ./CHANGELOG.md
[coveralls]: https://coveralls.io/github/parapluu/Concuerror
[help wanted]: https://github.com/parapluu/Concuerror/labels/help%20wanted
[license]: ./LICENSE
[travis]: https://travis-ci.org/parapluu/Concuerror
[website]: http://parapluu.github.io/Concuerror

<!-- Badges -->
[coveralls badge]: https://img.shields.io/coveralls/github/parapluu/Concuerror/master.svg?style=flat-square
[erlang versions badge]: https://img.shields.io/badge/erlang-R16B03%20to%2020.2-blue.svg?style=flat-square
[help wanted badge]: https://img.shields.io/waffle/label/parapluu/concuerror/help%20wanted.svg?label=help%20wanted&style=flat-square
[license badge]: https://img.shields.io/github/license/parapluu/Concuerror.svg?style=flat-square
[travis badge]: https://img.shields.io/travis/parapluu/Concuerror/master.svg?style=flat-square
