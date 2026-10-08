# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

Vagrant environment that creates a Windows 11 VM and builds KiCad (master,
x64) inside it. The host only runs Vagrant and thin wrappers; source and build
artifacts live on the VM disk under `C:\dev`.

| Path | Role |
|---|---|
| `Vagrantfile` | VM definition; defaults derived from host RAM/CPUs, overridable with `KICAD_VM_*` |
| `scripts/provision.ps1` | Runs in the guest: Git, Visual Studio 2022 C++, OpenSSH server |
| `scripts/kicad.ps1` | Runs in the guest (`C:\dev\tools\kicad.ps1`): bootstrap, configure, build, test, run, update |
| `bin/kicad-vm` | Host wrapper for macOS/Linux (bash) |
| `bin/kicad-vm.ps1` | Host wrapper for Windows hosts; keep its commands in sync with `bin/kicad-vm` |
| `README.md` | User documentation; update it whenever behavior changes |

## Workflow

```bash
./bin/kicad-vm up            # create + provision
./bin/kicad-vm ssh-config    # key + "kicad-win-dev" host in ~/.ssh/config
./bin/kicad-vm init          # clone KiCad, kicad-win-builder, vcpkg
caffeinate -is ./bin/kicad-vm configure Debug
caffeinate -is ./bin/kicad-vm build Debug
```

Source edits are made from the host through SSH (VS Code Remote-SSH on
`kicad-win-dev`, folder `C:\dev\kicad`). Do not add shared folders: building
KiCad over a shared mount is slow and breaks on path length/case issues.

Running a guest command directly is often more convenient than WinRM:

```bash
ssh kicad-win-dev "powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\tools\kicad.ps1 -Action build -Configuration Debug"
```

After editing `scripts/kicad.ps1` or `scripts/provision.ps1`, run
`vagrant provision` so the guest copy is updated.

## Things learned the hard way

- **Apple Silicon hosts get a Windows 11 ARM64 guest.** VirtualBox cannot run
  an x64 guest there. MSVC's `Hostarm64\x64` toolset cross-compiles x64 KiCad,
  which runs under emulation (`kicad-cli` reports "x64 on arm64").
- **vcpkg's binary cache from KiCad CI almost never matches on ARM64**, so the
  first `configure` builds ~150 packages from source (several hours). Later
  configures reuse the local cache and take under a minute. A full Debug build
  takes ~1h40 with 6 vCPUs.
- **Long commands:** WinRM's default 2h limit is raised to `PT24H` in the
  `Vagrantfile`. Over SSH, use `ServerAliveInterval`; guest processes keep
  running if the SSH session drops.
- **Host sleep pauses the VM** (`HostSuspend`) and VirtualBox on macOS does not
  resume it; `controlvm resume` is refused. Recover with
  `VBoxManage controlvm <id> savestate` then `vagrant up --no-provision`.
  Wrap long runs in `caffeinate -is`.
- **The default box's `sshd_config` lacks `Match Group administrators`**;
  `provision.ps1` adds it, otherwise key auth fails for `vagrant`.
- **Defender is active in the box** and slows builds. Excluding `C:\dev` is a
  security trade-off for the user to decide; do not add it on your own.
- A stale, inaccessible VM registered in VirtualBox makes `vagrant up` fail
  (`E_ACCESSDENIED` on `showvminfo`); the user must unregister it.

## Conventions

- PowerShell files use CRLF, shell files and `Vagrantfile` use LF
  (`.gitattributes`). Code, comments, and docs are in English.
- Validate the `Vagrantfile` with `vagrant validate` after changes.
- Never run `destroy` or delete anything under `C:\dev` without asking: it holds
  the user's source tree and hours of vcpkg/build output.

## Commits

- End commit messages with the trailer `Assisted-by: AI`.
- Do not add `Co-Authored-By` lines and do not mention any model name.
- Commit and push only when asked (`origin` is
  `github.com/s-celles/kicad-dev-vagrant`).
