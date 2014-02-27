#!/bin/bash
set -e

function apt_get_install()
{
	apt-get install -q -y --force-yes --no-install-recommends "$@"
}

export DEBIAN_FRONTEND=noninteractive

set -x

if ! grep -q setterm /etc/rc.local; then
	sed -i 's/^exit 0$//' /etc/rc.local
	cat >>/etc/rc.local <<-EOF
	# Increase kernel logging level. This ensures that all kernel
	# messages are forwarded to the log host through netconsole.
	dmesg -n 7

	# Disable Linux console blanking so that we can see kernel panics
	setterm -blank 0 </dev/console >/dev/console
	setterm -powerdown 0 </dev/console >/dev/console
	setterm -powersave off </dev/console >/dev/console
	EOF
fi

dmesg -n 7
setterm -blank 0 </dev/console >/dev/console
setterm -powerdown 0 </dev/console >/dev/console
setterm -powersave off </dev/console >/dev/console

if ! [[ -e /etc/apt/sources.list.d/brightbox.list ]]; then
	apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C3173AA6
	echo deb http://ppa.launchpad.net/brightbox/ruby-ng/ubuntu precise main > /etc/apt/sources.list.d/brightbox.list
fi

apt-get update
apt_get_install ruby2.1 ruby-switch wget
ruby-switch --set ruby2.1
