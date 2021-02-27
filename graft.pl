#!xPERLx -w

# $Id: graft.pl,v 2.16 2018/04/16 15:01:09 psamuel Exp $
#
# Virtual package installer.
#
# Author: Peter Samuel <peter.r.samuel@gmail.com>

###########################################################################
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA, or download it
# from the Free Software Foundation's web site:
#
#	http://www.gnu.org/copyleft/gpl.html
#	http://www.gnu.org/copyleft/gpl.txt
#

###########################################################################
#
# System defaults

use strict;
use File::Basename;
use Getopt::Long qw (:config bundling no_ignore_case);

$| = 1;

my %config;    # Configuration and other runtime values
my %option;    # Command line options

init();        # Argument parsing and set up

###########################################################################
#
# Process each package provided on the command line

foreach my $package (@ARGV) {
    $package = stripslashes($package);

    # Complain if the package directory is empty

    if ( $package eq '' ) {
        message(
            tag => 'ERROR',
            msg => 'Package directory cannot be empty.',
        );

        $config{errorStatus} = 3;
        next;
    }

    # If the package is not fully qualified, prepend it with the
    # default package target.

    unless ( fullyqualified($package) ) {
        $package = $config{packageDefault} . '/' . $package;
    }

    # Complain if the package directory does not exist.

    unless ( -d $package ) {
        message(
            tag => 'ERROR',
            msg => "Package directory $package does not exist.",
        );

        $config{errorStatus} = 3;
        next;
    }

    if ( exists $option{stow} ) {

        # Stow/Depot compatibility mode. Stow and Depot (in their
        # default modes) assume that packages are installed in
        # /dir/stow/pkg-nn or /dir/depot/pkg-nn. They also assume the
        # symbolic links will be created in /dir. Graft's Stow/Depot
        # compatibility mode takes a single argument as the
        # installation directory of the package and grafts it into the
        # directory which is the dirname of the dirname of the
        # argument. (That's not a typo! That really _is_ two lots of
        # dirname operations).

        $config{target} = dirname dirname $package;
    }

    if ( exists $option{install} ) {
        message(
            tag => 'Installing',
            msg => "links to $package in $config{target}"
        ) if $config{verbose};

        logger(
            tag => 'I',
            log => [ $package, $config{target} ],
        );

        install(
            source => $package,
            target => $config{target},
        );

        next;
    }

    if ( exists $option{delete} ) {
        message(
            tag => 'Uninstalling',
            msg => "links from $config{target} to $package",
        ) if $config{verbose};

        logger(
            tag => 'D',
            log => [ $package, $config{target} ],
        );

        uninstall(
            source => $package,
            target => $config{target},
        );

        next;
    }

    if ( exists $option{prune} ) {
        message(
            tag => 'Pruning',
            msg => "files in $config{target} which conflict with $package",
        ) if $config{verbose};

        # Pruning is a special case of deletion

        logger(
            tag => 'P',
            log => [ $package, $config{target} ],
        );

        uninstall(
            source => $package,
            target => $config{target},
        );

        next;
    }
}

exit $config{errorStatus};

###########################################################################

sub cat {

    # Open the named file and return a hash of the lines in the file.
    # Duplicate entries are handled automatically by the hash.

    my $file = shift;
    my %hash;

    if ( defined open FILE, $file ) {
        while (<FILE>) {
            chomp;
            ++$hash{$_};
        }

        close FILE;
        return %hash;
    }
    else {
        message(
            tag => 'ERROR',
            msg => "Could not open $file for reading: $!."
        );

        return undef;
    }
}

sub checksum {

    # Perform a CRC32 checksum on the named file

    my $file = shift;
    my $buffer;
    my $crc = 0;

    open FILE, $file
      or die "Failed to open $file for checksum calculation: $!\n";

    while ( read( FILE, $buffer, 65536, 0 ) ) {
        $crc = crc32( $buffer, $crc );
    }

    close FILE;

    return $crc;
}

sub directories {

    # Return a hash of directories beneath the current directory.
    # The special directories '.' and '..' will not be returned.
    # Symbolic links to directories will be treated as links and
    # NOT as directories.

    my $dir = shift;
    my %dirs;

    return %dirs unless ( -d $dir );

    if ( opendir DIR, $dir ) {
        foreach ( readdir DIR ) {
            next if /^\.\.?$/;    # ignore '.' and '..'
            next unless -d;       # ignore non directories
            next if -l;           # ignore symbolic links to directories
            ++$dirs{ basename $_};
        }

        closedir DIR;
        return %dirs;
    }
    else {
        message(
            tag => 'ERROR',
            msg => "Could not open directory $dir for reading: $!"
        );

        return undef;
    }
}

sub files {

    # Return a hash of non directories beneath the named directory.
    # Symbolic links to directories will also be returned.

    my $dir = shift;
    my %files;

    return %files unless ( -d $dir );

    if ( opendir DIR, $dir ) {
        foreach ( readdir DIR ) {
            next if ( -d and not -l );    # ignore real directories,
                                          # symlinks to directories are OK.
            ++$files{ basename $_};
        }

        closedir DIR;
        return %files;
    }
    else {
        message(
            tag => 'ERROR',
            msg => "Could not open directory $dir for reading: $!",
        );

        return undef;
    }
}

sub fullyqualified {

    # return true if the argument is a fully qualified directory name

    my $string = shift;

    return $string =~ /^\// ? 1 : 0;
}

