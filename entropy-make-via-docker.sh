#!/usr/bin/env bash

MK_BASHSRC="${BASH_SOURCE[0]}"
while [ -h "$MK_BASHSRC" ]; do # resolve $MK_BASHSRC until the file is no longer a symlink
    MK_BASHSRCDIR="$( cd -P "$( dirname "$MK_BASHSRC" )" >/dev/null && pwd )"
    MK_BASHSRC="$(readlink "$MK_BASHSRC")"

    # if $MK_BASHSRC was a relative symlink, we need to resolve it relative
    # to the path where the symlink file was located
    [[ $MK_BASHSRC != /* ]] && MK_BASHSRC="$MK_BASHSRCDIR/$MK_BASHSRC"
done
MK_BASHSRCDIR="$( cd -P "$( dirname "$MK_BASHSRC" )" >/dev/null && pwd )"

MK_USER_NAME="$(id -nu)"
MK_USER_ID="$(id -u)"
MK_UGROUP_NAME="$(id -ng)"
MK_UGROUP_ID="$(id -g)"

MK_MOUTPONIT="/home/build/entropy-floorp-build/"


MK_DEBIAN_SROUCELIST='
deb     https://mirrors.ustc.edu.cn/debian/         bookworm main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian/         bookworm main contrib non-free non-free-firmware

deb     https://mirrors.ustc.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware

deb     https://mirrors.ustc.edu.cn/debian/         bookworm-updates main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian/         bookworm-updates main contrib non-free non-free-firmware

deb     https://mirrors.ustc.edu.cn/debian/         bookworm-backports main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian/         bookworm-backports main contrib non-free non-free-firmware
'

MK_DEBIAN_DEPS=(
    # deps from moz boostrap
    bash findutils gzip libxml2 m4 make perl tar unzip git
    # deps from debian firefox build deps
    autotools-dev
    debhelper-compat
    libx11-dev
    libx11-xcb-dev
    libxt-dev
    libgtk-3-dev
    libglib2.0-dev
    libdrm-dev
    libstartup-notification0-dev
    libjpeg-dev
    zlib1g-dev
    libreadline-dev
    python3
    python3-pip
    python-is-python3
    dpkg-dev
    libnspr4-dev
    libnss3-dev
    libvpx-dev
    libdbus-glib-1-dev
    libffi-dev
    libevent-dev
    libpulse-dev
    libasound2-dev
    yasm
    nasm
    llvm-14-dev
    libclang-14-dev
    clang-14
    libc++-14-dev-wasm32
    libclang-rt-14-dev-wasm32
    lld-14
    cbindgen
    nodejs
    zip
    unzip
    locales
    xvfb
    xfonts-base
    xauth
    ttf-bitstream-vera
    fonts-freefont-ttf
    fonts-dejima-mincho
    iso-codes
    # entropy spec deps
    util-linux coreutils passwd curl xz-utils
)

# we should add a fake host entry to prevent pacman replace
# hosts.pacnew to dedicated /etc/hosts (readonly with post error) file
# since we use host machine's network stack.
docker run \
       --rm=true \
       --network=host \
       --add-host='localhost:127.0.0.1' \
       -v "${MK_BASHSRCDIR}:${MK_MOUTPONIT}" \
       debian:bookworm \
       bash -c \
       "set -e; \
if [ -d /usr/lib/apt/methods ] &&                                                            \
       [ ! -e /usr/lib/apt/methods/https ] ; then                                            \
    cd /usr/lib/apt/methods ;                                                                \
    ln -s http https ;                                                                       \
fi ;                                                                                         \
if [ -f /etc/apt/sources.list ]; then                                                        \
    sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list ;                  \
elif [ -f /etc/apt/sources.list.d/debian.sources ] ; then                                    \
    sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources ; \
else                                                                                         \
    printf 'No apt source list or referred file found' ;                                     \
    exit 1 ;                                                                                 \
fi ;                                                                                         \
apt-get -y update ; \
apt install -y ca-certificates apt-transport-https; \
echo '${MK_DEBIAN_SROUCELIST}' > /etc/apt/sources.list ; \
apt-get -y update ; apt-get -y upgrade ; \
apt install -y ${MK_DEBIAN_DEPS[*]} ; \
groupadd -g '$MK_UGROUP_ID' '$MK_UGROUP_NAME'; \
useradd  -m -G '$MK_UGROUP_NAME' -g '$MK_UGROUP_ID' -u '$MK_USER_ID' '$MK_USER_NAME'; \
su '$MK_USER_NAME' -c \"cd '${MK_MOUTPONIT}'; \
export HTTP_PROXY='${HTTP_PROXY}';            \
export http_proxy='${http_proxy}';            \
export HTTPS_PROXY='${HTTPS_PROXY}';          \
export https_proxy='${https_proxy}';          \
export NO_PROXY='${NO_PROXY}';                \
export no_proxy='${no_proxy}';                \
export MK_OPT_NO_OPTIMIZATION='${MK_OPT_NO_OPTIMIZATION}' ; \
export MK_VIA_DOCKER=true ;                   \
export -p ;                                   \
echo 'Test internet capable ...' ;            \
curl -I www.google.com ;                      \
echo \\\"with user \\\$(id -a) ...\\\" ; sleep 10 ;   \
bash entropy-make-core.sh ;\""
