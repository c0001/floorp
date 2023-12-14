#!/usr/bin/env bash
set -e
MK_BASHRCNAME="${BASH_SOURCE[0]}"
while [ -h "$MK_BASHRCNAME" ]; do # resolve $MK_BASHRCNAME until the file is no longer a symlink
    MK_BASHSRCDIR="$( cd -P "$( dirname "$MK_BASHRCNAME" )" >/dev/null && pwd )"
    MK_BASHRCNAME="$(readlink "$MK_BASHRCNAME")"

    # if $MK_BASHRCNAME was a relative symlink, we need to resolve it relative
    # to the path where the symlink file was located
    [[ $MK_BASHRCNAME != /* ]] && MK_BASHRCNAME="$MK_BASHSRCDIR/$MK_BASHRCNAME"
done
MK_BASHSRCDIR="$( cd -P "$( dirname "$MK_BASHRCNAME" )" >/dev/null && pwd )"

if [[ $1 = 'test' ]]; then
    MK_TESTP=1
else
    MK_TESTP=0
fi

export MOZ_BUILD_DATE="$(printf "%(%Y%m%d%H%M%S)T\n")"
# change default moz state dir '~/.mozbuild' to our spec, see more of docstring under
# 'build/mach_initialize.py'
mk_mozbuild_state_path_base='.mozbuild'
export MOZBUILD_STATE_PATH="${MK_BASHSRCDIR}/${mk_mozbuild_state_path_base}"

mk_edist_dir="${MK_BASHSRCDIR}/entropy-dist"
mk_ver="$(cat browser/config/version.txt)"
mk_eflver="$(cat browser/config/version_display.txt)"
mk_gpgverifyID='42EBF24476885D91'
mk_platform="$(uname -m)"
mk_objdir="${MK_BASHSRCDIR}/obj-${mk_platform}-pc-linux-gnu"
mk_distdir="${MK_BASHSRCDIR}/obj-${mk_platform}-pc-linux-gnu/dist"
mk_gitrev=''

[[ -f "${MK_BASHSRCDIR}/mozconfig" ]] && rm -f "${MK_BASHSRCDIR}/mozconfig"
if [[ -e ${MK_BASHSRCDIR}/.git ]] ; then
    if [[ $MK_TESTP -eq 0 ]] ; then
        git -C "$MK_BASHSRCDIR" clean -xfd
    fi
    git -C "$MK_BASHSRCDIR" submodule deinit --force --all
    git -C "$MK_BASHSRCDIR" submodule update --init --recursive
    mk_gitrev="$(git -C "$MK_BASHSRCDIR" describe --tags)"
    if [[ $mk_gitrev =~ ^(entropy-)?v[0-9]+\. ]] && \
           [[ ! $mk_gitrev =~ '-'[0-9]+-g.+$ ]]
    then
        :
    else
        mk_gitrev="$(git -C "$MK_BASHSRCDIR" rev-parse --short HEAD)"
        mk_eflver="${mk_eflver}_entropy_git:${mk_gitrev}"
    fi
elif [[ $MK_TESTP -eq 0 ]] ; then
    if [[ -e "${mk_edist_dir}" ]] ; then rm -rvi "$mk_edist_dir" ; fi
    if [[ -e "${mk_objdir}" ]] ; then  rm -rvi "$mk_objdir"; fi
fi

cp "${MK_BASHSRCDIR}/.github/workflows/src/linux/shared/mozconfig_linux_base" \
   "${MK_BASHSRCDIR}/mozconfig"

function mk_func_add_mozconf ()
{
    echo "$1" >> "${MK_BASHSRCDIR}/mozconfig"
}

function mk_func_call_marh ()
{
    if [[ MK_TESTP -eq 1 ]] ; then
        echo "./mach $*"
    else
        ./mach "$@"
    fi
}

mk_func_add_mozconf 'ac_add_options --with-branding=browser/branding/official'
mk_func_add_mozconf 'ac_add_options --disable-updater'
mk_func_add_mozconf 'ac_add_options MOZ_PGO=1'
mk_func_add_mozconf "mk_add_options 'export RUSTC_WRAPPER=${MOZBUILD_STATE_PATH}/sccache/sccache'"
mk_func_add_mozconf "mk_add_options 'export CCACHE_CPP2=yes'"
mk_func_add_mozconf "ac_add_options --with-ccache=${MOZBUILD_STATE_PATH}/sccache/sccache"

cd "${MK_BASHSRCDIR}"/

# for a official build, firefox need X display for batch of web render
# test, thus we exposed a virtual DISPLAY which will not pollute which
# DISPLAY our session used.
! command -v Xvfb &>/dev/null && \
    echo "\
virtual X frame buffer command Xvfb is not found in your PATH." \
    && exit 1
Xvfb :20 -screen 0 1024x768x24 &
mk_xvfb_procid=$!
echo "Waiting for xvfb initialization finished ..."
sleep 2
if ! ps -p $mk_xvfb_procid &>/dev/null ; then
    echo "Xvfb init fatal" ; exit 1
else
    export DISPLAY=:20
    # since firfox may prefer test with wayland, but we prefer use
    # headless virtual X display.
    unset -v WAYLAND_DISPLAY
fi

mk_func_call_marh --no-interactive bootstrap --application-choice browser

if ! mk_func_call_marh build ; then
    # try twice build for first fail which may caused by OOM
    mk_func_call_marh build
fi

mk_func_call_marh package

mk_func_call_marh \
    package-multi-locale --locales \
    ar cs da de el en-US en-GB es-ES fr hu \
    id it ja ko lt nl nn-NO pl pt-BR pt-PT \
    ru sv-SE th tr vi zh-CN zh-TW

if ps -p "$mk_xvfb_procid" &>/dev/null ; then
    kill "$mk_xvfb_procid"
fi

mkdir -p "${mk_edist_dir}/${mk_mozbuild_state_path_base}"
(
    [[ $MK_TESTP -eq 1 ]] && exit 0
    cd "$mk_distdir"
    for i in floorp-*.bz2 ; do
        mv "$i" "${mk_edist_dir}/${i/"$mk_ver"/"$mk_eflver"}"
    done
    for i in floorp-*.zip ; do
        mv "$i" "${mk_edist_dir}/${i/"$mk_ver"/"$mk_eflver"}"
    done
    for i in floorp-*.txt ; do
        mv "$i" "${mk_edist_dir}/${i/"$mk_ver"/"$mk_eflver"}"
    done
)

if [[ -d "${MOZBUILD_STATE_PATH}"/toolchains ]] ; then
    mv "${MOZBUILD_STATE_PATH}"/toolchains \
       "${mk_edist_dir}/${mk_mozbuild_state_path_base%/}/"
fi

if [[ -e ${MK_BASHSRCDIR}/.git ]] ; then
    echo "Archiving source tree ..."
    git archive --format=tar \
        --output="${mk_edist_dir}/floorp-${mk_eflver}.src.tar" \
        HEAD
    echo "Archiving source submodules tree recursively ..."
    git submodule --quiet foreach --recursive \
        'git archive --format=tar --prefix="${displaypath}/" -o __submodule__.tar HEAD'
    echo "Combination of source and submodules tree ..."
    # use force-local option to allow colon char in archive name: see
    # https://superuser.com/questions/1720172/what-does-tar-cannot-connect-to-resolve-failed-mean
    git submodule --quiet foreach --recursive \
        "cd '${mk_edist_dir}'                           && \
tar --concatenate --force-local                            \
--file='floorp-${mk_eflver}.src.tar'                       \
\"${MK_BASHSRCDIR}/\${displaypath}/__submodule__.tar\"  && \
rm -fv \"${MK_BASHSRCDIR}/\${displaypath}/__submodule__.tar\""
    cd "${mk_edist_dir}"
    echo "Gzip srouce archive ..."
    gzip -9 "floorp-${mk_eflver}.src.tar"
fi

cd "${mk_edist_dir}"
cat <<EOF > README.txt

To recompile source, mv the '.mozbuild' to decompressed source archive
root path for reusing the SCCACHE which used for this distribution for
preventing re-downloading artifacts and keep compile env consist.a

EOF

echo "Generate sha256sum hash log for distributions ..."
mk_dist_shahash="$(find . -type f -print0 | xargs --null sha256sum -b)"
echo "$mk_dist_shahash" > ./sha256sum.log
if [[ -n $mk_gpgverifyID ]] && \
       gpg --list-secret-keys \
           "$mk_gpgverifyID" >/dev/null 2>&1
then
    gpg --detach-sign --armor \
        -u "$mk_gpgverifyID"    \
        -o "sha256sum.log.asc" "sha256sum.log"
fi