sub init {

    # Die now if the OS does not support symbolic links!

    ( eval 'symlink "", "";', $@ eq '' )
      or die "Your operating system does not support symbolic links.\n";

    # If Compress::Raw::Zlib::crc32() is available, use it. This will be
    # used for calculating CRC32 checksums for configuration files flagged
    # by the existence of a xGRAFT-CONFIGx file. If the module is not
    # available then this feature will be disabled. Error messages will be
    # displayed later and only if relevant: IE a xGRAFT-CONFIGx file is
    # present.
    #
    # Note that we need to use "require" followed by "import" instead of
    # "use" to avoid compile time failures.
    #
    # use == BEGIN { require Module; import Module LIST; }

    eval { require Compress::Raw::Zlib; };

    unless ($@) {
        import Compress::Raw::Zlib;
        eval 'Compress::Raw::Zlib::crc32("")';

        unless ($@) {

            # The module exists and it has the crc32() function

            $config{HasCRC32} = 1;

            # Is File::Copy::copy() available?

            eval { require File::Copy; };

            unless ($@) {
                import File::Copy;
                eval 'File::Copy::copy("", ".")';

                unless ($@) {

                    # The module exists and has the copy() function

                    $config{HasCopy} = 1;
                }
                else {
                    # The module exists but does not have the copy() function

                    delete $config{HasCopy};
                }
            }
            else {
                # The module does not exist

                delete $config{HasCopy};
            }
        }
        else {
            # The module exists but does not have the crc32() function

            delete $config{HasCRC32};
        }
    }
    else {
        # The module does not exist.

        delete $config{HasCRC32};
    }

    ###########################################################################
    #
    # System defaults

    # Get the RCS revision number. If the file has been checked out for
    # editing, add '+' to the revision number to indicate its state. The
    # revision number is written to the log file for every graft operation.
    # This is only used for testing new development versions.

    my @rcsid =
      split( ' ', '$Id: graft.pl,v 2.16 2018/04/16 15:01:09 psamuel Exp $' );

    $config{version} = $rcsid[2];
    $config{version} .= '+' if ( scalar @rcsid == 9 );

    $config{progname}       = basename $0;    # this program's name
    $config{exitOnConflict} = 1;              # exit on conflicts - install only

    # These initialisation values are in quotes to ensure the perl -c check
    # passes. They are text values of the form xTEXTx which will be
    # replaced by sed as part of the make process.

    # Are superuser privileges required?
    $config{superuser} = 'xSUPERUSERx';

    # Preserve directory permissions on newly created directories?
    # Only if SUPERUSER is set to 1 in the Makefile.
    $config{preservePermissions} = 'xPRESERVEPERMSx';
    $config{preservePermissions} = 0 unless ( $config{superuser} );

    # Remove empty directories after an ungraft and remove conflicting
    # objects discovered during a prune?
    $config{deleteObjects} = 'xDELETEOBJECTSx';

    # default location of log file
    $config{logfile} = 'xLOGFILEx';

    # names of special graft control files
    $config{graftIgnore}  = 'xGRAFT-IGNOREx';
    $config{graftExclude} = 'xGRAFT-EXCLUDEx';
    $config{graftInclude} = 'xGRAFT-INCLUDEx';
    $config{graftConfig}  = 'xGRAFT-CONFIGx';

    # Should graft always ignore files and/or directories
    # specified by $config{graftNever}?
    $config{neverGraft} = 'xNEVERGRAFTx';

    # default package and target directories
    $config{packageDefault} = 'xPACKAGEDIRx';
    $config{target}         = 'xTARGETDIRx';
    $config{targetTop}      = $config{target};

    # config file suffix
    $config{configSuffix} = 'xCONFIG-SUFFIXx';

    # pruned file suffix
    $config{prunedSuffix} = 'xPRUNED-SUFFIXx';

    # Verbosity is zero for the moment. Set by user with -v or -V options.
    $config{verbose}     = 0;
    $config{veryVerbose} = 0;

    ###########################################################################
    #
    # Argument parsing

    usage()
      unless GetOptions(
        C     => sub { $option{neverGraft}          = 1 },
        D     => sub { $option{deleteObjects}       = 1 },
        d     => sub { $option{delete}              = 1 },
        i     => sub { $option{install}             = 1 },
        L     => sub { $config{locations}           = 1 },
        'l=s' => sub { $option{logfile}             = $_[1] },
        n     => sub { $option{noexec}              = 1 },
        P     => sub { $option{preservePermissions} = 1 },
        p     => sub { $option{prune}               = 1 },
        'r=s' => sub { $option{rootdir}             = $_[1] },
        s     => sub { $option{stow}                = 1 },
        't=s' => sub { $option{target}              = $_[1] },
        u     => sub { $option{superuser}           = 1 },
        V     => sub { $option{veryVerbose}         = 1 },
        v     => sub { $option{verbose}             = 1 },
      );

    # -L wins every time

    show_locations() if ( exists $config{locations} );

    # User must supply one of the -d, -i or -p options

    usage()
      unless ( exists $option{delete}
        or exists $option{install}
        or exists $option{prune} );

    # Options -d, -i and -p are mutually exclusive

    usage()
      if ( ( exists $option{delete} and exists $option{install} )
        or ( exists $option{delete}  and exists $option{prune} )
        or ( exists $option{install} and exists $option{prune} ) );

    if ( $config{superuser} ) {

        # Silently ignore -P if the effective user is not root

        delete $option{preservePermissions} if ($>);

        # -P is only useful with -i

        usage()
          if ( exists $option{preservePermissions}
            and ( exists $option{delete} or exists $option{prune} ) );

        # -P and -u are mutally exclusive

        usage()
          if (  exists $option{preservePermissions}
            and exists $option{superuser} );
    }

# If there are objects to consider for ignoring automatically, -C is only useful with -i.

    unless ( 'xGRAFT-NEVERx' eq '' ) {
        usage()
          if ( exists $option{neverGraft}
            and ( exists $option{delete} or exists $option{prune} ) );
    }
    else {
        delete $option{neverGraft};
    }

    # -D is only useful with -d or -p

    usage() if ( exists $option{deleteObjects} and exists $option{install} );

    # -s and -t are mutually exclusive

    usage() if ( exists $option{stow} and exists $option{target} );

    ###########################################################################
    #
    # Argument processing

    if ( exists $option{rootdir} ) {

        # Only the superuser can choose a root directory. Needs to be
        # enforced for noexec mode so that the output is correct.

        die "Sorry, only the superuser can specify a root directory.\n"
          unless ( $> == 0 );

        # New root directory must be fully qualified and it must also exist

        $config{rootdir} = $option{rootdir};

        unless ( fullyqualified( $config{rootdir} ) ) {
            message(
                tag => 'ERROR',
                msg =>
                  "Root directory $config{rootdir} is not fully qualified.",
            );

            usage();
        }

        unless ( -d $config{rootdir} ) {
            message(
                tag => 'ERROR',
                msg => "Root directory $config{rootdir} does not exist.",
            );

            usage();
        }

        # Everything below this point will be relative to the "new" root
        # directory - including the log file location!

        chroot $config{rootdir}
          or die "Failed to set new root directory to $config{rootdir}: $!\n";

        # Failsafe chdir to make sure all is well.

        chdir '/'
          or die "Failed to chdir to new root directory $config{rootdir}: $!\n";
    }

    if ( exists $option{target} ) {

        # Target directory must be fully qualified and it must also exist

        $config{target}    = $option{target};
        $config{targetTop} = $config{target};

        unless ( fullyqualified( $config{target} ) ) {
            message(
                tag => 'ERROR',
                msg =>
                  "Target directory $config{target} is not fully qualified.",
            );

            usage();
        }

        unless ( -d $config{target} ) {
            message(
                tag => 'ERROR',
                msg => "Target directory $config{target} does not exist.",
            );

            usage();
        }
    }

    if ( exists $option{noexec} ) {
        ++$config{verbose};             # -n implies verbose
        ++$config{veryVerbose};         # -n implies very verbose
        $config{exitOnConflict} = 0;    # no need to exit on conflicts
    }
    else {
        # Logfile must be fully qualified and its directory must exist

        if ( exists $option{logfile} ) {
            $config{logfile} = $option{logfile};   # User supplied log file name
        }

        unless ( fullyqualified( $config{logfile} ) ) {
            message(
                tag => 'ERROR',
                msg => "Log file $config{logfile} is not fully qualified.",
            );

            usage();
        }

        my $dir = dirname $config{logfile};

        unless ( -d $dir ) {
            message(
                tag => 'ERROR',
                msg => "Cannot create log file $config{logfile}. No such"
                  . " directory as $dir.",
            );

            usage();
        }

        # How verbose is verbose?

        ++$config{verbose}
          if ( exists $option{verbose} or exists $option{veryVerbose} );
        ++$config{veryVerbose} if ( exists $option{veryVerbose} );
    }

    usage() unless ( scalar @ARGV );    # Need package arguments

    # We do the toggles last. Otherwise the command line arguments would
    # affect the usage message which could confuse the punters. The toggles
    # could be coded as ternary operators but these are more readable and
    # obvious to me :)

    # Only worry about toggling $config{neverGraft} if there are objects to
    # consider for ignoring automatically. If there are no objects then
    # force it to 0.

    unless ( 'xGRAFT-NEVERx' eq '' ) {
        if ( exists $option{neverGraft} )    # Toggle never graft flag
        {
            if ( $config{neverGraft} ) {
                $config{neverGraft} = 0;     # Was set to 1 in Makefile
            }
            else {
                $config{neverGraft} = 1;     # Was set to 0 in Makefile
            }
        }

        if ( $config{neverGraft} ) {

            # List of files and/or directories graft may never examine.

            map { ++$config{graftNever}{$_} } qw ( xGRAFT-NEVERx );
        }
    }
    else {
        $config{neverGraft} = 0;
        %{ $config{graftNever} } = ();
    }

    if ( exists $option{deleteObjects} )    # Toggle delete directories flag
    {
        if ( $config{deleteObjects} ) {
            $config{deleteObjects} = 0;     # Was set to 1 in Makefile
        }
        else {
            $config{deleteObjects} = 1;     # Was set to 0 in Makefile
        }
    }

    if ( $config{superuser} ) {
        if (
            exists $option{preservePermissions}
          )                                 # Toggle preserve permissions flag
        {
            if ( $config{preservePermissions} ) {
                $config{preservePermissions} = 0;    # Was set to 1 in Makefile
            }
            else {
                $config{preservePermissions} = 1;    # Was set to 0 in Makefile
            }
        }
    }

    # Disable superuser privileges if superuser was set to 1 in Makefile
    # and user specified -u on the command line.

    $config{superuser} = 0
      if ( exists $option{superuser} and $config{superuser} );

    if ( $config{superuser} ) {

        # Everything beyond this point requires superuser
        # privileges unless -n or -u was specified on the command line.

        die "Sorry, only the superuser can install or delete packages.\n"
          unless ( $> == 0 or exists $option{noexec} );
    }

    # If everything succeeds, then exit with status 0. If a CONFLICT
    # arises, then exit with status 1. If the user supplied invalid command
    # line arguments the program has already exited with status 2. If one
    # or more packages does not exist then exit with status 3.

    $config{errorStatus} = 0;    # Set default exit status
}

