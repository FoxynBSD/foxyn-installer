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
printf '%s\n' '{"version":1,"id":1,"operation":"capabilities"}' | bin/foxyn-installer-backend
```

The backend reads one JSON request per line and emits one JSON response per
line, keeping `id` for correlation. `version` is currently `1`. Supported
operations are `capabilities`, `check-hardware`, `plan`, and `install`.
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

The backend runs with the frontend's privileges. No privilege boundary or
installation operations are implemented yet. Hardware checks can be incomplete
or unavailable to an unprivileged user. Do not use this prototype for an
installation.

In an existing FoxynBSD QEMU desktop with Eau, the window was built with
GNUstep Make and displayed both the backend's blocking finding and the error
for a missing backend ([blocked](docs/screenshots/qemu-backend-blocked.png),
[unavailable](docs/screenshots/qemu-backend-unavailable.png)). This does not
validate keyboard navigation or an installation. Backend queries run on a worker thread with a five-second deadline and a
64 KiB response limit. A deliberately unresponsive backend produced the
[timeout message](docs/screenshots/qemu-backend-timeout.png) in QEMU. More
error-path, keyboard and privilege-boundary testing is required before use.

Manual backend error probes are in `frontend/test-backends/`: point
`FOXYN_INSTALLER_BACKEND` at the absolute path of `hang.sh`,
`large-response.sh` or `exit-immediately.sh`, then launch the app. In QEMU,
the latter two produced the [large-response](docs/screenshots/qemu-backend-large.png)
and [invalid-response](docs/screenshots/qemu-backend-exit.png) messages. These
are single manual observations and do not establish behavior under every timing
or failure condition.
