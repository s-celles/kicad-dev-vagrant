[CmdletBinding()]
param(
    [ValidateSet('bootstrap', 'configure', 'build', 'test', 'run', 'status', 'update', 'clean')]
    [string]$Action = 'status',

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',

    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$Ref = 'master'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$DevRoot = 'C:\dev'
$SourceRoot = Join-Path $DevRoot 'kicad'
$VcpkgRoot = Join-Path $DevRoot 'vcpkg'
$BuilderRoot = Join-Path $DevRoot 'kicad-win-builder'
$BinaryFeed = 'default;nuget,https://gitlab.com/api/v4/projects/27426693/packages/nuget/index.json,read'

function Assert-LastExitCode([string]$Description) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Description (exit code $LASTEXITCODE)."
    }
}

function Enable-DeveloperShell {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw 'Visual Studio was not found. Run `vagrant provision`.'
    }

    $vsPath = & $vswhere `
        -latest `
        -products '*' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if ([string]::IsNullOrWhiteSpace($vsPath)) {
        throw 'The Visual Studio x64 C++ toolchain was not found. Run `vagrant provision`.'
    }

    $module = Join-Path $vsPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
    Import-Module $module
    $hostArchitecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    Enter-VsDevShell `
        -VsInstallPath $vsPath `
        -SkipAutomaticLocation `
        -DevCmdArguments "-arch=x64 -host_arch=$hostArchitecture"

    $env:VCPKG_ROOT = $VcpkgRoot
    $env:VCPKG_BINARY_SOURCES = $BinaryFeed
    $env:GIT_REDIRECT_STDERR = '2>&1'
    $env:Path = "C:\Program Files\Git\cmd;$env:Path"
}

function Assert-SourceTree {
    if (-not (Test-Path (Join-Path $SourceRoot 'CMakeLists.txt'))) {
        throw 'The KiCad source tree is missing. Run the `init` command from the host.'
    }
}

function Get-PresetNames {
    if ($Configuration -eq 'Release') {
        return @('msvc-win64-release', 'win64-release')
    }
    return @('msvc-win64-debug', 'win64-debug')
}

function Sync-Presets {
    $samplePath = Join-Path $SourceRoot 'CMakePresets.json.sample'
    $presetPath = Join-Path $SourceRoot 'CMakePresets.json'
    if (-not (Test-Path $samplePath)) {
        throw "KiCad preset file not found: $samplePath"
    }

    $presets = Get-Content -Raw $samplePath | ConvertFrom-Json
    $msvc = $presets.configurePresets | Where-Object { $_.name -eq 'msvc' }
    if (-not $msvc) {
        throw 'The base `msvc` preset is missing from the file supplied by KiCad.'
    }

    $msvc.environment.VCPKG_ROOT = $VcpkgRoot.Replace('\', '/')
    $msvc.environment | Add-Member `
        -NotePropertyName VCPKG_BINARY_SOURCES `
        -NotePropertyValue $BinaryFeed `
        -Force
    $msvc.cacheVariables | Add-Member `
        -NotePropertyName VCPKG_OVERLAY_TRIPLETS `
        -NotePropertyValue '${sourceDir}/tools/custom_vcpkg_triplets' `
        -Force

    $testBase = $presets.testPresets | Where-Object { $_.name -eq 'test-base' }
    if ($testBase) {
        $testBase | Add-Member -NotePropertyName hidden -NotePropertyValue $true -Force
    }

    $json = $presets | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText(
        $presetPath,
        $json,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Sync-Vcpkg {
    if (-not (Test-Path (Join-Path $BuilderRoot '.git'))) {
        git clone --depth 1 https://gitlab.com/kicad/packaging/kicad-win-builder.git $BuilderRoot
        Assert-LastExitCode 'Could not clone kicad-win-builder'
    }
    else {
        git -C $BuilderRoot pull --ff-only
        Assert-LastExitCode 'Could not update kicad-win-builder'
    }

    $builderScript = Get-Content -Raw (Join-Path $BuilderRoot 'build.ps1')
    $match = [regex]::Match($builderScript, '\$vcpkgCommit\s*=\s*"([0-9a-f]{40})"')
    if (-not $match.Success) {
        throw 'Could not read the vcpkg revision expected by KiCad CI.'
    }
    $vcpkgCommit = $match.Groups[1].Value

    if (-not (Test-Path (Join-Path $VcpkgRoot '.git'))) {
        git clone https://github.com/microsoft/vcpkg.git $VcpkgRoot
        Assert-LastExitCode 'Could not clone vcpkg'
    }

    git -C $VcpkgRoot fetch origin $vcpkgCommit --depth 1
    Assert-LastExitCode 'Could not fetch the required vcpkg revision'
    git -C $VcpkgRoot checkout --detach $vcpkgCommit
    Assert-LastExitCode 'Could not check out the required vcpkg revision'

    & (Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat') -disableMetrics
    Assert-LastExitCode 'vcpkg bootstrap failed'
}

function Initialize-Environment {
    New-Item -ItemType Directory -Force -Path $DevRoot | Out-Null
    if (-not (Test-Path (Join-Path $SourceRoot '.git'))) {
        git clone --branch $Ref --single-branch https://gitlab.com/kicad/code/kicad.git $SourceRoot
        Assert-LastExitCode 'Could not clone KiCad'
    }
    else {
        $currentRef = git -C $SourceRoot branch --show-current
        Write-Host "The source tree already exists (branch: $currentRef); no local files were changed."
    }

    Sync-Vcpkg
    Sync-Presets
    Write-Host ''
    Write-Host 'KiCad environment initialized.' -ForegroundColor Green
    Write-Host 'Next step: run the `configure Debug` command from the host.'
}

function Configure-KiCad {
    Assert-SourceTree
    Sync-Presets
    $configurePreset, $null = Get-PresetNames
    Push-Location $SourceRoot
    try {
        cmake --preset $configurePreset --fresh
        Assert-LastExitCode 'CMake configuration failed'
    }
    finally {
        Pop-Location
    }
}

function Build-KiCad {
    Assert-SourceTree
    $null, $buildPreset = Get-PresetNames
    $jobs = if ($env:KICAD_BUILD_JOBS) {
        [int]$env:KICAD_BUILD_JOBS
    } else {
        [Math]::Max(1, [Environment]::ProcessorCount - 1)
    }
    Push-Location $SourceRoot
    try {
        cmake --build --preset $buildPreset --parallel $jobs
        Assert-LastExitCode 'Build failed'
    }
    finally {
        Pop-Location
    }
}

function Test-KiCad {
    Assert-SourceTree
    $null, $testPreset = Get-PresetNames
    Push-Location $SourceRoot
    try {
        cmake --build --preset $testPreset --target qa_python_deps
        Assert-LastExitCode 'Could not install the Python test dependencies'
        ctest --preset $testPreset --output-on-failure
        Assert-LastExitCode 'Tests failed'
    }
    finally {
        Pop-Location
    }
}

function Start-KiCad {
    Assert-SourceTree
    $configurePreset, $null = Get-PresetNames
    $buildRoot = Join-Path $SourceRoot "build\$configurePreset"
    $executable = Join-Path $buildRoot 'kicad\kicad.exe'
    if (-not (Test-Path $executable)) {
        throw "Executable not found: $executable. Build KiCad first."
    }

    $vcpkgBin = if ($Configuration -eq 'Debug') {
        Join-Path $buildRoot 'vcpkg_installed\x64-windows\debug\bin'
    } else {
        Join-Path $buildRoot 'vcpkg_installed\x64-windows\bin'
    }
    $env:KICAD_RUN_FROM_BUILD_DIR = '1'
    $env:Path = @(
        $vcpkgBin,
        (Join-Path $buildRoot 'common'),
        (Join-Path $buildRoot 'api'),
        (Join-Path $buildRoot 'common\gal'),
        $env:Path
    ) -join ';'
    Start-Process -FilePath $executable -WorkingDirectory (Split-Path $executable)
    Write-Host "KiCad started from $buildRoot"
}

function Show-Status {
    Write-Host "Windows: $([Environment]::OSVersion.VersionString) / $env:PROCESSOR_ARCHITECTURE"
    Write-Host "Source:  $SourceRoot"
    if (Test-Path (Join-Path $SourceRoot '.git')) {
        git -C $SourceRoot status --short --branch
        git -C $SourceRoot describe --tags --always --dirty
    } else {
        Write-Host 'KiCad:   not initialized'
    }
    if (Test-Path (Join-Path $VcpkgRoot '.git')) {
        $vcpkgRevision = git -C $VcpkgRoot rev-parse --short HEAD
        Write-Host "vcpkg:  $vcpkgRevision"
    } else {
        Write-Host 'vcpkg:  not initialized'
    }
}

function Update-Environment {
    Assert-SourceTree
    git -C $SourceRoot pull --ff-only
    Assert-LastExitCode 'Could not update KiCad (check for local changes)'
    Sync-Vcpkg
    Sync-Presets
}

function Clean-Build {
    Assert-SourceTree
    $null, $buildPreset = Get-PresetNames
    Push-Location $SourceRoot
    try {
        cmake --build --preset $buildPreset --target clean
        Assert-LastExitCode 'Clean target failed'
    }
    finally {
        Pop-Location
    }
}

Enable-DeveloperShell

switch ($Action) {
    'bootstrap' { Initialize-Environment }
    'configure' { Configure-KiCad }
    'build' { Build-KiCad }
    'test' { Test-KiCad }
    'run' { Start-KiCad }
    'status' { Show-Status }
    'update' { Update-Environment }
    'clean' { Clean-Build }
}