sub install {

    # For each directory in $source, create a directory in $target.
    # For each file in $source, create a symbolic link from $target.

    my %arg = @_;

    my $source = $arg{source};
    my $target = $arg{target};

    my %excludes;
    my %includes;

    unless ( chdir $source ) {
        message(
            tag => 'ERROR',
            msg => "Could not change directories to $source: $!",
        );

        return;
    }

    message(
        tag => 'Processing',
        msg => "$source",
    ) if $config{verbose};

    # Get a list of files and directories in the source and target directory.

    my %sfiles       = files($source);
    my %tfiles       = files($target);
    my %sdirectories = directories($source);
    my %tdirectories = directories($target);

    # Flag any precedence conflicts in control files. In decending order of
    # precedence:
    #
    # xGRAFT-IGNOREx > xGRAFT-EXCLUDEx > xGRAFT-INCLUDEx > xGRAFT-CONFIGx.

    if ( exists $sfiles{ $config{graftIgnore} } ) {
        if ( exists $sfiles{ $config{graftExclude} } ) {
            message(
                tag => 'IGNORE',
                msg => "exclude file $source/$config{graftExclude}, overridden"
                  . " by bypass file $source/$config{graftIgnore}"
            ) if $config{veryVerbose};

            delete $sfiles{ $config{graftExclude} };
        }

        if ( exists $sfiles{ $config{graftInclude} } ) {
            message(
                tag => 'IGNORE',
                msg => "include file $source/$config{graftInclude}, overridden"
                  . " by bypass file $source/$config{graftIgnore}"
            ) if $config{veryVerbose};

            delete $sfiles{ $config{graftInclude} };
        }

        if ( exists $sfiles{ $config{graftConfig} } ) {
            message(
                tag => 'IGNORE',
                msg => "config file $source/$config{graftConfig}, overridden"
                  . " by bypass file $source/$config{graftIgnore}"
            ) if $config{veryVerbose};

            delete $sfiles{ $config{graftConfig} };
        }
    }
    elsif ( exists $sfiles{ $config{graftExclude} } ) {
        if ( exists $sfiles{ $config{graftInclude} } ) {
            message(
                tag => 'IGNORE',
                msg => "include file $source/$config{graftInclude}, overridden"
                  . " by exclude file $source/$config{graftExclude}"
            ) if $config{veryVerbose};

            delete $sfiles{ $config{graftInclude} };
        }

        if ( exists $sfiles{ $config{graftConfig} } ) {
            message(
                tag => 'IGNORE',
                msg => "config file $source/$config{graftConfig}, overridden"
                  . " by exclude file $source/$config{graftExclude}"
            ) if $config{veryVerbose};

            delete $sfiles{ $config{graftConfig} };
        }
    }
    elsif ( exists $sfiles{ $config{graftInclude} } ) {
        if ( exists $sfiles{ $config{graftConfig} } ) {
            message(
                tag => 'IGNORE',
                msg => "config file $source/$config{graftConfig}, overridden"
                  . " by include file $source/$config{graftInclude}"
            ) if $config{veryVerbose};

            delete $sfiles{ $config{graftConfig} };
        }
    }

    if ( exists $sfiles{ $config{graftConfig} } ) {
        unless ( exists $config{HasCRC32} ) {
            die "Cannot process $sfiles{$config{graftConfig}} during install"
              . " because Compress::Raw::Zlib::crc32() is unavailable\n";
        }

        unless ( exists $config{HasCopy} ) {
            die "Cannot process $sfiles{$config{graftConfig}} because"
              . " File::Copy::copy() is unavailable\n";
        }
    }

    # Don't process this directory if a xGRAFT-IGNOREx file exists.

    if ( exists $sfiles{ $config{graftIgnore} } ) {
        message(
            tag => 'BYPASS',
            msg => "$source - $config{graftIgnore} file found",
        ) if $config{veryVerbose};

        return;
    }

    # Grab the contents of the xGRAFT-EXCLUDEx or xGRAFT-INCLUDE files if
    # they exist. They'll be used later if relevant.

    %excludes = cat( $config{graftExclude} )
      if ( exists $sfiles{ $config{graftExclude} } );
    %includes = cat( $config{graftInclude} )
      if ( exists $sfiles{ $config{graftInclude} } );

    # Process each file in the current source directory

    foreach my $file ( keys %sfiles ) {

        # Don't graft control files

        next if ( $file eq $config{graftExclude} );
        next if ( $file eq $config{graftInclude} );
        next if ( $file eq $config{graftConfig} );

        if ( exists $sfiles{ $config{graftExclude} } ) {
            if ( exists $excludes{$file} ) {
                message(
                    tag => 'EXCLUDE',
                    msg => "file $source/$file - listed in"
                      . " $source/$config{graftExclude}",
                ) if $config{veryVerbose};

                next;
            }

            # File is not specifically excluded so make the symlink

            mklink( $source, $target, $file );
            next;
        }

        if ( exists $sfiles{ $config{graftInclude} } ) {
            if ( exists $includes{$file} ) {
                if ( exists $config{graftNever}{$file} ) {
                    message(
                        tag => 'INCLUDE',
                        msg => "overriding never include directive"
                          . " for file $source/$file listed in"
                          . " $source/$config{graftInclude}",
                    ) if $config{veryVerbose};

                    mklink( $source, $target, $file );
                }
                else {
                    message(
                        tag => 'INCLUDE',
                        msg => "file $source/$file - listed in"
                          . " $source/$config{graftInclude}",
                    ) if $config{veryVerbose};

                    mklink( $source, $target, $file );
                }
            }
            else {
                message(
                    tag => 'IGNORE',
                    msg => "file $source/$file - not listed in"
                      . " $source/$config{graftInclude}",
                ) if $config{veryVerbose};
            }

            next;
        }

        if ( exists $config{graftNever}{$file} ) {
            message(
                tag => 'EXCLUDE',
                msg => "file $source/$file will never be grafted",
            ) if $config{veryVerbose};

            next;
        }

        if ( exists $sfiles{ $config{graftConfig} } ) {
            mkcopy( $source, $target, $file );
            next;
        }

        # Make the link as there is no control file or other explicit
        # directive for this file.

        mklink( $source, $target, $file );
    }

    # Process each directory in the current source directory

    foreach my $dir ( sort keys %sdirectories ) {
        if ( -f "$source/$dir/$config{graftIgnore}" ) {

            # Explicitly ignore directories with xGRAFT-IGNOREx files.
            # Avoids making empty directories in the target.

          # Flag any precedence conflicts in control files for the
          # sub-directory. In decending order of precedence:
          #
          # xGRAFT-IGNOREx > xGRAFT-EXCLUDEx > xGRAFT-INCLUDEx > xGRAFT-CONFIGx.

            if ( -f "$source/$dir/$config{graftExclude}" ) {
                message(
                    tag => 'IGNORE',
                    msg =>
"exclude file $source/$dir/$config{graftExclude}, overridden"
                      . " by bypass file $source/$dir/$config{graftIgnore}"
                ) if $config{veryVerbose};
            }

            if ( -f "$source/$dir/$config{graftInclude}" ) {
                message(
                    tag => 'IGNORE',
                    msg =>
"include file $source/$dir/$config{graftInclude}, overridden"
                      . " by bypass file $source/$dir/$config{graftIgnore}"
                ) if $config{veryVerbose};
            }

            if ( -f "$source/$dir/$config{graftConfig}" ) {
                message(
                    tag => 'IGNORE',
                    msg =>
"config file $source/$dir/$config{graftConfig}, overridden"
                      . " by bypass file $source/$dir/$config{graftIgnore}"
                ) if $config{veryVerbose};
            }

            message(
                tag => 'BYPASS',
                msg => "$source/$dir - $config{graftIgnore} file found",
            ) if $config{veryVerbose};

            next;
        }

        if ( exists $sfiles{ $config{graftExclude} } ) {
            if ( exists $excludes{$dir} ) {
                message(
                    tag => 'EXCLUDE',
                    msg => "directory $source/$dir - listed in"
                      . " $source/$config{graftExclude}",
                ) if $config{veryVerbose};

                next;
            }

            mkdirectory( $source, $target, $dir );

            # Recursively descend into this directory and repeat the process.

            install(
                source => "$source/$dir",
                target => "$target/$dir",
            );

            next;
        }

        if ( exists $sfiles{ $config{graftInclude} } ) {
            if ( exists $includes{$dir} ) {
                if ( exists $config{graftNever}{$dir} ) {
                    message(
                        tag => 'INCLUDE',
                        msg => "overriding never include directive"
                          . " for directory $source/$dir listed in"
                          . " $source/$config{graftInclude}",
                    ) if $config{veryVerbose};

                    mkdirectory( $source, $target, $dir );

                    # Recursively descend into this directory and repeat
                    # the process.

                    install(
                        source => "$source/$dir",
                        target => "$target/$dir",
                    );
                }
                else {
                    message(
                        tag => 'INCLUDE',
                        msg => "directory $source/$dir - listed in"
                          . " $source/$config{graftInclude}",
                    ) if $config{veryVerbose};

                    mkdirectory( $source, $target, $dir );

                    # Recursively descend into this directory and repeat
                    # the process.

                    install(
                        source => "$source/$dir",
                        target => "$target/$dir",
                    );
                }
            }
            else {
                message(
                    tag => 'IGNORE',
                    msg => "directory $source/$dir - not listed in"
                      . " $source/$config{graftInclude}",
                ) if $config{veryVerbose};
            }

            next;
        }

        if ( exists $config{graftNever}{$dir} ) {
            message(
                tag => 'EXCLUDE',
                msg => "directory $source/$dir will never be grafted",
            ) if $config{veryVerbose};

            next;
        }

        # Make the directory as there is no control file or other explicit
        # directive for this file.

        mkdirectory( $source, $target, $dir );

        # Recursively descend into this directory and repeat the process.

        install(
            source => "$source/$dir",
            target => "$target/$dir",
        );
    }
}

