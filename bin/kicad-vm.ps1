[CmdletBinding(PositionalBinding = $true)]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',

    [Parameter(Position = 1)]
    [string]$Argument
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    @'
Usage: .\bin\kicad-vm.ps1 <command> [configuration|ref]

Commands:
  up                         Create and provision the VM
  init [ref]                 Clone KiCad and initialize vcpkg (ref: master)
  configure [Debug|Release]  Configure CMake
  build [Debug|Release]      Build KiCad
  test [Debug|Release]       Run the tests
  run [Debug|Release]        Start KiCad in the VM
  clean [Debug|Release]      Clean build artifacts through CMake
  update                     Update KiCad and vcpkg (fast-forward only)
  status                     Show environment status
  shell                      Open PowerShell in the VM
  reload | halt | suspend    Manage the VM
  destroy                    Destroy the VM and all of C:\dev
'@ | Write-Host
}

function Invoke-Vagrant([string[]]$Arguments) {
    & vagrant @Arguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

switch ($Command) {
    { $_ -in @('up', 'reload', 'halt', 'suspend', 'destroy') } {
        Invoke-Vagrant @($Command)
        exit 0
    }
    'shell' {
        Invoke-Vagrant @('powershell')
        exit 0
    }
    'init' {
        $ref = if ($Argument) { $Argument } else { 'master' }
        if ($ref -notmatch '^[A-Za-z0-9._/-]+$') {
            throw "Invalid KiCad ref: $ref"
        }
        $guestCommand = "& 'C:\dev\tools\kicad.ps1' -Action bootstrap -Ref '$ref'"
    }
    { $_ -in @('configure', 'build', 'test', 'run', 'clean') } {
        $configuration = if ($Argument) { $Argument } else { 'Debug' }
        if ($configuration -notin @('Debug', 'Release')) {
            throw 'Expected configuration: Debug or Release'
        }
        $guestCommand = "& 'C:\dev\tools\kicad.ps1' -Action '$Command' -Configuration '$configuration'"
    }
    { $_ -in @('update', 'status') } {
        $guestCommand = "& 'C:\dev\tools\kicad.ps1' -Action '$Command'"
    }
    { $_ -in @('help', '-h', '--help') } {
        Show-Usage
        exit 0
    }
    default {
        Show-Usage
        throw "Unknown command: $Command"
    }
}

Invoke-Vagrant @('winrm', '--shell', 'powershell', '--command', $guestCommand)
