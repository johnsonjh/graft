#!/usr/bin/env sh
#
# $Id: graftBootStrap.sh,v 1.7 2002/02/22 19:26:54 peters Exp $
#
# Bootstrap graft and perl - they have a nice incestuous relationship
# as the grafted graft uses the grafted path to the grafted perl, so
# you need to explicitly graft graft and graft perl before you can
# graft anything else.
#
# Author: Gordon Rowell (Gordon.Rowell@gormand.com.au)
#
# Modifications by Peter Samuel (Peter.Samuel@gormand.com.au)
#
###########################################################################

REPOSITORY=$1  # Where graft and perl were installed
GRAFTVERSION=$2  # Version number of graft
PERLVERSION=$3  # Version number of perl
TARGET=$4  # Public location of symlink tree

# Default values of the above for interactive use
repository="/pkgs"
graftversion="2.4"
perlversion="5.6.0"
target="/pkgs"

if [ $# -ne 4 ]; then
	echo  "Incorrect argument specification - will try interactive..."

	n=$(echo -n)

	if  [ "$n" = "-n" ]; then
		unset n
		c='\c'
	fi

	echo  $n "Where did you install both graft and perl [$repository] $c"
	read  REPOSITORY

	if  [ -z "$REPOSITORY" ]; then
		REPOSITORY="$repository"
	fi

	echo  $n "What version of graft are you bootstrapping [$graftversion] $c"
	read  GRAFTVERSION

	if  [ -z "$GRAFTVERSION" ]; then
		GRAFTVERSION="$graftversion"
	fi

	echo  $n "What version of perl are you bootstrapping [$perlversion] $c"
	read  PERLVERSION

	if  [ -z "$PERLVERSION" ]; then
		PERLVERSION="$perlversion"
	fi

	echo  $n "Where will you be grafting graft and perl [$target] $c"
	read  TARGET

	if  [ -z "$TARGET" ]; then
		TARGET="$target"
	fi

fi

GRAFT=${REPOSITORY}/graft-${GRAFTVERSION}/bin/graft
PERL=${REPOSITORY}/perl-${PERLVERSION}/bin/perl

if [ -x ${GRAFT} -a -x ${PERL} ]; then
	${PERL}  ${GRAFT} -i -t $TARGET $REPOSITORY/graft-${GRAFTVERSION}
	${PERL}  ${GRAFT} -i -t $TARGET $REPOSITORY/perl-${PERLVERSION}
else
	echo  "Either ${GRAFT} or ${PERL} is not executable"
	exit  1
fi
