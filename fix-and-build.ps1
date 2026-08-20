$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Get-Location }

Write-Host "[*] Creating missing directories..." -ForegroundColor Cyan
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
    $p = Join-Path $Root $d
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

Write-Host "[*] Generating Windows Application Manifest (app.manifest)..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $Root "src/Sevelr/app.manifest") -Value @'
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
      <!-- Windows 10 and Windows 11 -->
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
'@

Write-Host "[*] Generating Templates..." -ForegroundColor Cyan
$templates = @("strict", "balanced", "development", "research", "private", "webapp", "temporary", "custom")
foreach ($t in $templates) {
    $tPath = Join-Path $Root "templates/$t.json"
    Set-Content -Path $tPath -Value @"
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
    "clearOnExit": $(if ($t -eq "temporary") { "true" } else { "false" })
  },
  "security": {
    "mode": "$(if ($t -eq "balanced" -or $t -eq "development") { "balanced" } else { "strict" })",
    "failClosed": true,
    "tamperDetection": true,
    "integrityVerification": true,
    "requireSignedPolicy": false,
    "preventDevTools": true,
    "preventExtensionsModification": true
  }
}
"@
}

Write-Host "[*] Generating Documentation..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $Root "README.md") -Value @'
# Sevelr

Universal Windows Application Isolation & Policy Enforcement Platform.

## Quickstart

```powershell
# 1. Create an isolated environment
sevelr create dev-session --template strict

# 2. Verify security enforcement state
sevelr doctor dev-session

# 3. Launch isolated application
sevelr launch dev-session
'@
Set-Content -Path (Join-Path $Root "docs/architecture.md") -Value "# Sevelr ArchitecturenDefense-in-depth isolation across Network, Process, Filesystem, and Browser policies." Set-Content -Path (Join-Path $Root "docs/security-model.md") -Value "# Sevelr Security ModelnDetailed description of Windows Firewall, NTFS ACLs, EFS encryption, and Job Object isolation."
Set-Content -Path (Join-Path $Root "docs/threat-model.md") -Value "# Sevelr Threat Model`nAnalysis of application escape vectors, DNS leakage, and tamper prevention."
Write-Host "[*] Generating scripts..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $Root "scripts/build.ps1") -Value @'
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
dotnet build src/Sevelr/Sevelr.csproj -c Release
'@
Set-Content -Path (Join-Path $Root "scripts/package.ps1") -Value @'
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
Write-Host "[*] Publishing self-contained single-file win-x64 binary..." -ForegroundColor Cyan
$PublishDir = Join-Path $Root "dist"
if (Test-Path $PublishDir) { Remove-Item -Recurse -Force $PublishDir }
dotnet publish src/Sevelr/Sevelr.csproj -c Release
-r win-x64 --self-contained true
-p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
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
Compress-Archive -Path "$PublishDir*" -DestinationPath $ZipPath
Write-Host "`n[✓] Archive created successfully at: $ZipPath" -ForegroundColor Green
'@
Write-Host "[*] Building and packaging self-contained binary..." -ForegroundColor Cyan
& "$Root/scripts/package.ps1"