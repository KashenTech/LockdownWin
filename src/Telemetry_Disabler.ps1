 #Set-Content -Path ".\Disable_Hardware_Fing.ps1" -Encoding UTF8 -Value @'
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disables Windows telemetry / CEIP scheduled tasks that cause background
    CPU & disk spikes harmful to gaming and development workloads.

.DESCRIPTION
    Targets only Microsoft opt-in telemetry and Customer Experience Improvement
    Program (CEIP) tasks. Nothing here touches core Windows Update services,
    drivers, DirectX, .NET, or any game/dev runtime.

    Extra hardening options are offered interactively so you stay in control.

    Tasks handled:
      Application Experience\Microsoft Compatibility Appraiser  (CompatTelRunner.exe)
      Application Experience\ProgramDataUpdater
      Application Experience\StartupAppTask
      CEIP\Consolidator
      CEIP\UsbCeip
      CEIP\KernelCeipTask

    NOTE: Windows feature updates may re-enable these tasks.
    Re-run this script after major OS updates to restore your preferences.

.NOTES
    Author  : mkash
    Requires: PowerShell 5.1+ running as Administrator
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Header {
    param([string]$Text)
    Write-Host "`n==========================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
}
function Write-Ok   { param([string]$T); Write-Host "  [OK]   $T" -ForegroundColor Green }
function Write-Warn { param([string]$T); Write-Host "  [WARN] $T" -ForegroundColor DarkYellow }
function Write-Err  { param([string]$T); Write-Host "  [ERR]  $T" -ForegroundColor Red }
function Write-Step { param([string]$T); Write-Host "  >>     $T" -ForegroundColor Yellow }

function Confirm-Action {
    param([string]$Prompt)
    $reply = Read-Host "`n$Prompt [Y/N]"
    return ($reply -match '^[Yy]')
}

# ---------------------------------------------------------------------------
# Section 1 - Telemetry / CEIP Scheduled Tasks
# ---------------------------------------------------------------------------
Write-Header "1/4  Telemetry & CEIP Scheduled Tasks"

$tasks = @(
    @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "Microsoft Compatibility Appraiser" },
    @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "ProgramDataUpdater" },
    @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "StartupAppTask" },
    @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "Consolidator" },
    @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "UsbCeip" },
    @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "KernelCeipTask" }
)

$disabledCount = 0
$skippedCount  = 0

foreach ($t in $tasks) {
    try {
        $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop
        if ($task.State -eq 'Disabled') {
            Write-Ok "$($t.Name)  [already disabled]"
            $skippedCount++
        } else {
            Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null
            Write-Ok "$($t.Name)  -> Disabled"
            $disabledCount++
        }
    } catch {
        Write-Warn "$($t.Name)  not found on this edition (skipped)"
        $skippedCount++
    }
}

Write-Host "`n  Tasks disabled this run : $disabledCount" -ForegroundColor Cyan
Write-Host "  Tasks already OK / N/A  : $skippedCount"   -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Section 2 - DiagTrack service (Connected User Experiences & Telemetry)
# ---------------------------------------------------------------------------
Write-Header "2/4  DiagTrack Telemetry Service"

$diagTrack = Get-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue
if ($diagTrack) {
    if ($diagTrack.StartType -eq 'Disabled') {
        Write-Ok "DiagTrack  [already disabled]"
    } else {
        try {
            Stop-Service -Name 'DiagTrack' -Force -ErrorAction Stop
            Set-Service  -Name 'DiagTrack' -StartupType Disabled -ErrorAction Stop
            Write-Ok "DiagTrack stopped and set to Disabled"
        } catch {
            Write-Err "Could not disable DiagTrack: $_"
        }
    }
} else {
    Write-Warn "DiagTrack not found (may already be removed)"
}

# ---------------------------------------------------------------------------
# Section 3 - dmwappushservice (WAP Push telemetry router) - user choice
# ---------------------------------------------------------------------------
Write-Header "3/4  WAP Push Router Service  (dmwappushservice)"

