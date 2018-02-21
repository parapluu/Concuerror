[![Travis][travis badge]][travis]
[![Erlang Versions][erlang versions badge]][travis]
[![Help wanted!][help wanted badge]][help wanted]

# Concuerror

Concuerror is a stateless model checking tool for Erlang programs. It can be used to systematically test programs for concurrency errors, detect and report errors that only occur on few, specific schedulings or **verify** their absence.

To find out more [visit the website!][website]

## Is there a changelog?

[Yes!][changelog]

## How do I contribute to Concuerror?

* Run the testsuite : `make tests`
* Dialyze           : `make dialyze`
* Cleanup           : `make clean`

Copyright and License
----------------------
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
[help wanted]: https://github.com/parapluu/Concuerror/labels/help%20wanted
[license]: ./LICENSE
[travis]: https://travis-ci.org/parapluu/Concuerror
[website]: http://parapluu.github.io/Concuerror

<!-- Badges -->
[erlang versions badge]: https://img.shields.io/badge/erlang-R16B03%20to%2020.2-blue.svg?style=flat-square
[help wanted badge]: https://img.shields.io/waffle/label/parapluu/concuerror/help%20wanted.svg?label=help%20wanted&style=flat-square
[travis badge]: https://img.shields.io/travis/parapluu/Concuerror/master.svg?style=flat-square
