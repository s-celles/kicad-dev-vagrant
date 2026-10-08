[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Find-Command([string]$Name) {
    return Get-Command $Name -ErrorAction SilentlyContinue
}

function Assert-ValidSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -FilePath $Path
    if ($signature.Status -ne 'Valid') {
        throw "Invalid Authenticode signature for $Path ($($signature.Status))."
    }
}

Write-Host 'Enabling long Windows paths...'
New-ItemProperty `
    -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
    -Name LongPathsEnabled `
    -Value 1 `
    -PropertyType DWord `
    -Force | Out-Null

if (-not (Find-Command 'git.exe')) {
    Write-Host 'Installing Git for Windows...'
    $release = Invoke-RestMethod `
        -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' `
        -Headers @{ 'User-Agent' = 'kicad-dev-vagrant' }
    $gitArchitecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { '64-bit' }
    $asset = $release.assets |
        Where-Object { $_.name -match "^Git-.*-$gitArchitecture\.exe$" } |
        Select-Object -First 1
    if (-not $asset) {
        throw "Could not find the Git for Windows $gitArchitecture installer."
    }

    $gitInstaller = Join-Path $env:TEMP $asset.name
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $gitInstaller
        Assert-ValidSignature $gitInstaller
        $process = Start-Process `
            -FilePath $gitInstaller `
            -ArgumentList '/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-' `
            -Wait `
            -PassThru
        if ($process.ExitCode -ne 0) {
            throw "Git installation failed (exit code $($process.ExitCode))."
        }
    }
    finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $gitInstaller
    }
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasCpp = $false
if (Test-Path $vswhere) {
    $installation = & $vswhere `
        -latest `
        -products '*' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    $hasCpp = -not [string]::IsNullOrWhiteSpace($installation)
}

if (-not $hasCpp) {
    Write-Host 'Installing Visual Studio 2022 Community and the C++ toolchain...'
    $vsInstaller = Join-Path $env:TEMP 'vs_community.exe'
    try {
        Invoke-WebRequest `
            -Uri 'https://aka.ms/vs/17/release/vs_community.exe' `
            -OutFile $vsInstaller
        Assert-ValidSignature $vsInstaller
        $process = Start-Process `
            -FilePath $vsInstaller `
            -ArgumentList @(
                '--wait',
                '--quiet',
                '--norestart',
                '--nocache',
                '--add',
                'Microsoft.VisualStudio.Workload.NativeDesktop',
                '--includeRecommended'
            ) `
            -Wait `
            -PassThru
        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
            throw "Visual Studio installation failed (exit code $($process.ExitCode))."
        }
    }
    finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $vsInstaller
    }
}

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$gitCmd = 'C:\Program Files\Git\cmd'
if (($machinePath -split ';') -notcontains $gitCmd) {
    [Environment]::SetEnvironmentVariable('Path', "$machinePath;$gitCmd", 'Machine')
}

 $openSshServer = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
if ($openSshServer.State -ne 'Installed') {
    Write-Host 'Installing OpenSSH Server...'
    Add-WindowsCapability -Online -Name $openSshServer.Name | Out-Null
}

# Some boxes ship a minimal sshd_config without the stock Windows block that
# reads administrators' keys from administrators_authorized_keys.
$sshdConfig = 'C:\ProgramData\ssh\sshd_config'
if (Test-Path $sshdConfig) {
    $config = Get-Content -Raw $sshdConfig
    if ($config -notmatch '(?m)^\s*Match\s+Group\s+administrators') {
        Write-Host 'Enabling SSH keys for administrators...'
        Add-Content -Path $sshdConfig -Value @(
            '',
            'Match Group administrators',
            '       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys'
        )
        Restart-Service -Name sshd -ErrorAction SilentlyContinue
    }
}

Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -Name 'OpenSSH-Server-In-TCP' `
        -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22 | Out-Null
}

New-Item -ItemType Directory -Force -Path C:\dev\tools | Out-Null

Write-Host ''
Write-Host 'Provisioning complete.' -ForegroundColor Green
Write-Host 'If Windows reports a pending restart, run: vagrant reload'
