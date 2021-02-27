# **Graft**

A package management utility

---

[![DeepSourceA](https://deepsource.io/gh/johnsonjh/graft.svg/?label=active+issues)](https://deepsource.io/gh/johnsonjh/graft/?ref=repository-badge)
[![DeepSourceR](https://deepsource.io/gh/johnsonjh/graft.svg/?label=resolved+issues)](https://deepsource.io/gh/johnsonjh/graft/?ref=repository-badge)

---

## Introduction

**Graft** provides a mechanism for managing multiple packages under a single directory hierarchy.

It was inspired by both _Depot_ (Carnegie Mellon University) and _Stow_ (Bob Glickstein).

## Installation

### Module Dependencies

**Graft** has been written to ensure it uses Perl modules that are considered part of the core Perl distribution. However, it may be possible that you're using a home-grown installation of Perl, or some distribution that doesn't have the same Perl modules as the author's development environment.

If this is the case, you'll see compile failures for the following modules, if they are unavailable:

- `File::Basename`
- `Getopt::Long`

You will not be able to install **graft** until these modules are available.

You may also see run-time failures when using **graft** with `.graft-config` files, if the following modules are unavailable:

- `Compress::Raw::Zlib` _(used in install and delete modes)_
- `File::Copy` _(only used in install mode)_

If you don't have these modules and you do not intend to use `.graft-config` files, then you can continue to use **graft** without issue.

### Prepare

- `make -f Makefile.dist`

This generates a working copy of the `Makefile` for you to edit to suit your environment.

Edit `Makefile` appropriately.

You'll probably want to modify the following variables:

- `PACKAGEDIR = /usr/local/pkgs`
- `TARGETDIR = /usr/local`

The rest of the parameters are sensible defaults, but please change them to suit your needs. See the comments in the `Makefile` for directions or see the more detailed installation documentation in `doc/graft.html`.

### Build

- `make`

There should be no errors

### Install

- `make install`

This installs the **graft** executable and its documentation into the `$PACKAGEDIR/graft-2.16` directory which can then be _grafted_ into your `$TARGETDIR` directory:

- `/usr/local/pkgs/graft-2.16/bin/graft graft-2.16`

Or if you would prefer to create binary _RPM_ or _DEB_ files you can choose one of the following commands:

- `make rpm`
- `make deb`

Note that the installation directories for the _RPM_ and _DEB_ packages are hard-coded to:

- `/usr/bin`
- `/usr/share/man`
- `/usr/share/doc`

Then use the appropriate `rpm -[i|u] ...` or `dpkg install ...` command to install the package onto your system(s).

- Note that the _RPM_ package build was tested on a Debian system, so its success on a true _RPM_ based distro has not been verified.

## Documentation

See the man page and the files `./doc/graft.{html,pdf,ps,txt}` for expanded details on installation and usage.

## Author

- Peter Samuel <mailto:peter.r.samuel@gmail.com>

## Thanks

- Gordon Rowell
- Charles Butcher
- Charlie Brady
- Robert Maldon
- Matias Fonzo

## Homepage

- <http://peters.gormand.com.au/Home/tools/graft>
