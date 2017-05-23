#! /bin/bash

#    compile_damapper
#    Copyright (C) 2016-2017 German Tischler
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.

function getLatest
{
	local PROJ=$1
	curl --location https://github.com/gt1/${PROJ}/releases | grep "<a href=" | grep "release" | grep -v linux | egrep "\.tar\." |\
		perl -p -e "s/.*href=\"//" | perl -p -e "s/\".*//" | sed "s|.*/||" | perl -p -e "s/\.tar.*//" | head -n 1
}

function nproc
{
	if [ "${ARCH}" = "Linux" ] ; then
		TNUMPROC=`cat /proc/cpuinfo  | grep "processor" | wc -l`
	elif [ "${ARCH}" = "Darwin" ] ; then
		TNUMPROC=`sysctl -a | grep machdep.cpu.thread_count | awk '{print $2}'`
	fi

	if [ ! -z "${TNUMPROC}" ] ; then
		NUMPROC=$TNUMPROC
	fi

	echo $NUMPROC
}

function buildhdf5
{
	rm -fR hdf5-1.8.18 hdf5-1.8.18-src hdf5-1.8.18-build
	curl --location https://support.hdfgroup.org/ftp/HDF5/current18/src/hdf5-1.8.18.tar.gz | tar xzvf -
	mv hdf5-1.8.18 hdf5-1.8.18-src
	mkdir -p hdf5-1.8.18-build
	cd hdf5-1.8.18-build
	../hdf5-1.8.18-src/configure --enable-static --disable-shared $*
	make -j`nproc`
	make -j`nproc` install
	cd ..
	rm -fR hdf5-1.8.18 hdf5-1.8.18-src hdf5-1.8.18-build
}

function builddextractor
{
	curl --location https://github.com/thegenemyers/DEXTRACTOR/archive/master.zip > DEXTRACTOR.zip
	rm -fR DEXTRACTOR-master
	unzip DEXTRACTOR.zip
	cd DEXTRACTOR-master
	sed -e "s|-lz|-lz -ldl -lm|" -i  Makefile
	make PATH_HDF5=$1
	make install DEST_DIR=$1/bin
	cd ..
	rm -fR DEXTRACTOR.zip DEXTRACTOR-master
}

function buildlatest
{
	local PROJ=$1
	shift
	local SKIP=$1
	shift
	
	if [ ! -e ${SKIP} ] ; then
		local VERSION=`getLatest ${PROJ}`
		curl --location https://github.com/gt1/${PROJ}/archive/${VERSION}.tar.gz | tar xzvf -
		mv ${PROJ}-${VERSION} ${PROJ}-${VERSION}-src
		mkdir -p ${PROJ}-${VERSION}-build
		pushd ${PROJ}-${VERSION}-build
		../${PROJ}-${VERSION}-src/configure $*
		make -j`nproc`
		make -j`nproc` install
		popd
		rm -fR ${PROJ}-${VERSION}-src ${PROJ}-${VERSION}-build
	fi
}

ARCH=`uname`
NPROC=`nproc`

BUILD_GCC=gcc

if [ $# -lt 1 ] ; then
	echo "usage: $0 <installprefix>"
	exit 1
fi

INSTALLDIR=$1

mkdir -p ${INSTALLDIR}
pushd ${INSTALLDIR}
INSTALLDIR=$PWD
popd

buildhdf5 --prefix=${INSTALLDIR}
builddextractor ${INSTALLDIR}

if [ "${ARCH}" = "Darwin" ] ; then
	SHARED_LIBRARY_SUFFIX=".dylib"
else
	SHARED_LIBRARY_SUFFIX=".so"
fi

if [ ! -e ${INSTALLDIR}/bin/LAsort ] ; then
	curl --location https://github.com/thegenemyers/DALIGNER/archive/master.zip > DALIGNER.zip
	rm -fR DALIGNER-master
	unzip DALIGNER.zip
	rm -f DALIGNER.zip
	cd DALIGNER-master
	make -j${NPROC}
	mkdir -p ${INSTALLDIR}/bin
	cp -p daligner HPC.daligner LAsort LAmerge LAsplit LAcat LAshow LAcheck ${INSTALLDIR}/bin
	cd ..
	rm -fR DALIGNER-master
fi

if [ ! -e ${INSTALLDIR}/lib/libalign${SHARED_LIBRARY_SUFFIX} ] ; then
	rm -fR DALIGNER

	curl --location https://github.com/gt1/DALIGNER/archive/all_fixes_19_09_2015_prs.zip > all_fixes_19_09_2015_prs.zip
	rm -fR DALIGNER-all_fixes_19_09_2015_prs
	unzip all_fixes_19_09_2015_prs.zip
	rm -f all_fixes_19_09_2015_prs.zip
	
	cd DALIGNER-all_fixes_19_09_2015_prs
		if [ "${ARCH}" = "Darwin" ] ; then
			make -j${NPROC} libinstall PREFIX=${INSTALLDIR} SHARED_LIBRARY_EXTRA_LINKER_FLAGS="-install_name @executable_path/../lib/libalign.dylib" \
				SHARED_LIBRARY_SUFFIX="${SHARED_LIBRARY_SUFFIX}" CC=${BUILD_GCC}
		else
			make -j${NPROC} libinstall PREFIX=${INSTALLDIR} CC=${BUILD_GCC}
		fi
	cd ..
	
	rm -fR DALIGNER-all_fixes_19_09_2015_prs
fi

buildlatest libmaus2 ${INSTALLDIR}/lib/libmaus2.a --enable-native --with-daligner=${INSTALLDIR} --prefix=${INSTALLDIR}
buildlatest biobambam2 ${INSTALLDIR}/bin/bamsort --prefix=${INSTALLDIR} --with-libmaus2=${INSTALLDIR}
buildlatest lastools ${INSTALLDIR}/bin/lassort --prefix=${INSTALLDIR} --with-libmaus2=${INSTALLDIR}
buildlatest damapper_bwt ${INSTALLDIR}/bin/damapper_bwt --prefix=${INSTALLDIR} --with-libmaus2=${INSTALLDIR}

if [ ! -e ${INSTALLDIR}/bin/damapper ] ; then
	curl --location https://github.com/thegenemyers/DAMAPPER/archive/master.zip > damapper.zip
	rm -fR DAMAPPER-master
	unzip damapper.zip
	rm -f damapper.zip
	cd DAMAPPER-master
	make -j${NPROC}
	cp -p HPC.damapper damapper ${INSTALLDIR}/bin
	cd ..
	rm -fR DAMAPPER-master
fi

if [ ! -e ${INSTALLDIR}/bin/fasta2DAM ] ; then
	curl --location https://github.com/thegenemyers/DAZZ_DB/archive/master.zip > DAZZ_DB.zip
	rm -fR DAZZ_DB-master
	unzip DAZZ_DB.zip
	rm -f DAZZ_DB.zip
	cd DAZZ_DB-master
	make -k -j${NPROC}
	make -k install DEST_DIR=${INSTALLDIR}/bin
	cd ..
	rm -fR DAZZ_DB-master
fi

exit 0
