# KiCad Windows development environment

This repository creates a reproducible Windows VM from **macOS, Linux, or
Windows**, then installs the toolchain used to develop KiCad for Windows:

- Windows 11;
- Visual Studio 2022 Community with the Desktop C++ workload;
- CMake and Ninja supplied by Visual Studio;
- Git;
- vcpkg pinned automatically to the revision used by KiCad CI;
- the official KiCad source tree and Windows x64 CMake presets.

The source and build artifacts live under `C:\dev` on the VM disk. This is much
faster and more reliable than compiling a large C++ project from a shared host
folder.

> The automated workflow targets KiCad's `master` branch and produces
> **Windows x64** binaries. On Apple Silicon, Windows 11 ARM runs the required
> tools while MSVC cross-compiles the x64 target.

## Requirements

Allow for at least:

- 16 GB of RAM for the VM (24–32 GB of host RAM recommended);
- 8 virtual CPUs by default;
- about 80 GB of free disk space;
- a connection suitable for several large downloads;
- a Windows license appropriate for your use.

RAM and CPU allocations are configurable; see [Configuration](#configuration).

## Host compatibility

| Host | Recommended provider | Notes |
|---|---|---|
| macOS Intel | VirtualBox or VMware Fusion | Windows x64 guest |
| macOS Apple Silicon | Recent VirtualBox or VMware Fusion | Windows 11 ARM guest, x64 build target |
| Linux x86_64 | libvirt/QEMU or VirtualBox | The default box publishes an AMD64 libvirt image |
| Windows Pro/Enterprise | Hyper-V | Run the terminal as Administrator |
| Windows Home | VirtualBox | Full Hyper-V is unavailable |

The default box is `gusztavvargadr/windows-11`. It is a community image that
currently publishes AMD64 and ARM64 variants. Set `KICAD_VM_BOX` to use another
box; it must support WinRM and the conventional Vagrant account.

The default development box disables Windows Update and UAC. Depending on the
box version, Microsoft Defender real-time protection may still be active and
slow the build noticeably. Keep the VM
isolated: do not use it as a general workstation or store secrets in it. For
enterprise use, select an internally maintained and hardened box instead.

## 1. Install Vagrant and a provider

### macOS

Install Vagrant:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/hashicorp-vagrant
```

Then install a provider. For VirtualBox:

```bash
brew install --cask virtualbox
```

VMware Fusion and Parallels are also declared in the `Vagrantfile`, but their
respective Vagrant plugins must be installed if you select them.

### Linux

Install Vagrant from the official HashiCorp repository, then install QEMU and
libvirt with your distribution's package manager. Finally, install the provider:

```bash
vagrant plugin install vagrant-libvirt
```

Your user account must be allowed to access libvirt. On an x86_64 host:

```bash
export VAGRANT_DEFAULT_PROVIDER=libvirt
```

VirtualBox remains an alternative with `--provider=virtualbox`.

### Windows

Install Vagrant, then enable Hyper-V in Windows Features. Open PowerShell **as
Administrator** and select the provider:

```powershell
$env:VAGRANT_DEFAULT_PROVIDER = 'hyperv'
```

On Windows Home, install VirtualBox and use:

```powershell
$env:VAGRANT_DEFAULT_PROVIDER = 'virtualbox'
```

## 2. Create the environment

Clone this repository, change into it, and start the VM.

On macOS or Linux:

```bash
./bin/kicad-vm up
./bin/kicad-vm init
```

On Windows PowerShell:

```powershell
.\bin\kicad-vm.ps1 up
.\bin\kicad-vm.ps1 init
```

`up` downloads Windows and installs Visual Studio, so the first run can take a
while. `init` then clones KiCad and prepares the exact vcpkg revision expected
by its CI. If Windows requires a restart, run:

```bash
./bin/kicad-vm reload
```

or on Windows:

```powershell
.\bin\kicad-vm.ps1 reload
```

To select another compatible tag or branch during the initial clone:

```bash
./bin/kicad-vm init my-tag
```

`master` is the only branch automated and tested by this configuration. KiCad
10.0 additionally requires SWIG and extra Python configuration; follow that
version's KiCad documentation before using it.

## 3. Configure and build

Development build:

```bash
./bin/kicad-vm configure Debug
./bin/kicad-vm build Debug
./bin/kicad-vm test Debug
./bin/kicad-vm run Debug
```

Optimized build with debug information:

```bash
./bin/kicad-vm configure Release
./bin/kicad-vm build Release
./bin/kicad-vm run Release
```

On a Windows host, replace `./bin/kicad-vm` with
`.\bin\kicad-vm.ps1`. Commands and arguments are otherwise identical.

The initial CMake configuration restores prebuilt dependencies from KiCad's
public CI cache. If vcpkg builds every dependency instead of restoring most of
them, check access to GitLab and run `update`.

On a Windows ARM64 guest (Apple Silicon hosts), the compiler runs natively on
ARM64, so the CI cache, which was built on x64, almost never matches: vcpkg
builds about 150 packages from source and the first `configure` takes several
hours. Later configurations reuse the local vcpkg cache in the VM.

## Commands

| Command | Effect |
|---|---|
| `up` | create, start, and provision the VM |
| `init [ref]` | clone KiCad and prepare vcpkg |
| `configure [Debug\|Release]` | recreate the CMake configuration |
| `build [Debug\|Release]` | build KiCad |
| `test [Debug\|Release]` | install test dependencies and run CTest |
| `run [Debug\|Release]` | start the locally built KiCad in the VM |
| `update` | fast-forward KiCad and align vcpkg with CI |
| `status` | show versions and Git status |
| `clean [Debug\|Release]` | invoke the CMake `clean` target |
| `shell` | open a PowerShell session in Windows |
| `reload`, `halt`, `suspend` | manage VM state |
| `destroy` | destroy the VM and **everything under `C:\dev`** |

## Working on the source

The source tree is located at `C:\dev\kicad`. Two convenient approaches are:

1. open Visual Studio in the VM and load `C:\dev\kicad` as a folder;
2. use VS Code Remote SSH from the host, as described below.

Shared folders are deliberately disabled. Building a project of this size over
SMB, 9p, or a similar mount is slow and can introduce path-length or
case-sensitivity issues.

### Edit from macOS with VS Code

After the VM is running, install the **Remote - SSH** extension in VS Code on
the Mac and create a dedicated SSH key and configuration file:

```bash
./bin/kicad-vm ssh-config
```

This command installs the key for the Vagrant Windows account and adds the
`kicad-win-dev` host to `~/.ssh/config`. It also writes a copy of the settings
to `.vagrant/kicad-win-dev-ssh-config`. The VM's SSH port is forwarded only to
`127.0.0.1:2222`; it is not exposed on the local network.

In VS Code, run **Remote-SSH: Connect to Host**, select `kicad-win-dev`, then
open `C:\dev\kicad`.
Edits made in this window modify files directly on the Windows VM. Build from
the Mac as usual:

```bash
./bin/kicad-vm build Debug
```

Before running `destroy`, push your commits to a remote or copy your changes out
of the VM. Destroying the VM removes all local source and build artifacts.

## Configuration

The `Vagrantfile` reads these environment variables:

| Variable | Default | Description |
|---|---:|---|
| `KICAD_VM_BOX` | `gusztavvargadr/windows-11` | Windows box compatible with the selected provider |
| `KICAD_VM_CPUS` | `8` | virtual CPU count |
| `KICAD_VM_MEMORY` | `16384` | RAM in MiB |
| `KICAD_VM_GUI` | `true` | set to `false` for a headless VM |
| `VAGRANT_DEFAULT_PROVIDER` | automatic | `virtualbox`, `libvirt`, `hyperv`, `vmware_desktop`, or `parallels` |

Example for a smaller macOS/Linux host:

```bash
export KICAD_VM_CPUS=6
export KICAD_VM_MEMORY=12288
export VAGRANT_DEFAULT_PROVIDER=virtualbox
./bin/kicad-vm up
```

PowerShell equivalent:

```powershell
$env:KICAD_VM_CPUS = '6'
$env:KICAD_VM_MEMORY = '12288'
$env:VAGRANT_DEFAULT_PROVIDER = 'hyperv'
.\bin\kicad-vm.ps1 up
```

## Troubleshooting

### Visual Studio was just installed

If `init` cannot find the C++ toolchain, restart Windows and reprovision:

```bash
./bin/kicad-vm reload
vagrant provision
```

### The VM stops responding after the host slept

If the host goes to sleep, VirtualBox pauses the VM (`HostSuspend`) and, on
macOS, may not resume it on wake: SSH and WinRM commands then time out and
`vagrant status` reports `paused`. `VBoxManage controlvm <vm> resume` is
refused with "VM is paused due to host power management"; save the state and
start the VM again instead. Processes running in Windows, such as an ongoing
build, survive this:

```bash
VBoxManage controlvm "$(cat .vagrant/machines/default/virtualbox/id)" savestate
vagrant up --no-provision
```

The first `configure` (which builds every vcpkg dependency) and a full build
take several hours. Keep the host on AC power with the lid open, and prevent
sleep for the duration of the command. On macOS:

```bash
caffeinate -is ./bin/kicad-vm configure Debug
caffeinate -is ./bin/kicad-vm build Debug
```

### CMake fails after an update

Realign the source, vcpkg revision, and presets:

```bash
./bin/kicad-vm update
./bin/kicad-vm configure Debug
```

`update` refuses to overwrite local changes and only performs a fast-forward.

### The disk is nearly full

Use `clean` for one configuration. To reclaim all space, save your work, run
`destroy`, and recreate the VM.

### Inspect the environment

```bash
./bin/kicad-vm status
vagrant status
```

## Limitations

- This project prepares a **development and build** environment. It does not
  create KiCad's officially signed installer.
- The `master` branch changes continuously. On each `init` or `update`, the
  script reads the vcpkg commit declared by `kicad-win-builder` to stay aligned
  with CI.
- A public Windows box remains a third-party artifact. For enterprise use,
  publish a reviewed internal box and select it through `KICAD_VM_BOX`.
- HashiCorp has announced the HCP Vagrant registry shutdown at the end of 2026.
  `KICAD_VM_BOX` makes it possible to move the base box to an internal or
  replacement registry.

## Official references

- [Building KiCad with Visual Studio](https://dev-docs.kicad.org/en/build/windows-msvc/)
- [KiCad build prerequisites](https://dev-docs.kicad.org/en/build/getting-started/)
- [KiCad source repository](https://gitlab.com/kicad/code/kicad)
- [KiCad Windows packaging tooling](https://gitlab.com/kicad/packaging/kicad-win-builder)
- [Vagrant provider documentation](https://developer.hashicorp.com/vagrant/docs/providers)