sub logger {
    return if ( exists $option{noexec} );    # Nothing to log in noexec mode

    # Write a message in the log file. Prepend each message with the system
    # time and program version number.

    my %msg = @_;

    $msg{tag} = sprintf( "%s\t%s\t%s", time, $config{version}, $msg{tag} );

    if ( defined open LOGFILE, ">> $config{logfile}" ) {
        print LOGFILE join( "\t", $msg{tag}, @{ $msg{log} } ), "\n";
        close LOGFILE;
    }
    else {
        message(
            tag => 'ERROR',
            msg => "Could not open log file $config{logfile}: $!.",
        );

        $config{errorStatus} = 4 unless ( $config{errorStatus} );
    }
}

sub message {

    # Display a message on STDOUT or STDERR

    my %msg = @_;

    my $tagLength = 13;    # Length of longest tag word.

    if (   $msg{tag} =~ /^CONFLICT/
        or $msg{tag} =~ /^ERROR/ )
    {
        warn
          sprintf( "%-${tagLength}.${tagLength}s ", $msg{tag} ),
          $msg{msg},
          "\n";
    }
    else {
        print
          sprintf( "%-${tagLength}.${tagLength}s ", $msg{tag} ),
          $msg{msg},
          "\n";
    }
}

sub mkcopy {
    my $source = shift;
    my $target = shift;
    my $file   = shift;

    unless ( -e "$target/$file" ) {

        # Target does not exist. Make the copy.

        message(
            tag => 'COPY',
            msg => "$source/$file to $target/$file",
        ) if $config{veryVerbose};

        # Perform the copy. If -n was specified, don't actually create
        # anything, just report the action and move to the next file.

        unless ( exists $option{noexec} ) {
            copy( "$source/$file", "$target/$file" )
              or die "Failed to copy $source/$file to $target/$file: $!\n";

            if ( $config{preservePermissions} and $config{superuser} ) {

                # Only do this if superuser privileges are on.
                # Otherwise it's bound to fail.

                my (
                    undef, undef, $mode, undef,  $uid,
                    $gid,  undef, undef, $atime, $mtime
                ) = stat "$source/$file";

                chmod $mode, "$target/$file"
                  or die "Could not create $target/$file: $!\n";

                chown $uid, $gid, "$target/$file"
                  or die "Could not set ownership on $target/$file: $!\n";

                utime $atime, $mtime, "$target/$file"
                  or die
"Could not set access and modification times on $target/$file: $!\n";

                unless ( exists $option{rootdir} ) {
                    system( "/bin/ls", "-l", "$target/$file" );
                }
                else {
                 # /bin/ls probably won't be available after chroot().
                 # Do it the hard way. Note that permissions will be
                 # displayed in octal and the user and group values will
                 # be numeric because access to /etc/passwd will
                 # probably be unavailable.
                 #
                 # For example:
                 #
                 #	  0100644 1 1000 1000 56405 Mon Mar 12 16:25:41 2018 graft.pl

                    my @S = stat "$target/$file";
                    printf(
                        "0%o %ld %ld %ld %ld %s %s\n",
                        $S[2], $S[3], $S[4], $S[5], $S[7],
                        scalar localtime $S[9],
                        "$target/$file"
                    );
                }
            }
        }

        return;
    }

    if ( -l "$target/$file" ) {

        # Target is a symbolic link. Is it a symlink to the source file or
        # somewhere else?

        my $link = readlink "$target/$file";

        if ( "$source/$file" eq $link ) {

            # We want to make the target consistent in the case of
            # xGRAFT-CONFIGx so we'll remove the symlink and then make a
            # copy.

            message(
                tag => 'COPY_NEW',
                msg => "Replace symlink $source/$file to"
                  . " $target/$file with a copy",
            ) if $config{veryVerbose};

            # Perform the delete & copy. If -n was specified, don't actually
            # create anything, just report the action.

            unless ( exists $option{noexec} ) {
                unlink "$target/$file"
                  or die "Could not unlink $target/$file: $!\n";

                copy( "$source/$file", "$target/$file" )
                  or die "Failed to copy $source/$file to $target/$file: $!\n";

                if ( $config{preservePermissions} and $config{superuser} ) {

                    # Only do this if superuser privileges are on.
                    # Otherwise it's bound to fail.

                    my (
                        undef, undef, $mode, undef,  $uid,
                        $gid,  undef, undef, $atime, $mtime
                    ) = stat "$source/$file";

                    chmod $mode, "$target/$file"
                      or die "Could not create $target/$file: $!\n";

                    chown $uid, $gid, "$target/$file"
                      or die "Could not set ownership on $target/$file: $!\n";

                    utime $atime, $mtime, "$target/$file"
                      or die
"Could not set access and modification times on $target/$file: $!\n";
                }
            }

        }
        else {
            my $source_crc = checksum("$source/$file");
            my $target_crc = checksum("$target/$file");

            if ( $source_crc == $target_crc ) {
                message(
                    tag => 'NOP',
                    msg => "$target/$file is not linked to"
                      . " $source/$file but contents match",
                ) if $config{veryVerbose};
            }
            else {
                message(
                    tag => 'COPY_NEW',
                    msg => "$source/$file to"
                      . " $target/${file}$config{configSuffix}",
                ) if $config{veryVerbose};

               # Perform the copy. If -n was specified, don't actually
               # create anything, just report the action.
               #
               # NOTE - this will clobber any existing filexCONFIG-SUFFIXx file!

                unless ( exists $option{noexec} ) {
                    copy( "$source/$file",
                        "$target/${file}$config{configSuffix}" )
                      or die
"Failed to copy $source/$file to $target/${file}$config{configSuffix}: $!\n";

                    if ( $config{preservePermissions} and $config{superuser} ) {

                        # Only do this if superuser privileges are on.
                        # Otherwise it's bound to fail.

                        my (
                            undef, undef, $mode, undef,  $uid,
                            $gid,  undef, undef, $atime, $mtime
                        ) = stat "$source/$file";

                        chmod $mode, "$target/${file}$config{configSuffix}"
                          or die
"Could not create $target/${file}$config{configSuffix}: $!\n";

                        chown $uid, $gid,
                          "$target/${file}$config{configSuffix}"
                          or die
"Could not set ownership on $target/${file}$config{configSuffix}: $!\n";

                        utime $atime, $mtime,
                          "$target/${file}$config{configSuffix}"
                          or die
"Could not set access and modification times on $target/${file}$config{configSuffix}: $!\n";
                    }
                }
            }
        }

        return;
    }

    if ( -f "$target/$file" ) {

        # Target is a regular file. Does it match the source file or not?

        my $source_crc = checksum("$source/$file");
        my $target_crc = checksum("$target/$file");

        if ( $source_crc == $target_crc ) {
            message(
                tag => 'NOP',
                msg => "$source/$file and $target/$file match",
            ) if $config{veryVerbose};
        }
        else {
            message(
                tag => 'COPY_NEW',
                msg => "$source/$file to"
                  . " $target/${file}$config{configSuffix}",
            ) if $config{veryVerbose};

            # Perform the copy. If -n was specified, don't actually create
            # anything, just report the action.
            #
            # NOTE - this will clobber any existing filexCONFIG-SUFFIXx file!

            unless ( exists $option{noexec} ) {
                copy( "$source/$file", "$target/${file}$config{configSuffix}" )
                  or die
"Failed to copy $source/$file to $target/${file}$config{configSuffix}: $!\n";

                if ( $config{preservePermissions} and $config{superuser} ) {

                    # Only do this if superuser privileges are on.
                    # Otherwise it's bound to fail.

                    my (
                        undef, undef, $mode, undef,  $uid,
                        $gid,  undef, undef, $atime, $mtime
                    ) = stat "$source/$file";

                    chmod $mode, "$target/${file}$config{configSuffix}"
                      or die
"Could not create $target/${file}$config{configSuffix}: $!\n";

                    chown $uid, $gid, "$target/${file}$config{configSuffix}"
                      or die
"Could not set ownership on $target/${file}$config{configSuffix}: $!\n";

                    utime $atime, $mtime,
                      "$target/${file}$config{configSuffix}"
                      or die
"Could not set access and modification times on $target/${file}$config{configSuffix}: $!\n";
                }
            }
        }

        return;
    }

    # Target exists but is something else. Flag a conflict.

    message(
        tag => 'CONFLICT_COPY',
        msg => "$target/$file already exists but is NOT a"
          . ' file or a symlink.',
    );

    logger(
        tag => 'IC',
        log =>
          [ "$target/$file", 'file exists but is not a file or a symlink' ],
    );

    $config{errorStatus} = 1;
    exit 1 if $config{exitOnConflict};
}

