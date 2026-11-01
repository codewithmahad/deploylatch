$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceFile = Join-Path $repoRoot 'demo-app/src/main/java/dev/deploylatch/demo/DemoServer.java'
$buildDirectory = Join-Path $repoRoot 'demo-app/build'
$classesDirectory = Join-Path $buildDirectory 'classes'
$distDirectory = Join-Path $repoRoot 'demo-app/dist'

$javacCommand = (Get-Command 'javac.exe' -ErrorAction Stop).Source
$jdkBin = Split-Path -Parent $javacCommand
$javacExe = Join-Path $jdkBin 'javac.exe'
$jarExe = Join-Path $jdkBin 'jar.exe'

if (-not (Test-Path $jarExe)) {
    # Some Windows Java installations expose javac through a separate PATH directory.
    $javaSettings = (& cmd.exe /d /c 'java -XshowSettings:properties -version 2>&1' | Out-String)
    $javaHomeMatch = [regex]::Match($javaSettings, '(?m)^\s*java\.home\s*=\s*(.+)$')
    if (-not $javaHomeMatch.Success) {
        throw 'Could not locate the JDK tools. Check your Java installation.'
    }

    $jdkBin = Join-Path $javaHomeMatch.Groups[1].Value.Trim() 'bin'
    $javacExe = Join-Path $jdkBin 'javac.exe'
    $jarExe = Join-Path $jdkBin 'jar.exe'
}

if (-not (Test-Path $javacExe) -or -not (Test-Path $jarExe)) {
    throw "JDK tools not found in $jdkBin"
}

New-Item -ItemType Directory -Force $classesDirectory, $distDirectory | Out-Null
& $javacExe -d $classesDirectory $sourceFile
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed.' }

$releases = @(
    @{ Version = 'v1'; Healthy = 'true' },
    @{ Version = 'v2'; Healthy = 'true' },
    @{ Version = 'v3'; Healthy = 'false' }
)

foreach ($release in $releases) {
    $resourceDirectory = Join-Path $buildDirectory ('resources-' + $release.Version)
    New-Item -ItemType Directory -Force $resourceDirectory | Out-Null

    $resourceFile = Join-Path $resourceDirectory 'release.properties'
    $contents = @("version=$($release.Version)", "healthy=$($release.Healthy)", "") -join [Environment]::NewLine
    [System.IO.File]::WriteAllText($resourceFile, $contents, (New-Object System.Text.UTF8Encoding($false)))

    $outputFile = Join-Path $distDirectory ('demo-app-' + $release.Version + '.jar')
    & $jarExe --create --file $outputFile --main-class dev.deploylatch.demo.DemoServer -C $classesDirectory . -C $resourceDirectory release.properties
    if ($LASTEXITCODE -ne 0) { throw "Failed to package $($release.Version)." }
    Write-Host "Built $outputFile"
}
