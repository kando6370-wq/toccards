param(
    [Parameter(Mandatory = $true)]
    [string]$OnnxRuntimeSource,
    [Parameter(Mandatory = $true)]
    [string]$AndroidSdk,
    [Parameter(Mandatory = $true)]
    [string]$AndroidNdk,
    [string]$BuildDirectory,
    [string]$PythonExecutable = "python"
)

$ErrorActionPreference = "Stop"
$expectedVersion = "1.23.0"
$toolDirectory = $PSScriptRoot
$flutterDirectory = (Resolve-Path (Join-Path $toolDirectory "..\..")).Path
$sourceDirectory = (Resolve-Path $OnnxRuntimeSource).Path
$sdkDirectory = (Resolve-Path $AndroidSdk).Path
$ndkDirectory = (Resolve-Path $AndroidNdk).Path

if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path $sourceDirectory "build\android-minimal-aar"
}

$actualVersion = (Get-Content (Join-Path $sourceDirectory "VERSION_NUMBER") -Raw).Trim()
if ($actualVersion -ne $expectedVersion) {
    throw "Expected ONNX Runtime $expectedVersion, found $actualVersion."
}

$builder = Join-Path $sourceDirectory "tools\ci_build\github\android\build_aar_package.py"
$settings = Join-Path $toolDirectory "minimal_aar_build_settings.json"
$operators = Join-Path $toolDirectory "required_operators_and_types.config"

& $PythonExecutable $builder `
    --android_sdk_path $sdkDirectory `
    --android_ndk_path $ndkDirectory `
    --build_dir $BuildDirectory `
    --include_ops_by_config $operators `
    --config MinSizeRel `
    $settings
if ($LASTEXITCODE -ne 0) {
    throw "ONNX Runtime AAR build failed with exit code $LASTEXITCODE."
}

$artifacts = @(Get-ChildItem (Join-Path $BuildDirectory "aar_out\MinSizeRel") -Filter "*.aar" -File -Recurse)
if ($artifacts.Count -ne 1) {
    throw "Expected one AAR artifact, found $($artifacts.Count)."
}

$destinationDirectory = Join-Path $flutterDirectory "android\app\libs"
New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
$destination = Join-Path $destinationDirectory "onnxruntime-minimal-$expectedVersion.aar"
Copy-Item $artifacts[0].FullName $destination -Force
Write-Output $destination