sub mkdirectory {
    my $source = shift;
    my $target = shift;
    my $dir    = shift;

    if ( -d "$target/$dir" ) {

        # Target directory already exists.

        message(
            tag => 'NOP',
            msg => "$source/$dir and $target/$dir are both directories",
        ) if $config{veryVerbose};

        return;
    }

    unless ( -e "$target/$dir" ) {

        # Target directory does not exist. It's safe to make the directory.

        message(
            tag => 'MKDIR',
            msg => "$target/$dir",
        ) if $config{veryVerbose};

        # Make the directory. If -n was specified, don't actually create
        # anything, just report the action.

        unless ( exists $option{noexec} ) {
            if ( $config{preservePermissions} and $config{superuser} ) {

                # Only do this if superuser privileges are on.
                # Otherwise it's bound to fail.

                my ( undef, undef, $mode, undef, $uid, $gid, undef ) =
                  stat "$source/$dir";

                mkdir "$target/$dir", $mode
                  or die "Could not create $target/$dir: $!\n";

                chown $uid, $gid, "$target/$dir"
                  or die "Could not set ownership on $target/$dir: $!\n";
            }
            else {
                mkdir "$target/$dir", 0755
                  or die "Could not create $target/$dir: $!\n";
            }
        }

        return;
    }

    # Target already exists but is NOT a directory - conflict.

    message(
        tag => 'CONFLICT',
        msg => "$target/$dir already exists but is NOT" . ' a directory!',
    );

    logger(
        tag => 'IC',
        log => [ "$target/$dir", 'not a directory' ],
    );

    $config{errorStatus} = 1;
    exit 1 if $config{exitOnConflict};
}

