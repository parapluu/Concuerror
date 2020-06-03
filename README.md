[![Travis][travis badge]][travis]
[![Codecov][codecov badge]][codecov]
[![Erlang Versions][erlang versions badge]][travis]

# Concuerror

Concuerror is a stateless model checking tool for Erlang programs. It can be used to systematically test programs for concurrency errors, detect and report errors that only occur on few, specific schedulings or **verify** their absence.

[Visit the website][website] for documentation, examples, tutorials, publications, and many more!

## How to build

* Compile             : `make`
* Build documentation : `make edoc`
* Run the testsuites  : `make tests tests-real tests-unit`
* Run Dialyzer        : `make dialyzer`
* Run Elvis           : `make lint`
* Check code coverage : `make cover`
* Cleanup             : `make clean`

The preferred way to start concuerror is via the `bin/concuerror` escript.

## Is there bash_completion?

[Yes!][bash_completion]

## Is there a changelog?

[Yes!][changelog]

## Copyright and License

Copyright (c) 2014-2020,
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
[bash_completion]: ./resources/bash_completion/concuerror
[changelog]: ./CHANGELOG.md
[codecov]: https://codecov.io/gh/parapluu/Concuerror
[license]: ./LICENSE
[travis]: https://travis-ci.org/parapluu/Concuerror
[website]: http://parapluu.github.io/Concuerror

<!-- Badges -->
[codecov badge]: https://codecov.io/gh/parapluu/Concuerror/branch/master/graph/badge.svg
[erlang versions badge]: https://img.shields.io/badge/erlang-19.0to%2023.0-blue.svg
[travis badge]: https://travis-ci.org/parapluu/Concuerror.svg?branch=master
