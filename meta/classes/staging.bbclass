python populate_sysroot_prehook () {
	return
}

python populate_sysroot_posthook () {
	return
}

packagedstaging_fastpath () {
	:
}

sysroot_stage_dir() {
	src="$1"
	dest="$2"
	# if the src doesn't exist don't do anything
	if [ ! -d "$src" ]; then
		 return
	fi

	# We only want to stage the contents of $src if it's non-empty so first rmdir $src
	# then if it still exists (rmdir on non-empty dir fails) we can copy its contents
	rmdir "$src" 2> /dev/null || true
	# However we always want to stage a $src itself, even if it's empty
	mkdir -p "$dest"
	if [ -d "$src" ]; then
		cp -fpPR "$src"/* "$dest"
	fi
}

sysroot_stage_libdir() {
	src="$1"
	dest="$2"

	olddir=`pwd`
	cd $src
	las=$(find . -name \*.la -type f)
	cd $olddir
	echo "Found la files: $las"		 
	for i in $las
	do
		sed -e 's/^installed=yes$/installed=no/' \
		    -e '/^dependency_libs=/s,${WORKDIR}[[:alnum:]/\._+-]*/\([[:alnum:]\._+-]*\),${STAGING_LIBDIR}/\1,g' \
		    -e "/^dependency_libs=/s,\([[:space:]']\)${libdir},\1${STAGING_LIBDIR},g" \
		    -i $src/$i
	done
	sysroot_stage_dir $src $dest
}

sysroot_stage_dirs() {
	from="$1"
	to="$2"

	sysroot_stage_dir $from${includedir} $to${STAGING_INCDIR}
	if [ "${BUILD_SYS}" = "${HOST_SYS}" ]; then
		sysroot_stage_dir $from${bindir} $to${STAGING_DIR_HOST}${bindir}
		sysroot_stage_dir $from${sbindir} $to${STAGING_DIR_HOST}${sbindir}
		sysroot_stage_dir $from${base_bindir} $to${STAGING_DIR_HOST}${base_bindir}
		sysroot_stage_dir $from${base_sbindir} $to${STAGING_DIR_HOST}${base_sbindir}
		sysroot_stage_dir $from${libexecdir} $to${STAGING_DIR_HOST}${libexecdir}
		sysroot_stage_dir $from${sysconfdir} $to${STAGING_DIR_HOST}${sysconfdir}
		sysroot_stage_dir $from${localstatedir} $to${STAGING_DIR_HOST}${localstatedir}
	fi
	if [ -d $from${libdir} ]
	then
		sysroot_stage_libdir $from/${libdir} $to${STAGING_LIBDIR}
	fi
	if [ -d $from${base_libdir} ]
	then
		sysroot_stage_libdir $from${base_libdir} $to${STAGING_DIR_HOST}${base_libdir}
	fi
	sysroot_stage_dir $from${datadir} $to${STAGING_DATADIR}
}

sysroot_stage_all() {
	sysroot_stage_dirs ${D} ${SYSROOT_DESTDIR}
}

do_populate_sysroot[dirs] = "${STAGING_DIR_TARGET}/${bindir} ${STAGING_DIR_TARGET}/${libdir} \
			     ${STAGING_DIR_TARGET}/${includedir} \
			     ${STAGING_BINDIR_NATIVE} ${STAGING_LIBDIR_NATIVE} \
			     ${STAGING_INCDIR_NATIVE} \
			     ${STAGING_DATADIR} \
			     ${S} ${B}"

# Could be compile but populate_sysroot and do_install shouldn't run at the same time
addtask populate_sysroot after do_install

PSTAGING_ACTIVE = "0"
SYSROOT_PREPROCESS_FUNCS ?= ""
SYSROOT_DESTDIR = "${WORKDIR}/sysroot-destdir/"
SYSROOT_LOCK = "${STAGING_DIR}/staging.lock"


python do_populate_sysroot () {
    #
    # if do_stage exists, we're legacy. In that case run the do_stage,
    # modify the SYSROOT_DESTDIR variable and then run the staging preprocess
    # functions against staging directly.
    #
    # Otherwise setup a destdir, copy the results from do_install
    # and run the staging preprocess against that
    #
    pstageactive = (bb.data.getVar("PSTAGING_ACTIVE", d, True) == "1")
    lockfile = bb.data.getVar("SYSROOT_LOCK", d, True)
    stagefunc = bb.data.getVar('do_stage', d, True)

    dest = bb.data.getVar('D', d, True)
    sysrootdest = bb.data.expand('${SYSROOT_DESTDIR}${STAGING_DIR_TARGET}', d)
    bb.mkdirhier(sysrootdest)

    bb.build.exec_func("sysroot_stage_all", d)
    #os.system('cp -pPR %s/* %s/' % (dest, sysrootdest))
    for f in (bb.data.getVar('SYSROOT_PREPROCESS_FUNCS', d, True) or '').split():
        bb.build.exec_func(f, d)
    bb.build.exec_func("packagedstaging_fastpath", d)

    lock = bb.utils.lockfile(lockfile)
    os.system(bb.data.expand('cp -pPR ${SYSROOT_DESTDIR}${TMPDIR}/* ${TMPDIR}/', d))
    bb.utils.unlockfile(lock)
}

def is_legacy_staging(d):
    stagefunc = bb.data.getVar('do_stage', d, True)
    if stagefunc is None:
        return False
    return True

python () {
    if is_legacy_staging(d):
        bb.fatal("Legacy staging found for %s as it has a do_stage function. This will need conversion to a do_install or often simply removal to work with Poky" % bb.data.getVar("FILE", d, True))
}