sub mklink {
    my $source = shift;
    my $target = shift;
    my $file   = shift;

    if ( -l "$target/$file" ) {

        # Target file exists and is a symlink. If it is a symlink to the
        # source file it can be ignored. Having this test first avoids any
        # problems later where the target may be a symlink to the package
        # file which is in turn a symlink to a non existent file. A -e test
        # in this case fails as it uses stat() which will traverse the
        # link(s).

        my $link = readlink "$target/$file";

        if ( "$source/$file" eq $link ) {
            message(
                tag => 'NOP',
                msg => "$target/$file already linked to" . " $source/$file",
            ) if $config{veryVerbose};
        }
        else {
            message(
                tag => 'CONFLICT',
                msg => "$target/$file is linked to something"
                  . " other than $source/$file"
                  . " ($target/$file -> $link)",
            );

            logger(
                tag => 'IC',
                log => [ "$target/$file", 'invalid symlink' ],
            );

            $config{errorStatus} = 1;
            exit 1 if $config{exitOnConflict};
        }

        return;
    }

    unless ( -e "$target/$file" ) {

        # Target file does not exist. It's safe to make the link.

        message(
            tag => 'SYMLINK',
            msg => "$target/$file -> $source/$file",
        ) if $config{veryVerbose};

        # Make the symbolic link. If -n was specified, don't
        # actually create anything, just report the action.

        unless ( exists $option{noexec} ) {
            symlink "$source/$file", "$target/$file"
              or die 'Failed to create symbolic link'
              . " $target/$file -> $source/$file: $!\n";
        }

        return;
    }

    # Target file exists and is not a symlink

    message(
        tag => 'CONFLICT',
        msg => "$target/$file already exists but is NOT a"
          . " symlink to $source/$file",
    );

    logger(
        tag => 'IC',
        log => [ "$target/$file", 'file exists' ],
    );

    $config{errorStatus} = 1;
    exit 1 if $config{exitOnConflict};
}

sub prune {

    # Only prune target files or directories that are in conflict with the
    # source.

    my $source = shift;
    my $target = shift;
    my $file   = shift;

    if ( -l "$target/$file" ) {
        my $link = readlink "$target/$file";

        unless ( "$source/$file" eq $link ) {

            # Target is a symlink to something other than the source file.

            if ( $config{deleteObjects} ) {
                message(
                    tag => 'UNLINK',
                    msg => "$target/$file",
                ) if $config{veryVerbose};

                unless ( exists $option{noexec} ) {
                    unlink "$target/$file"
                      or die "Could not unlink $target/$file: $!\n";
                }
            }
            else {
                message(
                    tag => 'RENAME',
                    msg =>
                      "$target/$file to $target/${file}$config{prunedSuffix}",
                ) if $config{veryVerbose};

                unless ( exists $option{noexec} ) {
                    rename "$target/$file",
                      "$target/${file}$config{prunedSuffix}"
                      or die "Could not rename $target/$file to"
                      . " $target/${file}$config{prunedSuffix}: $!\n";
                }
            }
        }

        return;
    }

    if ( -e "$target/$file" ) {

        # Target exists but is not a symlink. Therefore it is in conflict
        # by definition.

        if ( -d "$target/$file" ) {
            if ( $config{deleteObjects} ) {
                my %tfiles       = files("$target/$file");
                my %tdirectories = directories("$target/$file");

                if ( scalar keys %tfiles or scalar keys %tdirectories ) {
                    message(
                        tag => 'RENAME',
                        msg =>
"$target/$file to $target/${file}$config{prunedSuffix}"
                          . ": directory is not empty."
                    );

                    unless ( exists $option{noexec} ) {
                        rename "$target/$file",
                          "$target/${file}$config{prunedSuffix}"
                          or die "Could not rename $target/$file to"
                          . " $target/${file}$config{prunedSuffix}: $!\n";
                    }
                }
                else {
                    message(
                        tag => 'UNLINK',
                        msg => "$target/$file",
                    );

                    unless ( exists $option{noexec} ) {
                        unlink "$target/$file"
                          or die "Could not unlink $target/$file: $!\n";
                    }
                }
            }
            else {
                message(
                    tag => 'RENAME',
                    msg =>
                      "$target/$file to $target/${file}$config{prunedSuffix}",
                ) if $config{veryVerbose};

                unless ( exists $option{noexec} ) {
                    rename "$target/$file",
                      "$target/${file}$config{prunedSuffix}"
                      or die "Could not rename $target/$file to"
                      . " $target/${file}$config{prunedSuffix}: $!\n";
                }
            }
        }
        else {
            if ( $config{deleteObjects} ) {
                message(
                    tag => 'UNLINK',
                    msg => "$target/$file",
                ) if $config{veryVerbose};

                unless ( exists $option{noexec} ) {
                    unlink "$target/$file"
                      or die "Could not unlink $target/$file: $!\n";
                }
            }
            else {
                message(
                    tag => 'RENAME',
                    msg =>
                      "$target/$file to $target/${file}$config{prunedSuffix}",
                ) if $config{veryVerbose};

                unless ( exists $option{noexec} ) {
                    rename "$target/$file",
                      "$target/${file}$config{prunedSuffix}"
                      or die "Could not rename $target/$file to"
                      . " $target/${file}$config{prunedSuffix}: $!\n";
                }
            }
        }
    }
}

sub show_locations {
    print << "EOF";
GRAFT_PERL=xPERLx
GRAFT_LOGFILE=xLOGFILEx
GRAFT_TARGETDIR=xTARGETDIRx
GRAFT_PACKAGEDIR=xPACKAGEDIRx
EOF

    exit 0;
}

sub stripslashes {

    # Strip leading and trailing slashes and whitespace from user supplied
    # package names. Some shells will put a trailing slash onto directory
    # names when using file completion - Bash for example.
    #
    # Also, Perl's builtin File::Basename::basename() will return an
    # empty string for a slash terminated directory, unlike the command
    # line version which returns the last directory component.

    my $string = shift;

    $string =~ s#^\s*/*$#/#;
    $string =~ s#/*\s*$##;
    return $string;
}

