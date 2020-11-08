# How to make a release

Here is how to prepare a new release of Concuerror

## Decide release number

Follow semantic versioning (link in CHANGELOG.md)

`RELEASE=0.42`

## Fix and commit release number in CHNAGELOG.md

Format the UNRELEASED section in CHANGELOG.md

`## [0.42](https://github.com/parapluu/Concuerror/releases/tag/0.42) - 2042-11-20`

Then commit:

`git commit -m "Update CHANGELOG for release ${RELEASE}"`

The UNRELEASED section will be added back as the last step.

## Make the release tag

`git tag -a ${RELEASE} -m "Release ${RELEASE}" -s`

## Ensure you are logged in to Hex

`rebar3 hex user whoami`

If no info shown:

`rebar3 hex user auth`

## Push package to Hex

`rebar3 hex publish`

## Push tag to repository

`git push parapluu ${RELEASE}`

## Create release from tag

Copy the most recent section of the CHANGELOG as description and leave title empty

## Add a new UNRELEASED section in CHANGELOG.md

```
## [Unreleased](https://github.com/parapluu/Concuerror/tree/master)

### Added

### Removed

### Changed

### Fixed



```
