# Foxyn Installer

Foxyn Installer is the separate installer project for FoxynBSD. Its intended
architecture is a GNUstep graphical frontend and a privileged Ruby backend.
See [FoxynBSD issue #16](https://github.com/FoxynBSD/FoxynBSD/issues/16).

## Current status

This is an early, **read-only prototype**. It cannot discover disks, assess
hardware, run an installation, or create a bootable system. The requested
installer frontends and ISO integration do not yet exist. Do not use this as
an installer. The backend reports the unavailable checks as blocking and
always refuses `install`; a review is illustrative and its caller-supplied
target identity is not verified.

## Run and test

Ruby and its standard JSON library are required. No gems are needed.

```sh
ruby test/service_test.rb
ruby test/hardware_test.rb
printf '%s\n' '{"version":1,"id":1,"operation":"capabilities"}' | bin/foxyn-installer-backend
```

The backend reads one JSON request per line and emits one JSON response per
line, keeping `id` for correlation. `version` is currently `1`. Supported
operations are `capabilities`, `check-hardware`, `plan`, and `install`.
`check-hardware` reads the architecture, CPU model and physical memory on
DragonFly, reporting unavailable values rather than guessing. It also records
whether the kernel provides a nonempty EFI memory map. Its absence or a failed
read remains unknown and is not classified as BIOS. These are
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

The wire protocol and the model may change before a stable release. No
privileged service, authentication boundary, executable installation steps,
logging or recovery mechanism has been implemented. Future work also includes
hardware compatibility data based on measured results, both GUI flows,
keyboard access, failure handling, disposable-target tests and end-to-end
installation and reboot tests.

## License

BSD 2-Clause; see [LICENSE](LICENSE).