sub rmfile {
    my $source   = shift;
    my $target   = shift;
    my $file     = shift;
    my %excludes = @_;

    unless ( -e "$target/$file" ) {

        # Target may not exist. It may be an orphaned symlink.

        unless ( -l "$target/$file" ) {
            message(
                tag => 'NOP',
                msg => "$target/$file does not exist",
            ) if $config{veryVerbose};

            return;
        }
    }

    if ( -f "$source/$config{graftConfig}" ) {
        if ( -l "$target/$file" ) {

            # Target is a symlink. If it is a symlink to the source file
            # then remove it so a subsequent graft install will copy the
            # file in place. If it is a symlink elsewhere leave it in
            # place. Also attempt to remove $filexCONFIG-SUFFIXx if it
            # exists. See the code for specifics.

            my $link = readlink "$target/$file";

            if ( "$source/$file" eq $link ) {
                message(
                    tag => 'UNLINK_COPY',
                    msg => "$target/$file",
                ) if $config{veryVerbose};

                unless ( exists $option{noexec} ) {
                    unlink "$target/$file"
                      or message(
                        tag => 'ERROR',
                        msg => "Could not unlink $target/$file: $!",
                      );
                }

                if ( -e "$target/${file}$config{configSuffix}" ) {
                    message(
                        tag => 'UNLINK_NEW',
                        msg => "$target/${file}$config{configSuffix}",
                    ) if $config{veryVerbose};

                    unless ( exists $option{noexec} ) {
                        unlink "$target/${file}$config{configSuffix}"
                          or message(
                            tag => 'ERROR',
                            msg =>
"Could not unlink $target/${file}$config{configSuffix}: $!",
                          );
                    }
                }
            }
            else {
                my $source_crc = checksum("$source/$file");
                my $target_crc = checksum("$target/$file");

                if ( $source_crc == $target_crc ) {

                    # Leave the target symlink in place but remove
                    # filexCONFIG-SUFFIX if it exists.

                    message(
                        tag => 'NOP',
                        msg => "Preserving $target/$file as it is linked to"
                          . " something other than $source/$file."
                          . " CRC32 matches $source/$file"
                    ) if $config{veryVerbose};

                    if ( -e "$target/${file}$config{configSuffix}" ) {
                        message(
                            tag => 'UNLINK_NEW',
                            msg => "$target/${file}$config{configSuffix}",
                        ) if $config{veryVerbose};

                        unless ( exists $option{noexec} ) {
                            unlink "$target/${file}$config{configSuffix}"
                              or message(
                                tag => 'ERROR',
                                msg =>
"Could not unlink $target/${file}$config{configSuffix}: $!",
                              );
                        }
                    }
                }
                else {
                    message(
                        tag => 'NOP',
                        msg => "Preserving $target/$file as it is linked to"
                          . " something other than $source/$file."
                          . " CRC32 does not match $source/$file"
                    ) if $config{veryVerbose};

                    if ( -e "$target/${file}$config{configSuffix}" ) {
                        message(
                            tag => 'NOP',
                            msg =>
                              "Preserving $target/${file}$config{configSuffix}"
                              . " as $target/$file is linked to something"
                              . " other than $source/$file."
                              . " CRC32 does not match $source/$file"
                        ) if $config{veryVerbose};
                    }
                }
            }

            return;
        }

        # The target file exists and is not a symlink. (It's not a
        # directory by definition as directories are handled elsewhere).
        # Leave it in place and attempt to remove filexCONFIG-SUFFIXx if it
        # exists. See the code for specifics.

        my $source_crc = checksum("$source/$file");
        my $target_crc = checksum("$target/$file");

        if ( $source_crc == $target_crc ) {
            message(
                tag => 'NOP',
                msg => "Preserving $target/$file as it is a regular"
                  . " configuration file."
                  . " CRC32 matches $source/$file"
            ) if $config{veryVerbose};

            if ( -e "$target/${file}$config{configSuffix}" ) {
                message(
                    tag => 'UNLINK_NEW',
                    msg => "$target/${file}$config{configSuffix}",
                ) if $config{veryVerbose};

                unless ( exists $option{noexec} ) {
                    unlink "$target/${file}$config{configSuffix}"
                      or message(
                        tag => 'ERROR',
                        msg =>
"Could not unlink $target/${file}$config{configSuffix}: $!",
                      );
                }
            }
        }
        else {
            message(
                tag => 'NOP',
                msg => "Preserving $target/$file as it is a regular"
                  . " configuration file."
                  . " CRC32 does not match $source/$file"
            ) if $config{veryVerbose};
        }
    }
    else {
        # No xGRAFT-CONFIGx file. Check for regular conflicts

        if ( -l "$target/$file" ) {

            # Target file exists and is a symlink. If it is a symlink to
            # the source file it can be ignored. Having this test first
            # avoids any problems later where the target may be a symlink
            # to the package file which is in turn a symlink to a non
            # existent file. A -e test in this case fails as it uses stat()
            # which will traverse the link(s).

            my $link = readlink "$target/$file";

            if ( "$source/$file" eq $link ) {

                # If -n was specified, don't actually remove anything, just
                # report the action.

                message(
                    tag => 'UNLINK',
                    msg => "$target/$file",
                ) if $config{veryVerbose};

                unless ( exists $option{noexec} ) {
                    unlink "$target/$file"
                      or message(
                        tag => 'ERROR',
                        msg => "Could not unlink $target/$file: $!",
                      );
                }

                return;
            }
            else {
                message(
                    tag => 'CONFLICT',
                    msg => "$target/$file is linked to"
                      . " something other than $source/$file"
                      . " ($target/$file -> $link)",
                );

                logger(
                    tag => 'DC',
                    log => [ "$target/$file", "invalid symlink" ],
                );

                return;
            }
        }

        # The target file exists and is not a symlink. (It's not a
        # directory by definition as directories are handled
        # elsewhere).

        # Target file exists and is in conflict with the source file

        if ( -e "$source/$config{graftIgnore}" ) {
            message(
                tag => 'NOTE',
                msg => "Ignored $target/$file already exists"
                  . " but is NOT a symlink to $source/$file",
            );

            logger(
                tag => 'DN',
                log => [ "$target/$file", "file exists [Ignored]" ],
            );

            return;
        }

        if ( exists $excludes{$file} ) {
            message(
                tag => 'NOTE',
                msg => "Excluded $target/$file already exists"
                  . " but is NOT a symlink to $source/$file",
            );

            logger(
                tag => 'DN',
                log => [ "$target/$file", "file exists [Excluded]" ],
            );

            return;
        }

        message(
            tag => 'CONFLICT',
            msg => "$target/$file already exists"
              . " but is NOT a symlink to $source/$file",
        );

        logger(
            tag => 'DC',
            log => [ "$target/$file", "file exists" ],
        );
    }
}

