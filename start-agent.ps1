# Save as start-agent.ps1
$ErrorActionPreference = "Continue"

$envFile = Join-Path $PSScriptRoot ".env"

Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
        Set-Variable -Name $matches[1].Trim() -Value $matches[2].Trim()
    }
}

$ServerUrl = "https://$SERVERURL"
$SecretKey = $SECRETKEY

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "       SEVELR REAL-TIME CLOUD AGENT ACTIVATED            " -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "[*] Host Machine       : $env:COMPUTERNAME ($env:USERNAME)" -ForegroundColor Gray
Write-Host "[*] Connected to       : $ServerUrl" -ForegroundColor Gray
Write-Host "[*] Bare Web Dashboard : $ServerUrl" -ForegroundColor Green
Write-Host "    (Press '~' or tap 3 times on the blank screen to unlock)" -ForegroundColor Yellow
Write-Host "=========================================================`n" -ForegroundColor Cyan

$ProjectsDir = "$env:LOCALAPPDATA\Sevelr\projects"
$RuntimeSessionsFile = "$env:LOCALAPPDATA\Sevelr\runtime\active_sessions.json"
$LogFile = "$env:LOCALAPPDATA\Sevelr\logs\sevelr.log"

# Locate sevelr.exe binary
$SevelrBin = "$env:LOCALAPPDATA\Programs\Sevelr\bin\sevelr.exe"
if (-not (Test-Path $SevelrBin)) {
    $cmd = Get-Command "sevelr" -ErrorAction SilentlyContinue
    if ($cmd) { $SevelrBin = $cmd.Source }
}

$actionResults = @{}

