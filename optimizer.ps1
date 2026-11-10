<#
=====================================================================
  Optimizer.ps1
  Do tools ek hi run mein: WinUtil + doosra command.

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Optimizer.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Optimizer.ps1 -SkipSecond
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Optimizer.ps1 -OnlySecond
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Optimizer.ps1 -OpenSecondInBrowser
=====================================================================
#>
[CmdletBinding()]
param(
    [switch]$SkipFirst,
    [switch]$SkipSecond,
    [switch]$OnlyFirst,
    [switch]$OnlySecond,
    [switch]$OpenSecondInBrowser,
    [string]$LogDir = (Join-Path $env:TEMP 'OptimizerLogs')
)

$ErrorActionPreference = 'Continue'
$script:FailedCount = 0
$script:StartedAt   = Get-Date

# ---------------------------------------------------------------
# 0. Admin check + self elevation
# ---------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Admin rights nahi hain - UAC prompt khola ja raha hai...' -ForegroundColor Yellow
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -LogDir `"$LogDir`""
    foreach ($sw in 'SkipFirst','SkipSecond','OnlyFirst','OnlySecond','OpenSecondInBrowser') {
        if ((Get-Variable $sw -ValueOnly)) { $argLine += " -$sw" }
    }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argLine -Wait
    }
    catch {
        Write-Host 'Elevation cancel ho gaya. Admin PowerShell khol kar dobara chalao.' -ForegroundColor Red
        Read-Host 'Band karne ke liye Enter dabao'
    }
    return
}

# ---------------------------------------------------------------
# 1. Logging setup
# ---------------------------------------------------------------
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$logFile = Join-Path $LogDir ('Optimizer_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
try { Start-Transcript -Path $logFile -Force | Out-Null } catch { }

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','OK','WARN','ERR')][string]$Level = 'INFO'
    )
    $color = switch ($Level) {
        'OK'   { 'Green'  }
        'WARN' { 'Yellow' }
        'ERR'  { 'Red'    }
        default{ 'Cyan'   }
    }
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Write-Host $line -ForegroundColor $color
    Add-Content -LiteralPath $logFile -Value $line -ErrorAction SilentlyContinue
}

function Resolve-Url {
    param([Parameter(Mandatory)][string]$Url)
    if ($Url -match '^(?i)https?://') { return $Url }
    return "https://$Url"
}

# ---------------------------------------------------------------
# 2. Step definitions - dono commands yahan hain
# ---------------------------------------------------------------
$steps = @(
    [pscustomobject]@{
        Name   = 'ChrisTitusTech WinUtil'
        Url    = 'https://christitus.com/win'
        Script = 'irm https://christitus.com/win | iex'
        Skip   = [bool]($SkipFirst -or $OnlySecond)
        Hint   = $null
    }
    [pscustomobject]@{
        Name   = 'Doosra command (tinyurl.com/p9uvcp6c)'
        Url    = 'tinyurl.com/p9uvcp6c'
        Script = 'irm "tinyurl.com/p9uvcp6c" | iex'
        Skip   = [bool]($SkipSecond -or $OnlyFirst)
        Hint   = 'Ye link YouTube video hai (Rick Astley - Never Gonna Give You Up), PowerShell script nahi. iex HTML parse nahi kar sakta, isliye fail hoga. -OpenSecondInBrowser se browser mein khul jayega.'
    }
)

Write-Log '=====================================================' 'INFO'
Write-Log 'Optimizer shuru' 'INFO'
Write-Log ("Host   : {0}" -f $env:COMPUTERNAME) 'INFO'
Write-Log ("PS     : {0}" -f $PSVersionTable.PSVersion) 'INFO'
Write-Log ("Log    : {0}" -f $logFile) 'INFO'
Write-Log '=====================================================' 'INFO'

# ---------------------------------------------------------------
# 3. Execution loop
# ---------------------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]

foreach ($step in $steps) {

    if ($step.Skip) {
        Write-Log ("SKIP  -> {0}" -f $step.Name) 'WARN'
        $results.Add([pscustomobject]@{
            Tool    = $step.Name
            Status  = 'Skipped'
            Seconds = 0
        })
        continue
    }

    $url = Resolve-Url $step.Url

    Write-Log '-----------------------------------------------------' 'INFO'
    Write-Log ("RUN   -> {0}" -f $step.Name) 'INFO'
    Write-Log ("CMD   -> {0}" -f $step.Script) 'INFO'
    Write-Log ("URL   -> {0}" -f $url) 'INFO'

    $timer  = [System.Diagnostics.Stopwatch]::StartNew()
    $status = 'OK'

    try {
        $content = Invoke-RestMethod -Uri $url -UseBasicParsing -MaximumRedirection 10 -ErrorAction Stop
        $content | Invoke-Expression
        Write-Log ("DONE  -> {0}" -f $step.Name) 'OK'
    }
    catch {
        $status = 'Failed'
        $script:FailedCount++
        Write-Log ("FAIL  -> {0}" -f $step.Name) 'ERR'
        Write-Log ("Reason: {0}" -f $_.Exception.Message) 'ERR'
        if ($step.Hint) { Write-Log ("Hint  : {0}" -f $step.Hint) 'WARN' }

        if ($OpenSecondInBrowser -and $step.Name -like '*p9uvcp6c*') {
            try {
                Start-Process $url
                Write-Log 'Browser mein khol diya.' 'INFO'
            }
            catch {
                Write-Log 'Browser bhi nahi khul paya.' 'WARN'
            }
        }
    }
    finally {
        $timer.Stop()
    }

    $results.Add([pscustomobject]@{
        Tool    = $step.Name
        Status  = $status
        Seconds = [math]::Round($timer.Elapsed.TotalSeconds, 1)
    })
}

# ---------------------------------------------------------------
# 4. Summary
# ---------------------------------------------------------------
Write-Log '=====================================================' 'INFO'
Write-Log 'SUMMARY' 'INFO'
Write-Log '=====================================================' 'INFO'

$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

$elapsed = [math]::Round(((Get-Date) - $script:StartedAt).TotalSeconds, 1)
Write-Log ("Total time : {0}s" -f $elapsed) 'INFO'
Write-Log ("Failed     : {0}" -f $script:FailedCount) $(if ($script:FailedCount -gt 0) { 'WARN' } else { 'OK' })
Write-Log ("Log file   : {0}" -f $logFile) 'INFO'

try { Stop-Transcript | Out-Null } catch { }

Write-Host ''
Read-Host 'Band karne ke liye Enter dabao'

exit ([int]($script:FailedCount -gt 0))