sub uninstall {

    # For each file in $source, remove the corresponding symbolic link from
    # $target. Directories may be deleted depending on the status of
    # $config{deleteObjects}. If the -p option was used instead of -d then
    # prune conflicting files from the target rather than delete previously
    # grafted links.
    #
    # Special handling will be required for directories containing
    # xGRAFT-CONFIGx files.

    my %arg = @_;

    my $source = $arg{source};
    my $target = $arg{target};

    unless ( chdir $source ) {
        message(
            tag => 'ERROR',
            msg => "Could not change directories to $source: $!",
        );

        return;
    }

    message(
        tag => 'Processing',
        msg => "$source",
    ) if $config{verbose};

    # Get a list of files and directories in the source and target directory.

    my %sfiles       = files($source);
    my %tfiles       = files($target);
    my %sdirectories = directories($source);
    my %tdirectories = directories($target);

    # No need to prune directories that have a xGRAFT-CONFIGX file as
    # conflicts are handled by copying the source file to
    # $target/filexCONFIG-SUFFIXx.

    if ( exists $option{prune} and $sfiles{ $config{graftConfig} } ) {
        message(
            tag => 'IGNORE',
            msg => "Ignoring prune operation in $target as"
              . " $source contains $config{graftConfig}",
        );
    }

    # Die if we cannot perform necessary CRC32 checksums?

    if ( exists $sfiles{ $config{graftConfig} } ) {
        unless ( exists $config{HasCRC32} ) {
            die "Cannot process $sfiles{$config{graftConfig}} during uninstall"
              . " because Compress::Raw::Zlib::crc32() is unavailable\n";
        }
    }

    # Take a note of any files that would be excluded so that an
    # appropriate message can be shown should there be a conflict on
    # deletion. Used in rmfiles().

    my %excludes;

    if ( exists $sfiles{ $config{graftExclude} } ) {
        %excludes = cat( $config{graftExclude} );
    }

    for my $file ( keys %sfiles ) {

        # Ignore control files - they are never grafted so there's nothing
        # to uninstall.

        next if ( $file eq $config{graftIgnore} );
        next if ( $file eq $config{graftInclude} );
        next if ( $file eq $config{graftExclude} );
        next if ( $file eq $config{graftConfig} );

        if ( exists $option{prune} ) {
            prune( $source, $target, $file )
              unless ( exists $sfiles{ $config{graftConfig} } );
        }
        else {
            rmfile( $source, $target, $file, %excludes );
        }
    }

    # Recursively descend into this directory and repeat the process.

    foreach my $dir ( sort keys %sdirectories ) {
        uninstall(
            source => "$source/$dir",
            target => "$target/$dir",
        );
    }

    # Is the target directory empty?
    #
    # Exceptions:
    #	- target is not a directory (IE a symlink to a directory)
    #	- prune mode is enabled
    #	- the target directory is the top target directory
    #	- the source directory contains a xGRAFT-CONFIGx file

    return unless ( -d $target );
    return if exists $option{prune};
    return if ( $target eq $config{targetTop} );
    return if ( exists $sfiles{ $config{graftConfig} } );

    # Refresh the list of files and directories in the target.

    %tfiles       = files($target);
    %tdirectories = directories($target);

    unless ( scalar keys %tfiles or scalar keys %tdirectories ) {
        if ( $config{deleteObjects} ) {
            message(
                tag => 'RMDIR',
                msg => "$target/",
            ) if $config{veryVerbose};

            unless ( exists $option{noexec} ) {

                # Directory removal is not fatal because we want to
                # continue to delete as much as possible.

                rmdir $target
                  or message(
                    tag => 'ERROR',
                    msg => "Cannot remove directory $target: $!",
                  );
            }
        }
        else {
            message(
                tag => 'EMPTY',
                msg => "$target/ is now empty. Delete manually if necessary.",
            ) if $config{veryVerbose};
        }
    }
}

sub usage {
    my $nopriv;
    my $priv;
    my $option_C;

    if ( $config{superuser} ) {
        $priv   = 'Requires superuser privileges.';
        $nopriv = 'Does not require superuser privileges.';
    }
    else {
        $priv   = '';
        $nopriv = '';
    }

    unless ( 'xGRAFT-NEVERx' eq '' ) {
        $option_C = '[-C] ';
    }
    else {
        $option_C = '';
    }

    print << "EOF" if $config{superuser};

$config{progname}: Version $config{version}

Usage:
  $config{progname} -i ${option_C}[-P|u] [-l log] [-n] [-r /rootdir] [-s|-t target] [-v|V] package package ...
  $config{progname} -d [-D] [-u] [-l log] [-n] [-r /rootdir] [-s|-t target] [-v|V] package package ...
  $config{progname} -p [-D] [-u] [-l log] [-n] [-r /rootdir] [-s|-t target] [-v|V] package package ...

  -i		Install packages. $priv
		Cannot be used with -d or -p options.
EOF

    print << "EOF" unless ( $config{superuser} );

$config{progname}: Version $config{version}

Usage:
  $config{progname} -i ${option_C}[-l log] [-n] [-r /rootdir] [-s|-t target] [-v|V] package package ...
  $config{progname} -d [-D] [-l log] [-n] [-r /rootdir] [-s|-t target] [-v|V] package package ...
  $config{progname} -p [-D] [-l log] [-n] [-r /rootdir] [-s|-t target] [-v|V] package package ...

  -i		Install packages. $priv
		Cannot be used with -d or -p options.
EOF

    unless ( 'xGRAFT-NEVERx' eq '' ) {

        # Only display help details for -C if there are file or directories
        # specified in the Makefile to be consider for ignoring automatically.

        map { ++$config{graftNever}{$_} } qw ( xGRAFT-NEVERx );

        if ( $config{neverGraft} ) {

            print << "EOF";
  -C		Disable the automatic exclusion of files and/or
		directories that match:
EOF

            print "\t\t	   ";
            print join( ' ', keys %{ $config{graftNever} } ), "\n";
        }
        else {
            print << "EOF";
  -C		Force the automatic exclusion of files and/or
		directories that match:
EOF

            print "\t\t	   ";
            print join( ' ', keys %{ $config{graftNever} } ), "\n";
        }
    }

    if ( $config{superuser} ) {
        if ( $config{preservePermissions} ) {
            print << "EOF";
  -P		Do not preserve ownership and permissions when creating
		directories. Can only be used with the -i option.
		Cannot be used with the -u option.
EOF
        }
        else {
            print << "EOF";
  -P		Preserve ownership and permissions when creating
		directories. Can only be used with the -i option.
		Cannot be used with the -u option.

		Silently ignored if the effective user is not root.
EOF
        }
    }

    print << "EOF";
  -d		Delete packages. $priv
		Cannot be used with -i or -p options.
  -p		Prune files that will conflict with the grafting of the
		named packages. $priv
		Cannot be used with -d or -i options.
EOF

    if ( $config{deleteObjects} ) {
        print << "EOF";
  -D		When used with the -d option, do not remove directories
		made empty by package deletion. When used with the -p
		option, rename conflicting files or directories to
		file$config{prunedSuffix} instead of removing them.
		Cannot be used with the -i option.
EOF
    }
    else {
        print << "EOF";
  -D		When used with the -d option, remove directories made
		empty by package deletion. When used with the -p
		option, remove conflicting files or directories
		instead of renaming them as file$config{prunedSuffix}. If
		the directory is not empty it will be renamed as
		dir$config{prunedSuffix}. Cannot be used with the -i option.
EOF
    }

    print << "EOF" if $config{superuser};
  -u		Superuser privileges are not required to install, delete
		or prune packages. Cannot be used with the -P option.
EOF

    print << "EOF";
  -l log	Use the named file as the log file instead of the
		default log file. The log file name must be fully
		qualified. The log file is not used if the -n option
		is also supplied. Default: xLOGFILEx
  -n		Print list of operations but do NOT perform them.
		Automatically implies the very verbose option.
EOF

    print << "EOF" if $config{superuser};
		$nopriv
EOF

    print << "EOF";
  -r /rootdir	Use the fully qualified named directory as the root directory
		for all graft operations. The source directory, target
		directory and log file will all be relative to this
		specific directory. Can only be used by the superuser.
  -s		Stow/Depot compatibility mode. Infer the graft target
		directory from the package installation directory in
		the manner of Stow and Depot. Cannot be used with the
		-t option.
  -t target	Use the named directory as the graft target directory
		rather than the default target directory. The target
		directory must be fully qualified. Cannot be used with
		the -s option. Default: xTARGETDIRx
  -v		Be verbose.
  -V		Be very verbose.
  package	Operate on the named packages. If the package name is
		not fully qualified, the default package installation
		directory will be prepended to the named package.
		Default: xPACKAGEDIRx
EOF

    exit 2;
}

###########################################################################
