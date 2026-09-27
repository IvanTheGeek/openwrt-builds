#!/usr/bin/env bash
# set-site-psk.sh: write, or check, a site layer's Wi-Fi passphrase file in the PRIVATE overlay repo:
#   $OPENWRT_PRIVATE_CLONE/sites/<site>/files/etc/homelab/site/wifi.psk   (one line, mode 0600)
# Laptop side (the canonical openwrt-private clone lives there). It holds no site value itself.
#
#   set-site-psk.sh <site>                    the owner types the passphrase into a desktop dialog, twice
#   set-site-psk.sh <site> --from-file FILE   take it from FILE (0600/0400, owned by you), e.g. a scratch
#                                             copy the owner already entered through a dialog
#   set-site-psk.sh <site> --check            is the file there, 0600, one line, 8-63 printable ASCII,
#                                             and not the repository placeholder? Prints yes/no only.
#
# The value is read with the `read` builtin and written with the `printf` builtin: never in an argv,
# never printed, never logged. The repository ships the file as a PLACEHOLDER line carrying the marker
# @@UNSET-SECRET@@; build.sh refuses any overlay that still carries that marker, and so does this tool.
# Before the dialog form, announce the dialog in chat: which secret (the site's Wi-Fi passphrase),
# what it opens (that site's Wi-Fi), the action (ENTER the existing passphrase to STORE it; nothing is
# unlocked), and why now.
# Afterwards never run `cat`, `git diff`, `git show` or `git log -p` on that path where others can see
# the output; use `git diff --stat` and `git status --short`. Never name the file *.plain (git-ignored,
# yet rsync would still ship it to the build host).
set -euo pipefail
export LC_ALL=C
site=${1:?usage: $0 <site> [--from-file FILE | --check]}
mode=${2:-dialog}
case "$site" in */* | .* | '') echo "bad site name" >&2; exit 2 ;; esac
PRIV=${OPENWRT_PRIVATE_CLONE:-$HOME/openwrt-private}
[ -d "$PRIV/sites/$site/files" ] || { echo "no site layer at $PRIV/sites/$site/files" >&2; exit 2; }
dest=$PRIV/sites/$site/files/etc/homelab/site/wifi.psk
marker='@@UNSET''-SECRET@@'

# valid FILE: one line of 8-63 printable ASCII that is not the placeholder. Sets nothing visible.
valid() {
	local v=''
	[[ -f $1 && ! -L $1 ]] || return 1
	(($(tr -cd '\n' < "$1" | wc -c) <= 1)) || return 1
	IFS= read -r v < "$1" || [[ -n $v ]] || return 1
	[[ $v != *"$marker"* ]] || return 3
	((${#v} >= 8 && ${#v} <= 63)) || return 1
	[[ $v != *[!\ -~]* ]] || return 1
	return 0
}

# store SRC: copy SRC's single line into $dest as one LF-terminated line, 0600, atomically. The temp
# file must sit beside $dest for the rename; the EXIT trap removes it if anything stops us first, and
# build.sh refuses an overlay that still carries a .psk-* file.
tmpnew=''
cleanup() { rm -f "${tmpnew:-}" "${a:-}" "${b:-}"; [ -z "${tdir:-}" ] || rmdir "$tdir" 2> /dev/null || true; }
trap cleanup EXIT
store() {
	local v=''
	IFS= read -r v < "$1" || true
	mkdir -p "$(dirname "$dest")"
	tmpnew=$(mktemp "$(dirname "$dest")/.psk-new.XXXXXX")
	printf '%s\n' "$v" > "$tmpnew"
	v=''
	chmod 600 "$tmpnew"
	mv -f "$tmpnew" "$dest"
	tmpnew=''
	echo "written: $dest (mode $(stat -c %a "$dest")); content not shown"
}

case "$mode" in
--check)
	rc=0; valid "$dest" || rc=$?
	case $rc in
	0) m=$(stat -c %a "$dest"); echo "ok: $dest is one valid line (mode $m$([ "$m" = 600 ] || echo ', NOT 0600: chmod 600 it'))"; [ "$m" = 600 ] ;;
	3) echo "PLACEHOLDER: $dest still holds the repository placeholder" >&2; exit 1 ;;
	*) echo "INVALID: $dest is missing, not one line, or not 8-63 printable ASCII (content not shown)" >&2; exit 1 ;;
	esac
	;;
--from-file)
	src=${3:?--from-file needs a path}
	[[ -f $src && ! -L $src && -O $src ]] || { echo "$src: missing, a symlink, or not owned by $(id -un)" >&2; exit 2; }
	case $(stat -c %a -- "$src") in 600 | 400) ;; *) echo "$src must be mode 0600 or 0400" >&2; exit 2 ;; esac
	rc=0; valid "$src" || rc=$?
	[ "$rc" = 0 ] || { echo "$src is not one line of 8-63 printable ASCII (or is the placeholder): nothing written" >&2; exit 1; }
	umask 077
	store "$src"
	;;
dialog)
	# The display: read it from logind, never hardcode it (a real seat is :0, an xrdp session :10).
	sid=$(loginctl list-sessions --no-legend | awk -v u="$USER" '$3 == u { print $1; exit }')
	disp=$(loginctl show-session "$sid" -p Display --value 2>/dev/null || true)
	[ -n "$disp" ] || { echo "no graphical session for $USER: the owner cannot see a dialog; stop" >&2; exit 3; }
	umask 077
	# The two dialog captures live OUTSIDE the repository: a private directory on a tmpfs
	# ($XDG_RUNTIME_DIR, 0700), never the overlay tree that git and build.sh read.
	tdir=$(mktemp -d "${XDG_RUNTIME_DIR:-/dev/shm}/set-site-psk.XXXXXX")
	a=$(mktemp "$tdir/a.XXXXXX"); b=$(mktemp "$tdir/b.XXXXXX")
	ask() { DISPLAY="$disp" XAUTHORITY="$HOME/.Xauthority" /usr/bin/ssh-askpass "$1" > "$2"; }
	ask "Site $site Wi-Fi passphrase (the one in use today). It will be STORED in openwrt-private." "$a" ||
		{ echo "dialog cancelled: nothing written" >&2; exit 1; }
	ask "The same passphrase again, to confirm." "$b" || { echo "dialog cancelled: nothing written" >&2; exit 1; }
	cmp -s "$a" "$b" || { echo "the two entries differ: nothing written" >&2; exit 1; }
	valid "$a" || { echo "not one line of 8-63 printable ASCII characters: nothing written" >&2; exit 1; }
	store "$a"
	;;
*) echo "usage: $0 <site> [--from-file FILE | --check]" >&2; exit 2 ;;
esac
