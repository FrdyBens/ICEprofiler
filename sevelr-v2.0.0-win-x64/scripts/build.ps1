#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Building Sevelr Engine & Test Suite    " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

dotnet build Sevelr.sln -c Release
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed with exit code $LASTEXITCODE"
}

Write-Host "`n[✓] Solution built successfully." -ForegroundColor Green