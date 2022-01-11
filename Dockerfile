from ubuntu:20.04 as base-ubuntu

run apt -y update
run apt -y upgrade
run apt -y autoremove

run apt -y install systemd less vim net-tools apt-utils
run apt install -y --no-install-recommends systemd-sysv

# General build environment

from base-ubuntu as builder

run apt -y install build-essential git make wget

# JALV

from builder as jalv

run git clone https://github.com/drobilla/jalv.git

run apt -y install debhelper-compat libgtk-3-dev libjack-dev liblilv-dev libserd-dev libsord-dev libsratom-dev libsuil-dev lv2-dev pkg-config python3

run update-alternatives --install /usr/bin/python python /usr/bin/python3 1

workdir jalv

run git checkout v1.6.4

run git submodule update --init --recursive

add jalv-v1.6.4-oslp.patch .

run patch -p1 < jalv-v1.6.4-oslp.patch

run ./waf configure --prefix=/usr

run ./waf

run ./waf install --destdir=/jalv-install

# lilv for python

from builder as lilvpy

run apt install -y python3 pkg-config lv2-dev libserd-dev libsord-dev libsratom-dev libsndfile-dev \
                   python3-distutils

run update-alternatives --install /usr/bin/python python /usr/bin/python3 1

run git clone https://github.com/lv2/lilv.git

workdir lilv

run git checkout v0.24.6

run git submodule update --init --recursive

run ./waf configure --prefix=/usr

run ./waf

run ./waf install

# Build few more LV2 plugins in the same build environment

workdir /

run git clone https://github.com/unclechu/lv2-stereo-mixer.git

workdir lv2-stereo-mixer

run make

# Jack Audio Tools (LV2) https://github.com/SpotlightKid/jack-audio-tools

from builder as jad

run git clone https://github.com/SpotlightKid/jack-audio-tools.git

workdir jack-audio-tools/lv2

run chmod +x *.py

from base-ubuntu as oslp

# Install kx-studio packages

workdir /install-kx

# Install required dependencies if needed

run apt -y install apt-transport-https gpgv wget

# Download package file

run wget https://launchpad.net/~kxstudio-debian/+archive/kxstudio/+files/kxstudio-repos_10.0.3_all.deb

# Install it

run dpkg -i kxstudio-repos_10.0.3_all.deb

run apt -y update

run rm -rf /install-kx

run env DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends jackd2 a2jmidid alsa-utils \
        amsynth zynaddsubfx lilv-utils aj-snapshot helm python3 jq x11-utils x42-plugins carla \
	xterm xinit psmisc dbus-x11 locales gmrun liblilv-0-0 libsratom-0-0 libserd-0-0 libsuil-0-0 libgtk-3-0 \
	wmctrl zenity xdotool ghc xmlstarlet libxml2-utils lsp-plugins

run update-alternatives --install /usr/bin/python python /usr/bin/python3 1

add usrbin /usr/bin
add etcdefault /etc/default
add units /lib/systemd/system
run mkdir -p /usr/lib/oslp/json
add json /usr/lib/oslp/json

run systemctl enable jackd.service a2jmidid.service conlog.service makereq.service makereq.path dotghci.service
run systemctl disable systemd-resolved.service
run systemctl disable networkd-dispatcher.service
run systemctl disable console-getty.service
run systemctl disable dbus.service
run systemctl disable systemd-logind.service
run systemctl disable multi-user.target
run systemctl disable graphical.target
run systemctl set-default basic.target

run locale-gen en_US.UTF-8

# Copy from all builders

copy --from=jalv /jalv-install /

copy --from=jad /jack-audio-tools/lv2 /usr/bin

run mkdir -p /usr/lib/python3/dist-packages/

copy --from=lilvpy /usr/lib/python3/dist-packages/lilv.py /usr/lib/python3/dist-packages/

run mkdir -p /usr/lib/lv2/stereo-mixer.lv2

copy --from=lilvpy /lv2-stereo-mixer/stereo-mixer.lv2 /usr/lib/lv2/stereo-mixer.lv2

# Symlink lv2 from incorrect install locations

run ln -sf /usr/lib/x86_64-linux-gnu/liblilv-0.so.0 /usr/lib/x86_64-linux-gnu/liblilv-0.so

# Generate the Haskell plugins database

run mkdir -p /usr/lib/oslp/haskell

run /usr/bin/mkhslib >/usr/lib/oslp/haskell/PluginBase.hs

add haskell /usr/lib/oslp/haskell
add dotghci /usr/lib/oslp/haskell

workdir /usr/lib/oslp/haskell

run for f in *.hs; do echo :q | ghci $f 2>&1 | tee /dev/stderr | grep 'error:$' | wc -l | (read n; exit $n) ; done

# Install yq

run wget -qO /usr/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64

run chmod +x /usr/bin/yq

run yq --version

# Flatten image

from scratch

copy --from=oslp / /
