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

# we should add a fake host entry to prevent pacman replace
# hosts.pacnew to dedicated /etc/hosts (readonly with post error) file
# since we use host machine's network stack.
docker run \
       --rm=true \
       --network=host \
       --add-host='localhost:127.0.0.1' \
       -v "${MK_BASHSRCDIR}:${MK_MOUTPONIT}" \
       archlinux:base-devel \
       bash -c \
       "set -e; \
echo 'Server = https://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch' > /etc/pacman.d/mirrorlist
pacman-key --init ; pacman -Syy --noconfirm ; pacman -S --noconfirm archlinux-keyring ; \
pacman -Syu --noconfirm ; \
pacman -S --noconfirm --needed bash findutils gzip \
libxml2 m4 make perl tar unzip git xorg-server-xvfb \
python python-pip; \
groupadd -g '$MK_UGROUP_ID' '$MK_UGROUP_NAME'; \
useradd  -m -G '$MK_UGROUP_NAME' -g '$MK_UGROUP_ID' -u '$MK_USER_ID' '$MK_USER_NAME';
su '$MK_USER_NAME' -c 'cd '${MK_MOUTPONIT}';
export HTTP_PROXY=\"${HTTP_PROXY}\";
export http_proxy=\"${http_proxy}\";
export HTTPS_PROXY=\"${HTTPS_PROXY}\";
export https_proxy=\"${https_proxy}\";
export NO_PROXY=\"${NO_PROXY}\";
export no_proxy=\"${no_proxy}\";
export -p ;
echo \"Test internet capable ...\" ;
curl -I www.google.com ;
echo \"with user \$(id -a) ...\" ; sleep 10 ;
bash entropy-make-core.sh ;'"
