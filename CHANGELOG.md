# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased](https://github.com/parapluu/Concuerror/tree/master)

### Added
- Total state space size and time to completion estimation
- `--first_process_errors_only` option
- Parts of [aronisstav/erlang-concurrency-litmus-tests](https://github.com/aronisstav/erlang-concurrency-litmus-tests) as a testsuite
- [Codecov](https://codecov.io/github/parapluu/Concuerror) code coverage tracking
- [contributor's guide](./CONTRIBUTING.md)
- [Github Pull Request and Issue templates](./.github/)

### Removed
- untested code for 'hijacking' processes (e.g. application_controller (#2))

### Changed
- progress bar format
- symbolic PIDs are now shown as "<symbol/last registered name>"
- report shows mailbox contents when a deadlock is detected
- significantly optimized DPOR implementations
- moved concuerror executable to /bin directory

### Fixed
- handling of stacktraces
- exclude instrumentation time from timeouts

## [0.18](https://github.com/parapluu/Concuerror/releases/tag/0.18) - 2018-02-20

### Added
- `--observers` option as a synonym of `--use_receive_patterns`
- Support for erlang:hibernate/3
- Support for more safe built-in operations
- A Changelog

### Changed
- Completely reworked the implementation of `--use_receive_patterns`
- `--use_receive_patterns` default is now `true`

### Fixed
- Handling of exit_signals sent to self() (#5)

## [0.17](https://github.com/parapluu/Concuerror/releases/tag/0.17) - 2017-10-17

## [0.16](https://github.com/parapluu/Concuerror/releases/tag/0.16) - 2016-10-25

## [0.15](https://github.com/parapluu/Concuerror/releases/tag/0.15) - 2016-08-29

## [0.14](https://github.com/parapluu/Concuerror/releases/tag/0.14) - 2015-06-10
