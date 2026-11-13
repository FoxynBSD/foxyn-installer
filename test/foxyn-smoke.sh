#!/bin/sh
# Read-only smoke test for the prototype on an already booted FoxynBSD guest.
set -eu

case ${1-} in
'') build_gui=no ;;
--build-gui) build_gui=yes ;;
*) echo 'usage: test/foxyn-smoke.sh [--build-gui]' >&2; exit 2 ;;
esac
[ "$(uname -s)" = DragonFly ] || { echo 'requires DragonFly/FoxynBSD' >&2; exit 1; }
cd "$(dirname "$0")/.."

ruby test/boot_configuration_test.rb
ruby test/system_copy_test.rb
ruby test/command_test.rb
ruby test/service_test.rb
ruby test/disks_test.rb
ruby test/hardware_test.rb
ruby test/integration_test.rb
ruby test/read_only_server_test.rb

tmpdir=$(mktemp -d /tmp/foxyn-installer-smoke.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
printf '%s\n' \
    '{"version":1,"id":"hardware","operation":"check-hardware"}' \
    '{"version":1,"id":"disks","operation":"list-disks"}' \
    '{"version":1,"id":"install","operation":"install"}' |
    bin/foxyn-installer-backend > "$tmpdir/responses.jsonl"
ruby -rjson -e '
  rows = File.readlines(ARGV.fetch(0)).map { |line| JSON.parse(line) }
  abort "unexpected response count" unless rows.size == 3
  hardware, disks, install = rows
  abort "hardware was not blocked" unless hardware["id"] == "hardware" && hardware.dig("result", "complete") == false
  abort "disk inventory failed" unless disks["id"] == "disks" && disks.dig("result", "disks").is_a?(Array) && disks.dig("result", "target_safety_checked") == false
  abort "installation was not refused" unless install["id"] == "install" && install.dig("result", "accepted") == false
  puts "Protocol smoke passed: hardware incomplete; #{disks["result"]["disks"].size} devices; installation refused"
' "$tmpdir/responses.jsonl"

if [ "$build_gui" = yes ]; then
    [ -r /System/Library/Makefiles/GNUstep.sh ] || { echo 'GNUstep Make is not installed' >&2; exit 1; }
    # GNUstep.sh reads optional unset shell variables.
    set +u
    . /System/Library/Makefiles/GNUstep.sh
    set -u
    (cd frontend && gmake)
fi
