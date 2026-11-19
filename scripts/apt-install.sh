#!/usr/bin/env bash
# apt-install.sh <package>...: installs Ubuntu packages in a CI container, riding out mirror
# outages (#269). Each apt call retries its own downloads with a timeout, the whole update and
# install is tried five times with a growing pause, and from the third try on the container reads
# Azure's Ubuntu mirror, which GitHub's runners sit beside, in place of archive/security.ubuntu.com.
set -u
opts=(-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30)
for try in 1 2 3 4 5; do
  if [ "$try" -ge 3 ]; then
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
      [ -f "$f" ] && sed -i -E 's#https?://(archive|security)\.ubuntu\.com#http://azure.archive.ubuntu.com#g' "$f"
    done
  fi
  if apt-get "${opts[@]}" update && apt-get "${opts[@]}" install -y "$@"; then
    exit 0
  fi
  [ "$try" -lt 5 ] && { echo "apt-install: try $try failed, trying again in $((try * 20))s"; sleep $((try * 20)); }
done
echo "apt-install: could not install $* after 5 tries" >&2
exit 1
