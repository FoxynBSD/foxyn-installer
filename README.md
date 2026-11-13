# Foxyn Installer

Foxyn Installer is the separate installer project for FoxynBSD. Its intended
architecture is a GNUstep graphical frontend and a privileged Ruby backend.
See [FoxynBSD issue #16](https://github.com/FoxynBSD/FoxynBSD/issues/16).

## Current status

This is an early prototype. Its exposed protocol is read-only and can list
some locally attached devices, but cannot assess hardware, verify a target,
run an installation, or create a bootable system. An internal copy operation
is testable on disposable trees but is not exposed by the protocol. The
installer workflows and ISO integration do not yet exist. Do not use this as
an installer. The backend reports the unavailable checks as blocking and
always refuses `install`; a review is illustrative and its caller-supplied
target identity is not verified.

## Run and test

Ruby and its standard JSON library are required. No gems are needed.

```sh
ruby test/boot_configuration_test.rb
ruby test/system_copy_test.rb
ruby test/command_test.rb
ruby test/service_test.rb
ruby test/disks_test.rb
ruby test/hardware_test.rb
ruby test/integration_test.rb
ruby test/read_only_server_test.rb
printf '%s\n' '{"version":1,"id":1,"operation":"capabilities"}' | bin/foxyn-installer-backend
```

The backend reads one JSON request per line and emits one JSON response per
line, keeping `id` for correlation. `version` is currently `1`. Supported
operations are `capabilities`, `check-hardware`, `list-disks`, `plan`, and `install`.
`list-disks` reads `kern.disks`, probes physical-looking devices using
DragonFly's `diskinfo`, and compares device numbers with `/dev/serno` aliases.
It reports size and serial when available. It also lists mounted filesystems
and attempts to associate their source device numbers with already-present
whole-disk and slice nodes. A match is evidence of a mounted disk, but an
empty match is not proof a disk is unused: aliases, device layering, live
media and busy but unmounted devices are not comprehensively resolved. Model,
bus and target safety are not established; access permissions and device support can prevent discovery.
Memory and virtual `md`/`vn` devices are listed without opening them. This
inventory may open other device nodes read-only and may cause their normal
kernel probing. The output may contain sensitive serial numbers. It has been
exercised on QEMU virtio disks, not physical hardware.


`check-hardware`, `plan`, and `install`.
`check-hardware` reads the architecture, CPU model and physical memory on
DragonFly, reporting unavailable values rather than guessing. It also records
whether the kernel provides a nonempty EFI memory map. Its absence or a failed
read remains unknown and is not classified as BIOS. It reports PCI devices
shown as unattached by `pciconf`, including vendor and device IDs; a failed
PCI inventory is distinguished from an empty result. Network interface
flags and any link status are recorded without addresses. They do not prove
connectivity, and an unavailable interface inventory remains a blocker. These are
observations, not a compatibility verdict: boot mode validation, CPU features, measured
minimums, display, input, network and target-disk checks are still missing.
The result remains incomplete and blocking. `install`

returns `accepted: false` and performs no changes.

A plan describes a whole-disk GPT/UEFI layout, the selected root filesystem
and components. It requires caller-supplied `mode`, `filesystem`, `components`
and a `target` object with `device`, `model`, `serial` and `size_bytes`.
Simple mode requires HAMMER2 and desktop. Advanced mode can describe HAMMER2
or UFS and base with an optional desktop. Every plan has `executable: false`
and `target_verified: false`. It is not a hardware compatibility check,
confirmation, authorization or guarantee that the requested layout can be
created. Actual execution must discover the device independently, bind the
review and confirmation to its identity, recheck it immediately before any
write, and reject busy/live media and unsafe configurations.

The wire protocol and the model may change before a stable release. The
read-only service and system-copy building block described below are
experimental; no production privilege boundary, end-to-end installation,
installation logging or recovery mechanism has been implemented. Future work also includes
hardware compatibility data based on measured results, both GUI flows,
keyboard access, failure handling, disposable-target tests and end-to-end
installation and reboot tests.

## License

BSD 2-Clause; see [LICENSE](LICENSE).

## Experimental GNUstep frontend

`frontend/` contains an initial status window. It is not an installer wizard:
it displays the backend's hardware findings and has no installation action.
It requires the session's GNUstep GUI and an absolute backend path:

```sh
. /System/Library/Makefiles/GNUstep.sh
cd frontend && gmake
FOXYN_INSTALLER_BACKEND=/absolute/path/to/bin/foxyn-installer-backend \
  openapp FoxynInstaller.app
```

In the command above the backend runs with the frontend's privileges. An
experimental read-only service is described below; no privilege boundary for
installation operations is implemented. Hardware checks can be incomplete
or unavailable to an unprivileged user. Do not use this prototype for an
installation.

In an existing FoxynBSD QEMU desktop with Eau, the window was built with
GNUstep Make and displayed both the backend's blocking finding and the error
for a missing backend ([blocked](docs/screenshots/qemu-backend-blocked.png),
[unavailable](docs/screenshots/qemu-backend-unavailable.png)). This does not validate an installation. Backend queries run on a worker thread with a five-second deadline and a
64 KiB response limit. A deliberately unresponsive backend produced the
[timeout message](docs/screenshots/qemu-backend-timeout.png) in QEMU. More error-path and privilege-boundary testing is required before use.

Manual backend error probes are in `frontend/test-backends/`: point
`FOXYN_INSTALLER_BACKEND` at the absolute path of `hang.sh`,
`large-response.sh` or `exit-immediately.sh`, then launch the app. In QEMU,
the latter two produced the [large-response](docs/screenshots/qemu-backend-large.png)
and [invalid-response](docs/screenshots/qemu-backend-exit.png) messages. These
are single manual observations and do not establish behavior under every timing
or failure condition.

On the same QEMU desktop, an earlier version used Tab to move focus visibly
between [Check again](docs/screenshots/qemu-keyboard-refresh.png) and
[Quit](docs/screenshots/qemu-keyboard-quit.png). Space triggered a second
backend invocation on Check again and closed the window on Quit. This covers
only the current status window; the future installation flows and other
accessibility needs remain untested.

The findings area now scrolls. With `frontend/test-backends/many-findings.rb`,
Tab and Space reached the [last of 20 findings](docs/screenshots/qemu-findings-last.png)
using More and returned to the [first](docs/screenshots/qemu-findings-first.png)
using Earlier. This was checked in the existing QEMU desktop; it does not
validate screen-reader support or future installer flows.

The combined prototype's backend and frontend were exercised together on the
existing FoxynBSD QEMU desktop. Its [unprivileged window](docs/screenshots/qemu-integrated-unprivileged.png)
reported that the PCI inventory could not be read, alongside the overall
hardware blocker. A supported privilege boundary for the real backend is
still needed; this test did not grant additional privileges to the GUI.
Run `ruby test/integration_test.rb` to check service routing with fixtures.

The GitHub Actions workflow runs the Ruby syntax and fixture tests on Linux.
It does not compile GNUstep or test DragonFly devices, a QEMU desktop, or an
installation; those checks remain separate.

On a writable FoxynBSD test system, `test/foxyn-smoke.sh` runs the backend
checks and verifies that hardware remains incomplete and installation is
refused. `test/foxyn-smoke.sh --build-gui` also compiles the GNUstep window.
The smoke test inventories devices but never calls an installation operation
that writes; device probing has the limitations described above. It does not
launch the GUI or test a live ISO or installed system.

## Experimental read-only privilege separation

`foxyn-installer-readonlyd` is a prototype daemon intended to be started
manually as root with one authorized numeric user ID. It creates a private
root-controlled directory in `/var/run`, checks the connecting user's
`getpeereid`, and exposes only capabilities, hardware observations, disk
inventory and non-executable plans. Install requests are refused. The
`foxyn-installer-readonly-client` verifies socket permissions and the server's
root peer credential; it reads `FOXYN_INSTALLER_SOCKET` and can be used as
`FOXYN_INSTALLER_BACKEND` for the status window.

This is not a production privilege boundary. The daemon must only be run from
root-owned, non-user-writable files and a sanitized environment. It has no
service integration, security review or durable startup/cleanup design. Each
external system probe has a five-second deadline and a 1 MiB output
limit. Each service request also runs in a separate process with a 3.5-second
deadline; the server attempts to terminate its process group on timeout. It
must not be made setuid or exposed to
untrusted users. Disk inventory may trigger kernel probing as described above.
In a disposable QEMU guest, a manually started daemon let the authorized
user query PCI details, denied another user, and refused an install request.
The [GUI showed the resulting finding](docs/screenshots/qemu-privileged-readonly.png).
These checks do not establish safety for privileged installation operations.

## Internal system-copy experiment

`SystemCopy` is an internal, unexposed building block for copying the system
directories using `/bin/cpdup`. It requires an empty destination, rejects
obvious overlapping trees, reports progress per directory and stops on a
copy error. A subsequent scan restores cross-directory hardlinks after
checking that copied contents match. Its caller must control both trees and
prevent concurrent path
replacement; it does not validate or mount a disk. No RPC invokes it.

On the QEMU FoxynBSD guest, `test/system_copy_test.rb` copied only synthetic
temporary files and checked their contents, mode, symlink and hardlinks both
within and across copied directories. A fixture verifies that mismatched
copies are not overwritten when links are restored. Tests also cover an
injected failure and unsafe paths. This does not verify full system copies,
separately mounted source directories, disk failures, cancellation, bounded
output or installation/reboot. Those and the
target authorization remain necessary before connecting it to the installer.

A separate QEMU run used an older FoxynBSD base root ISO (kernel build
`961c22b04b`) as the source and a newly created 6 GiB virtio disk, formatted
UFS, as the disposable destination. The root ISO was read-only, while `/etc`,
`/var` and `/root` were separate tmpfs mounts. `SystemCopy` returned success
for all nine listed directories; byte comparisons passed for `/bin/sh`,
`/etc/rc.conf`, `/usr/bin/ruby` and `/boot/kernel/kernel`. The mounted copy
used approximately 624 MiB and was unmounted before the VM shut down. The
source scan found no hardlink pairs in that image, so this run adds no evidence
about hardlink preservation. It did not copy a desktop installation, verify
all files or metadata, configure a boot loader, install a user, or boot the
copied disk. A first attempt using a separately hot-plugged USB disk timed out
in `newfs`; it was detached, and the cause was not established.

## Internal boot-configuration experiment

`BootConfiguration` is not exposed by the protocol. Given a trusted target
tree with an already mounted ESP, it writes UFS or HAMMER2 `fstab` entries
using distinct GPT slice UUIDs, creates matching loader configurations on
the root and ESP, and removes the live root-write setting from `rc.conf`.
It rejects malformed UUIDs, unsupported values, the running root path and
symlink configuration paths. Files are replaced one at a time; an error can
leave a partially updated target. The caller must control the target tree and
prevent path races. No disk identity check, partitioning, ESP mount, EFI loader
copy, durability guarantee or rollback is implemented by this operation.

In QEMU, tests passed on a disposable copy of the older base image described
above using fixture UUIDs and a directory in place of an ESP. The two loader
files matched and the generated UFS `fstab` was inspected. The fixture UUIDs
do not identify real GPT partitions, and the resulting disk was not booted.
