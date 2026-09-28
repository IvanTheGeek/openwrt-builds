#!/usr/bin/env bash
# set-site-bh-key.sh: generate, check or rotate a site layer's BACKHAUL key (the WPA3-SAE key of a wireless
# link between two of the site's own units) in the PRIVATE overlay repo:
#   $OPENWRT_PRIVATE_CLONE/sites/<site>/files/etc/homelab/site/backhaul.psk   (one line, mode 0600)
# Laptop side, a sibling of set-site-psk.sh (same repo discovery, same file rules, same atomic store). It
# holds no site value itself. Nobody ever types this key: it is random, and it lives only in the private
# repo, the images built from it and the units.
#
#   set-site-bh-key.sh <site> --generate   write a NEW random key (63 characters of [A-Za-z0-9]); refuses
#                                          unless the file is missing or still the repository placeholder
#   set-site-bh-key.sh <site> --check      is it there, 0600, one line, 63 [A-Za-z0-9], not the placeholder,
#                                          and different from the site's wifi.psk? Prints yes/no only.
#   set-site-bh-key.sh <site> --rotate --both-ends-on-site
#                                          overwrite an existing key. A new key splits the link until BOTH
#                                          units carry it, and a unit whose only uplink is that link is then
#                                          cut off: rotate only with a person on site at both units.
#
# The key comes from /dev/urandom through `tr -dc` into bash's `read` builtin (a process substitution:
# laptop bash, never a router shell) and is written with the `printf` builtin into a temp file beside
# the target (.psk-bh.XXXXXX, so build.sh's .psk-* stray guard covers a crash), then renamed. It is never
# in an argv, never printed, never logged: the output names the file, its mode and a 12-hex sha256 digest.
# BHKEY_RANDOM (tests only) replaces /dev/urandom as the random source. It is honored only with BHKEY_TEST=1,
# never for a repository under the user's own ~/openwrt-private, and then says so on stderr: a predictable
# source would otherwise become a stored key that --check calls ok. Refused under xtrace (it would print the key).
# Afterwards never run `cat`, `git diff`, `git show` or `git log -p` on that path where others can see the
# output; use `git diff --stat` and `git status --short`.
set -euo pipefail
case $- in *x*) echo "refusing to run with xtrace (bash -x / set -x): it would print the key" >&2; exit 2 ;; esac
export LC_ALL=C
site=${1:?usage: $0 <site> --generate | --check | --rotate --both-ends-on-site}
mode=${2:?usage: $0 <site> --generate | --check | --rotate --both-ends-on-site}
case "$site" in */* | .* | '') echo "bad site name" >&2; exit 2 ;; esac
PRIV=${OPENWRT_PRIVATE_CLONE-$HOME/openwrt-private}
[ -n "$PRIV" ] || { echo "OPENWRT_PRIVATE_CLONE is set but empty: refusing to guess the repository" >&2; exit 2; }
[ -d "$PRIV/sites/$site/files" ] || { echo "no site layer at $PRIV/sites/$site/files" >&2; exit 2; }
dest=$PRIV/sites/$site/files/etc/homelab/site/backhaul.psk
wifi=$PRIV/sites/$site/files/etc/homelab/site/wifi.psk
marker='@@UNSET''-SECRET@@'
LEN=63
RND=/dev/urandom
if [ -n "${BHKEY_RANDOM+x}" ]; then
	[ "${BHKEY_TEST:-0}" = 1 ] || { echo "BHKEY_RANDOM is a test hook: refused without BHKEY_TEST=1" >&2; exit 2; }
	here=$(realpath -m -- "$PRIV")
	for h in "$HOME" "$(getent passwd "$(id -un)" | cut -d: -f6)"; do
		[ -n "$h" ] || continue
		case "$here/" in "$(realpath -m -- "$h/openwrt-private")/"*)
			echo "BHKEY_RANDOM refused: $PRIV is the real private repository" >&2; exit 2 ;;
		esac
	done
	echo "TEST RANDOM SOURCE ($BHKEY_RANDOM): the key written is NOT a usable key" >&2
	RND=$BHKEY_RANDOM
fi

# state FILE: 0 = a valid key, 3 = the placeholder, 4 = missing, 1 = anything else. Sets nothing visible.
state() {
	local v=''
	[[ -e $1 || -L $1 ]] || return 4
	[[ -f $1 && ! -L $1 ]] || return 1
	(($(tr -cd '\n' < "$1" | wc -c) <= 1)) || return 1
	IFS= read -r v < "$1" || [[ -n $v ]] || return 1
	[[ $v != *"$marker"* ]] || return 3
	((${#v} == LEN)) || return 1
	[[ $v != *[!A-Za-z0-9]* ]] || return 1
	return 0
}
# same_as_wifi FILE: the key equals the site's Wi-Fi passphrase (compared in the shell, never shown)
same_as_wifi() {
	local a='' b=''
	[[ -f $wifi && ! -L $wifi ]] || return 1
	IFS= read -r a < "$1" || true
	IFS= read -r b < "$wifi" || true
	[[ -n $a && $a == "$b" ]]
}
digest() { sha256sum "$1" | cut -c1-12; }

tmpnew=''
cleanup() { rm -f "${tmpnew:-}"; }
trap cleanup EXIT
generate() {
	local k='' n=0
	mkdir -p "$(dirname "$dest")"
	umask 077
	tmpnew=$(mktemp "$(dirname "$dest")/.psk-bh.XXXXXX")
	while :; do
		k=''
		IFS= read -r -N "$LEN" k < <(tr -dc 'A-Za-z0-9' < "$RND" 2> /dev/null) || true
		if ((${#k} != LEN)) || [[ $k == *[!A-Za-z0-9]* ]]; then
			k=''; echo "the random source gave a short or invalid read: nothing written" >&2; exit 1
		fi
		printf '%s\n' "$k" > "$tmpnew"
		k=''
		same_as_wifi "$tmpnew" || break
		n=$((n + 1)); ((n < 3)) || { echo "three keys in a row equal the Wi-Fi passphrase?! nothing written" >&2; exit 1; }
	done
	chmod 600 "$tmpnew"
	state "$tmpnew" || { echo "the generated file does not check out: nothing written" >&2; exit 1; }
	mv -f "$tmpnew" "$dest"
	tmpnew=''
	echo "written: $dest ($LEN chars, mode $(stat -c %a "$dest"), sha256 digest $(digest "$dest")); content not shown"
}

case "$mode" in
--check)
	rc=0; state "$dest" || rc=$?
	case $rc in
	0)
		if same_as_wifi "$dest"; then echo "INVALID: $dest equals the site's Wi-Fi passphrase (neither shown)" >&2; exit 1; fi
		m=$(stat -c %a "$dest")
		echo "ok: $dest is one valid key line (mode $m$([ "$m" = 600 ] || echo ', NOT 0600: chmod 600 it'), sha256 digest $(digest "$dest"))"
		[ "$m" = 600 ] ;;
	3) echo "PLACEHOLDER: $dest still holds the repository placeholder" >&2; exit 1 ;;
	4) echo "MISSING: $dest does not exist" >&2; exit 1 ;;
	*) echo "INVALID: $dest is not one line of $LEN [A-Za-z0-9] characters (content not shown)" >&2; exit 1 ;;
	esac
	;;
--generate)
	rc=0; state "$dest" || rc=$?
	case $rc in
	3 | 4) generate ;;
	0) echo "$dest already holds a key: --generate never overwrites one (see --rotate)" >&2; exit 1 ;;
	*) echo "$dest holds something that is neither a key nor the placeholder: nothing written; look at it by hand (without printing it)" >&2; exit 1 ;;
	esac
	;;
--rotate)
	[ "${3:-}" = --both-ends-on-site ] || {
		echo "--rotate splits the link until BOTH units carry the new key; a unit whose only uplink it is gets cut off." >&2
		echo "Rotate only with a person at both units: $0 $site --rotate --both-ends-on-site" >&2
		exit 2
	}
	generate
	;;
*) echo "usage: $0 <site> --generate | --check | --rotate --both-ends-on-site" >&2; exit 2 ;;
esac
