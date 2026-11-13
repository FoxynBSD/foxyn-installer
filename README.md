# Foxyn Installer

Foxyn Installer is the separate installer project for FoxynBSD. Its intended
architecture is a GNUstep graphical frontend and a privileged Ruby backend.
See [FoxynBSD issue #16](https://github.com/FoxynBSD/FoxynBSD/issues/16).

## Current status

This is an early, **read-only prototype**. It can list some locally attached devices, but cannot assess
hardware, verify a target, run an installation, or create a bootable system. The requested
installer frontends and ISO integration do not yet exist. Do not use this as
an installer. The backend reports the unavailable checks as blocking and
always refuses `install`; a review is illustrative and its caller-supplied
target identity is not verified.

## Run and test

Ruby and its standard JSON library are required. No gems are needed.

```sh
ruby test/service_test.rb
ruby test/disks_test.rb
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

`check-hardware` currently returns an incomplete, blocking result. `install`
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

The wire protocol and the model may change before a stable release. No
privileged service, authentication boundary, executable installation steps,
logging or recovery mechanism has been implemented. Future work also includes
hardware compatibility data based on measured results, both GUI flows,
keyboard access, failure handling, disposable-target tests and end-to-end
installation and reboot tests.

## License

BSD 2-Clause; see [LICENSE](LICENSE).
