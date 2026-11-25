# Shared by the examples. It is read by them, it is not run on its own.
#
# The examples run from a checkout, nothing has to be installed. They need
# perl with the module IO::Pty, which keyfilter needs. They do not need a
# terminal, they use a private home directory so they never touch the files
# of the user, and they remove everything they made.

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
kf="$root/keyfilter"
ctl="$root/keyfilterctl"

tmp=$(mktemp -d)
HOME="$tmp"
export HOME
mkdir -p "$HOME/.config/keyfilter"

bg=
cleanup()
	{
	[ -n "$bg" ] && kill "$bg" 2>/dev/null
	rm -rf "$tmp"
	}
trap cleanup EXIT
trap 'exit 1' INT TERM

limit=$(command -v timeout || true)

title() { printf '== %s ==\n' "$1" ; }

show() { printf '$ %s\n' "$*" ; }

# what a person would see: control characters are made visible
visible() { printf '%s' "$1" | cat -v ; }

# bytes FORMAT: put the bytes that printf makes of FORMAT in $want
bytes()
	{
	want=$(printf "$1" ; printf x)
	want=${want%x}
	}

expect()
	{
	if [ "$2" = "$3" ]
		then
		printf '   %s: %s\n' "$1" "$(visible "$3")"
		else
		printf 'FAILED: %s\n   expected: %s\n   got:      %s\n' "$1" "$(visible "$2")" "$(visible "$3")" >&2
		exit 1
		fi
	}

contains()
	{
	case "$3" in
		*"$2"*) printf '   %s\n' "$1" ;;
		*) printf 'FAILED: %s\n   wanted: %s\n   got:    %s\n' "$1" "$(visible "$2")" "$(visible "$3")" >&2 ; exit 1 ;;
		esac
	}

done_ok() { echo OK ; }

# typed FORMAT BYTES [options]
#
# Type what printf makes of FORMAT into keyfilter, after a second so
# that the command has time to set up its terminal. The command is a shell
# that collects BYTES bytes. What it collected is left in $out.
typed()
	{
	_format=$1
	_count=$2
	shift 2
	out=$( (sleep 1 ; printf "$_format") | $limit ${limit:+30} "$kf" "$@" -- sh -c "stty raw -echo ; head -c $_count" ; printf x )
	out=${out%x}
	}

# start_instance BYTES [options]
#
# Run keyfilter in the background, with the same collecting command. Its
# input stays open on descriptor 3, type with: send_keys FORMAT
start_instance()
	{
	_count=$1
	shift
	mkfifo "$tmp/in"
	exec 3<>"$tmp/in"
	"$kf" "$@" -- sh -c "stty raw -echo ; echo ready ; head -c $_count" <"$tmp/in" >"$tmp/out" 2>"$tmp/err" &
	bg=$!
	_tries=0
	while ! grep -q ready "$tmp/out" 2>/dev/null && [ "$_tries" -lt 100 ]
		do
		sleep 0.1
		_tries=$((_tries + 1))
		done
	_tries=0
	while ! ls "$HOME"/.config/keyfilter/sockets/*.sock >/dev/null 2>&1 && [ "$_tries" -lt 100 ]
		do
		sleep 0.1
		_tries=$((_tries + 1))
		done
	sleep 0.2
	}

send_keys()
	{
	printf "$1" >&3
	sleep 0.4
	}

# finish_instance: wait for the command to have what it wanted, what it
# collected is left in $out
finish_instance()
	{
	wait "$bg"
	bg=
	out=$(tail -c +7 "$tmp/out" ; printf x)
	out=${out%x}
	}