while ($true) {
    try {
        # 1. Collect all local project configurations
        $localProjects = @{}
        if (Test-Path $ProjectsDir) {
            $folders = Get-ChildItem -Directory $ProjectsDir
            foreach ($f in $folders) {
                $cfgPath = Join-Path $f.FullName "config\project.json"
                if (Test-Path $cfgPath) {
                    try {
                        $rawJson = Get-Content $cfgPath -Raw | ConvertFrom-Json
                        $localProjects[$f.Name] = $rawJson
                    } catch { }
                }
            }
        }

        # 2. Check live process runtime status
        $runtimeStatus = @{}
        if (Test-Path $RuntimeSessionsFile) {
            try {
                $sessions = Get-Content $RuntimeSessionsFile -Raw | ConvertFrom-Json
                foreach ($s in $sessions) {
                    $pidNum = $s.ProcessId
                    $proc = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
                    if ($proc) {
                        $runtimeStatus[$s.ProjectId] = @{
                            status = "running"
                            pid = $pidNum
                            startedAt = $s.StartedAt
                        }
                    }
                }
            } catch { }
        }

        foreach ($pName in $localProjects.Keys) {
            if (-not $runtimeStatus.ContainsKey($pName)) {
                $runtimeStatus[$pName] = @{ status = "stopped" }
            }
        }

        # 3. Read latest logs
        $recentLogs = @()
        if (Test-Path $LogFile) {
            try {
                $recentLogs = Get-Content $LogFile -Tail 25
            } catch { }
        }

        # 4. Construct payload and ping
        $payload = @{
            agent_info = @{
                hostname = $env:COMPUTERNAME
                user = $env:USERNAME
                platform = "Windows x64"
            }
            projects = $localProjects
            runtime = $runtimeStatus
            logs = $recentLogs
            action_results = $actionResults
        }

        $bodyJson = $payload | ConvertTo-Json -Depth 10
        $headers = @{ "X-Sevelr-Secret" = $SecretKey }

        $response = Invoke-RestMethod -Uri "$ServerUrl/api/agent/sync" `
            -Method POST `
            -Headers $headers `
            -Body $bodyJson `
            -ContentType "application/json" `
            -TimeoutSec 5

        $actionResults = @{}

        # 5. Process Actions from Cloud
        if ($response -and $response.actions) {
            foreach ($act in $response.actions) {
                $actionId = $act.action_id
                $type = $act.type
                $data = $act.payload

                Write-Host "[*] Cloud Action: $type ($actionId)" -ForegroundColor Yellow

                try {
                    if ($type -eq "create_project" -or $type -eq "save_config") {
                        $p = $data.project
                        $projId = $p.project.id
                        $tmpl = if ($p.security.mode) { $p.security.mode } else { "balanced" }
                        $targetDir = Join-Path $ProjectsDir $projId

                        # Initialize via Sevelr CLI first if it doesn't exist
                        if (-not (Test-Path (Join-Path $targetDir "config"))) {
                            Write-Host "[+] Creating local structure via Sevelr CLI: $projId..." -ForegroundColor Cyan
                            & $SevelrBin create $projId --template $tmpl
                        }

                        # Save updated project configuration
                        $cfgFile = Join-Path $targetDir "config\project.json"
                        $pJson = $p | ConvertTo-Json -Depth 10
                        [System.IO.File]::WriteAllText($cfgFile, $pJson)

                        # Re-generate manifest integrity manifest so tamper detection passes
                        $manifestPath = Join-Path $targetDir "config\manifest.json"
                        $hashes = @{}
                        $configFiles = Get-ChildItem -Path (Join-Path $targetDir "config") -File
                        foreach ($cf in $configFiles) {
                            if ($cf.Name -ne "manifest.json") {
                                $hash = (Get-FileHash $cf.FullName -Algorithm SHA256).Hash
                                $rel = "config\" + $cf.Name
                                $hashes[$rel] = $hash
                            }
                        }
                        $manObj = @{ FileHashes = $hashes; GeneratedAt = (Get-Date).ToUniversalTime().ToString("o") }
                        [System.IO.File]::WriteAllText($manifestPath, ($manObj | ConvertTo-Json -Depth 5))

                        Write-Host "[✓] Project '$projId' configuration & integrity manifest synced." -ForegroundColor Green
                        $actionResults[$actionId] = @{ status = "success"; output = "Config updated" }
                    }
                    elseif ($type -eq "launch") {
                        $projId = $data.id
                        Write-Host "[▶] Launching Browser for '$projId'..." -ForegroundColor Green

                        # Direct execution of Sevelr launcher
                        Start-Process -FilePath $SevelrBin -ArgumentList "launch $projId" -WindowStyle Normal

                        $actionResults[$actionId] = @{ status = "success"; output = "Launched" }
                    }
                    elseif ($type -eq "stop") {
                        $projId = $data.id
                        Write-Host "[⏹] Terminating '$projId'..." -ForegroundColor Red
                        
                        if (Test-Path $RuntimeSessionsFile) {
                            $sessions = Get-Content $RuntimeSessionsFile -Raw | ConvertFrom-Json
                            foreach ($s in $sessions) {
                                if ($s.ProjectId -eq $projId) {
                                    Stop-Process -Id $s.ProcessId -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }
                        $actionResults[$actionId] = @{ status = "success"; output = "Stopped" }
                    }
                    elseif ($type -eq "delete_project") {
                        $projId = $data.id
                        $targetDir = Join-Path $ProjectsDir $projId
                        if (Test-Path $targetDir) {
                            Remove-Item -Recurse -Force $targetDir
                            Write-Host "[🗑] Deleted project: $projId" -ForegroundColor Red
                        }
                        $actionResults[$actionId] = @{ status = "success"; output = "Deleted" }
                    }
                }
                catch {
                    Write-Host "[!] Action failure: $_" -ForegroundColor Red
                    $actionResults[$actionId] = @{ status = "error"; output = "$_" }
                }
            }
        }
    }
    catch {
        Write-Host "[-] Pinging $ServerUrl..." -ForegroundColor DarkGray
    }

    Start-Sleep -Seconds 3
}