$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = (Get-Location).Path }

Write-Host "[1/5] Ensuring directory structure exists..." -ForegroundColor Cyan
$dirs = @(
    "src/Sevelr/Core",
    "src/Sevelr/Configuration/Models",
    "src/Sevelr/Policies",
    "src/Sevelr/Applications",
    "src/Sevelr/Browser",
    "src/Sevelr/Network",
    "src/Sevelr/DNS",
    "src/Sevelr/Filesystem",
    "src/Sevelr/Process",
    "src/Sevelr/Security",
    "src/Sevelr/Extensions",
    "src/Sevelr/Logging",
    "src/Sevelr/Runtime",
    "src/Sevelr/Projects",
    "src/Sevelr/Diagnostics",
    "src/Sevelr/Commands",
    "templates",
    "docs",
    "scripts"
)
foreach ($d in $dirs) {
    $targetDir = Join-Path $Root $d
    if (-not (Test-Path $targetDir)) { [System.IO.Directory]::CreateDirectory($targetDir) | Out-Null }
}

Write-Host "[2/5] Writing src/Sevelr/app.manifest..." -ForegroundColor Cyan
$manifestXml = @"
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="2.0.0.0" name="Sevelr.Platform"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="asInvoker" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" />
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
      <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
    </windowsSettings>
  </application>
</assembly>
"@
[System.IO.File]::WriteAllText((Join-Path $Root "src/Sevelr/app.manifest"), $manifestXml)

Write-Host "[3/5] Writing documentation and templates..." -ForegroundColor Cyan
[System.IO.File]::WriteAllText((Join-Path $Root "README.md"), "# Sevelr`n`nUniversal Windows Application Isolation & Policy Enforcement Platform.`n")
[System.IO.File]::WriteAllText((Join-Path $Root "docs/architecture.md"), "# Sevelr Architecture`n`nModular architecture with defense-in-depth isolation.`n")
[System.IO.File]::WriteAllText((Join-Path $Root "docs/security-model.md"), "# Sevelr Security Model`n`nMulti-layer defense: OS Firewall, NTFS ACLs, EFS encryption, Job Objects.`n")
[System.IO.File]::WriteAllText((Join-Path $Root "docs/threat-model.md"), "# Sevelr Threat Model`n`nThreat vector mitigations and fail-closed security properties.`n")

$templates = @("strict", "balanced", "development", "research", "private", "webapp", "temporary", "custom")
foreach ($t in $templates) {
    $clearOnExit = if ($t -eq "temporary") { "true" } else { "false" }
    $secMode = if ($t -eq "balanced" -or $t -eq "development") { "balanced" } else { "strict" }
    $tplJson = @"
{
  "schemaVersion": 2,
  "project": {
    "id": "$t-environment",
    "displayName": "$t Profile",
    "description": "Auto-generated $t isolation profile.",
    "template": "$t"
  },
  "application": {
    "provider": "brave",
    "executable": null,
    "arguments": [],
    "initialUrl": "about:blank"
  },
  "network": {
    "mode": "allowlist",
    "allowedDomains": [],
    "deniedDomains": [],
    "allowedIps": [],
    "allowedCidrs": [],
    "allowedPorts": [443],
    "allowHttp": false,
    "allowHttps": true,
    "allowWebSocket": false,
    "allowQuic": false,
    "allowIpv6": true,
    "allowLocalhost": false,
    "allowPrivateNetworks": false
  },
  "dns": {
    "mode": "policy",
    "allowDirectIp": false,
    "allowDoh": false,
    "allowDot": false
  },
  "filesystem": {
    "encrypted": true,
    "downloads": "isolated",
    "temporaryFiles": "isolated",
    "allowSharedDirectories": false
  },
  "process": {
    "monitor": true,
    "allowChildProcesses": true,
    "allowedExecutables": [],
    "maxMemoryMb": 4096,
    "singleInstancePerProject": true
  },
  "privacy": {
    "sync": false,
    "telemetry": false,
    "passwordSaving": false,
    "autofill": false,
    "clearOnExit": $clearOnExit
  },
  "security": {
    "mode": "$secMode",
    "failClosed": true,
    "tamperDetection": true,
    "integrityVerification": true,
    "requireSignedPolicy": false,
    "preventDevTools": true,
    "preventExtensionsModification": true
  }
}
"@
    [System.IO.File]::WriteAllText((Join-Path $Root "templates/$t.json"), $tplJson)
}

Write-Host "[4/5] Publishing self-contained single-file win-x64 binary..." -ForegroundColor Cyan
$PublishDir = Join-Path $Root "dist"
if (Test-Path $PublishDir) { Remove-Item -Recurse -Force $PublishDir }

$publishArgs = @(
    "publish",
    (Join-Path $Root "src/Sevelr/Sevelr.csproj"),
    "-c", "Release",
    "-r", "win-x64",
    "--self-contained", "true",
    "-p:PublishSingleFile=true",
    "-p:IncludeNativeLibrariesForSelfExtract=true",
    "-o", (Join-Path $PublishDir "bin")
)

& dotnet @publishArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "dotnet publish failed with exit code $LASTEXITCODE"
}

Write-Host "[5/5] Creating release zip archive..." -ForegroundColor Cyan
Copy-Item -Recurse (Join-Path $Root "templates") (Join-Path $PublishDir "templates")
Copy-Item -Recurse (Join-Path $Root "docs") (Join-Path $PublishDir "docs")
Copy-Item -Recurse (Join-Path $Root "scripts") (Join-Path $PublishDir "scripts")
Copy-Item (Join-Path $Root "README.md") $PublishDir

$ZipPath = Join-Path $Root "sevelr-v2.0.0-win-x64.zip"
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }

Compress-Archive -Path "$PublishDir\*" -DestinationPath $ZipPath
Write-Host "`n========================================================" -ForegroundColor Green
Write-Host " [✓] Build and packaging complete!" -ForegroundColor Green
Write-Host " [✓] Package generated: $ZipPath" -ForegroundColor Green
Write-Host "========================================================`n" -ForegroundColor Green