$wap = Get-Service -Name 'dmwappushservice' -ErrorAction SilentlyContinue
if ($wap) {
    if ($wap.StartType -eq 'Disabled') {
        Write-Ok "dmwappushservice  [already disabled]"
    } else {
        if (Confirm-Action "  Disable dmwappushservice (WAP Push telemetry router)?") {
            try {
                Stop-Service -Name 'dmwappushservice' -Force -ErrorAction SilentlyContinue
                Set-Service  -Name 'dmwappushservice' -StartupType Disabled -ErrorAction Stop
                Write-Ok "dmwappushservice disabled"
            } catch {
                Write-Err "Could not disable dmwappushservice: $_"
            }
        } else {
            Write-Step "Skipped by user."
        }
    }
} else {
    Write-Warn "dmwappushservice not found (skipped)"
}

# ---------------------------------------------------------------------------
# Section 4 - Optional extra tweaks (gaming + dev)
# ---------------------------------------------------------------------------
Write-Header "4/4  Optional Extra Tweaks"

# -- 4a. Gaming tweaks -------------------------------------------------------
if (Confirm-Action "  Apply gaming tweaks? (Game DVR off, HW-Accelerated GPU Scheduling on, SysMain off)") {
    Write-Step "Applying gaming registry tweaks..."

    # Disable Game DVR / Game Bar background capture (removes background video-encoding overhead)
    $gameDVRKey = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR"
    if (-not (Test-Path $gameDVRKey)) { New-Item -Path $gameDVRKey -Force | Out-Null }
    Set-ItemProperty -Path $gameDVRKey -Name "value" -Value 0 -Type DWord -Force
    Write-Ok "Game DVR disabled via policy"

    # Hardware-Accelerated GPU Scheduling (HAGS) - reduces CPU overhead for GPU frame delivery
    $gpuKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    Set-ItemProperty -Path $gpuKey -Name "HwSchMode" -Value 2 -Type DWord -Force
    Write-Ok "HAGS (HwSchMode=2) enabled"

    # Disable SysMain (Superfetch) - beneficial on SSD systems or when you have plenty of RAM
    $sysMain = Get-Service -Name 'SysMain' -ErrorAction SilentlyContinue
    if ($sysMain -and $sysMain.StartType -ne 'Disabled') {
        Stop-Service -Name 'SysMain' -Force -ErrorAction SilentlyContinue
        Set-Service  -Name 'SysMain' -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Ok "SysMain (Superfetch) disabled"
    } elseif ($sysMain) {
        Write-Ok "SysMain  [already disabled]"
    }

    Write-Warn "Restart recommended for HAGS to take full effect."
} else {
    Write-Step "Skipped gaming tweaks."
}

# -- 4b. Developer tweak: Windows Search indexer -----------------------------
if (Confirm-Action "  Disable Windows Search indexing service? (Frees CPU/disk during compiles & Docker builds)") {
    $wsearch = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
    if ($wsearch) {
        if ($wsearch.StartType -eq 'Disabled') {
            Write-Ok "WSearch  [already disabled]"
        } else {
            Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
            Set-Service  -Name 'WSearch' -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Ok "WSearch service disabled"
        }
    } else {
        Write-Warn "WSearch service not found (skipped)"
    }
} else {
    Write-Step "Skipped Windows Search tweak."
}

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
Write-Header "Done"
Write-Host @"

  Summary:
    [OK]  CEIP / telemetry scheduled tasks  - processed
    [OK]  DiagTrack service                 - handled
    [ ?]  dmwappushservice                  - per your choice above
    [ ?]  Gaming tweaks (DVR/HAGS/SysMain)  - per your choice above
    [ ?]  WSearch indexer                   - per your choice above

  Safe to run again at any time.
  Re-run after major Windows feature updates to re-apply your preferences.

  Nothing here touches drivers, DirectX, .NET, VC++ runtimes, or game files.

"@ -ForegroundColor Gray
'@
