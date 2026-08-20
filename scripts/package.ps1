$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host "[*] Publishing self-contained single-file win-x64 binary..." -ForegroundColor Cyan

$PublishDir = Join-Path $Root "dist"
if (Test-Path $PublishDir) { Remove-Item -Recurse -Force $PublishDir }

dotnet publish src/Sevelr/Sevelr.csproj `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o (Join-Path $PublishDir "bin")

if ($LASTEXITCODE -ne 0) {
    Write-Error "dotnet publish failed with exit code $LASTEXITCODE"
}

Copy-Item -Recurse templates (Join-Path $PublishDir "templates")
Copy-Item -Recurse docs (Join-Path $PublishDir "docs")
Copy-Item -Recurse scripts (Join-Path $PublishDir "scripts")
Copy-Item README.md $PublishDir

$ZipPath = Join-Path $Root "sevelr-v2.0.0-win-x64.zip"
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }

Compress-Archive -Path "$PublishDir\*" -DestinationPath $ZipPath
Write-Host "[✓] Archive created successfully at: $ZipPath" -ForegroundColor Green
