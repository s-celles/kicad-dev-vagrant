# frozen_string_literal: true

require "etc"
require "rbconfig"

host_cpu = RbConfig::CONFIG.fetch("host_cpu", "unknown")
default_box = "gusztavvargadr/windows-11"

# Host RAM in MiB, or nil when it cannot be determined.
def host_memory_mib
  case RbConfig::CONFIG.fetch("host_os", "")
  when /darwin/
    Integer(`sysctl -n hw.memsize`.strip) / 1024 / 1024
  when /linux/
    File.read("/proc/meminfo")[/^MemTotal:\s+(\d+)/, 1].to_i / 1024
  when /mswin|mingw|cygwin/
    Integer(`powershell -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory"`.strip) / 1024 / 1024
  end
rescue StandardError
  nil
end

# Leave enough RAM and CPU to the host: at most 16 GiB and 8 vCPUs, and at
# most 5/8 of the host RAM and all but two host CPUs.
host_memory = host_memory_mib
default_memory = if host_memory
  [[host_memory * 5 / 8 / 1024 * 1024, 4096].max, 16_384].min
else
  16_384
end
default_cpus = [[Etc.nprocessors - 2, 2].max, 8].min

Vagrant.configure("2") do |config|
  config.vm.box = ENV.fetch("KICAD_VM_BOX", default_box)
  config.vm.hostname = "kicad-win-dev"
  config.vm.communicator = "winrm"
  config.vm.boot_timeout = 1_200
  config.winrm.timeout = 1_200
  # The first configure builds every vcpkg dependency; WinRM's default 2-hour
  # limit is too short for that and for a full KiCad build.
  config.winrm.execution_time_limit = "PT24H"
  config.vm.synced_folder ".", "C:/vagrant", disabled: true
  config.vm.network "forwarded_port",
    guest: 22,
    host: 2222,
    host_ip: "127.0.0.1",
    id: "ssh"

  cpus = ENV.fetch("KICAD_VM_CPUS", default_cpus.to_s).to_i
  memory = ENV.fetch("KICAD_VM_MEMORY", default_memory.to_s).to_i
  gui = ENV.fetch("KICAD_VM_GUI", "true") != "false"

  config.vm.provider "virtualbox" do |provider|
    provider.cpus = cpus
    provider.memory = memory
    provider.gui = gui
    provider.name = "kicad-win-dev-#{host_cpu}"
  end

  config.vm.provider "vmware_desktop" do |provider|
    provider.vmx["numvcpus"] = cpus.to_s
    provider.vmx["memsize"] = memory.to_s
    provider.gui = gui
  end

  config.vm.provider "parallels" do |provider|
    provider.cpus = cpus
    provider.memory = memory
  end

  config.vm.provider "libvirt" do |provider|
    provider.cpus = cpus
    provider.memory = memory
  end

  config.vm.provider "hyperv" do |provider|
    provider.cpus = cpus
    provider.memory = memory
    provider.vmname = "kicad-win-dev-#{host_cpu}"
  end

  config.vm.provision "shell",
    path: "scripts/provision.ps1",
    privileged: true,
    reboot: false

  config.vm.provision "file",
    source: "scripts/kicad.ps1",
    destination: "C:/Windows/Temp/kicad.ps1"

  config.vm.provision "shell",
    inline: <<-POWERSHELL
      $ErrorActionPreference = 'Stop'
      New-Item -ItemType Directory -Force -Path C:/dev/tools | Out-Null
      Copy-Item -Force C:/Windows/Temp/kicad.ps1 C:/dev/tools/kicad.ps1
    POWERSHELL
end
