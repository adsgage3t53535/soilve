# ================================================================
#  MONITOR - VoltPro Watchdog + Roblox Error Killer + FarmSync
# ================================================================

# ── Auto-elevacao para Administrador ────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) {
        # Executado via iex/irm — salva em disco e relanca como admin
        $scriptPath = "$env:TEMP\monitor_run.ps1"
        $MyInvocation.MyCommand.ScriptBlock | Out-String | Set-Content $scriptPath -Encoding UTF8
    }
    Start-Process 'powershell.exe' -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

$host.UI.RawUI.WindowTitle = 'Monitor'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr i, int x, int y, int w, int ht, uint f);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc p, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr wp, IntPtr lp2);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int nCmdShow);
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    public const int SW_MINIMIZE = 6;
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr lp);
}
'@ -ErrorAction SilentlyContinue

# ── Configuracoes ────────────────────────────────────────────────
$VoltExe      = "$env:USERPROFILE\Desktop\VoltBlack\VoltPro_6.6.exe"
$VoltProc     = [System.IO.Path]::GetFileNameWithoutExtension($VoltExe)

$FarmSyncExe  = "$env:USERPROFILE\Desktop\farmsync\client_web.exe"
$FarmSyncBat  = "$env:USERPROFILE\Desktop\farmsync\FarmSync_AutoStart.bat"
$FarmSyncKey  = "$env:USERPROFILE\Desktop\farmsync\key.txt"

$LogFile      = $env:TEMP + '\monitor.log'
$StopFile     = $env:TEMP + '\monitor.stop'
$WinW         = 900; $WinH = 500
$CmdW         = 700; $CmdH = 500
$ApiUrl       = 'https://vps-production-2bd3.up.railway.app'
$ApiKey       = 'GobrinNoti'
$ApiHeaders   = @{ 'X-Api-Key' = $ApiKey }
$GithubUrl    = 'https://raw.githubusercontent.com/adsgage3t53535/soilve/refs/heads/main/volt-watchdog.ps1'
$WebRBDir     = "$env:USERPROFILE\Desktop\WebRB\YummyWebPlayer"
$WebRBExe     = 'webrb.exe'
$ErrorTitles  = @('Error','Roblox Error','Crash','Disconnected','An error occurred','Notice')

# MachineId via auth.json (Note field)
$_authFile = "$WebRBDir\auth.json"
$MachineId = try {
    $j = Get-Content $_authFile -Raw -EA Stop | ConvertFrom-Json
    if ($j.Note) { $j.Note } else { $env:COMPUTERNAME }
} catch { $env:COMPUTERNAME }

$script:Paused    = $false
$script:CurHash   = $null

# ── Log ─────────────────────────────────────────────────────────
$script:LogBuffer = [System.Collections.Generic.List[hashtable]]::new()

function wLog($m, $l = 'INFO') {
    $time = Get-Date -f 'HH:mm:ss'
    $s    = '[' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + '][' + $l + '] ' + $m
    Write-Host '  [' -NoNewline -ForegroundColor DarkGray
    Write-Host $time  -NoNewline -ForegroundColor Cyan
    Write-Host '] '   -NoNewline -ForegroundColor DarkGray
    switch ($l) {
        'WARN'  { Write-Host 'AVISO  ' -NoNewline -ForegroundColor Yellow; Write-Host $m -ForegroundColor Yellow }
        'ERROR' { Write-Host 'ERRO   ' -NoNewline -ForegroundColor Red;    Write-Host $m -ForegroundColor Red    }
        'OK'    { Write-Host 'OK     ' -NoNewline -ForegroundColor Green;   Write-Host $m -ForegroundColor Green  }
        default { Write-Host $m -ForegroundColor White }
    }
    Add-Content $LogFile $s -Encoding UTF8
    $lines = Get-Content $LogFile -EA SilentlyContinue
    if ($lines.Count -gt 500) { $lines | Select-Object -Last 250 | Set-Content $LogFile -Encoding UTF8 }
    $script:LogBuffer.Add(@{ t = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); l = $l; m = $m })
    if ($script:LogBuffer.Count -gt 100) { $script:LogBuffer.RemoveAt(0) }
}
function Separador { Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray }

# ── Organizar janelas ────────────────────────────────────────────
function OrganizarJanela {
    $sw = [WinAPI]::GetSystemMetrics(0)
    $sh = [WinAPI]::GetSystemMetrics(1)
    $vProc = GetVoltProc
    if ($vProc -and $vProc.MainWindowHandle -ne [IntPtr]::Zero) {
        $xV = $sw - $WinW - 10; $yV = $sh - $WinH - 50
        [WinAPI]::SetWindowPos($vProc.MainWindowHandle, [IntPtr]::Zero, $xV, $yV, $WinW, $WinH, 0x0040) | Out-Null
    }
    $wProc = Get-Process -Name 'webrb','WebRB' -EA SilentlyContinue | Select-Object -First 1
    if ($wProc -and $wProc.MainWindowHandle -ne [IntPtr]::Zero) {
        $xR = $sw - $WinW - 10; $yR = $sh - $WinH - 50 - $WinH - 10
        [WinAPI]::SetWindowPos($wProc.MainWindowHandle, [IntPtr]::Zero, $xR, $yR, $WinW, $WinH, 0x0040) | Out-Null
    }
    $hwndCmd = [WinAPI]::GetConsoleWindow()
    if ($hwndCmd -ne [IntPtr]::Zero) {
        $xC = $sw - $WinW - 10 - $CmdW - 10; $yC = $sh - $CmdH - 50
        [WinAPI]::SetWindowPos($hwndCmd, [IntPtr]::Zero, $xC, $yC, $CmdW, $CmdH, 0x0040) | Out-Null
    }
    MinimizarRoblox
}

# ── Roblox Minimizer ─────────────────────────────────────────────
# PostMessage WM_SYSCOMMAND/SC_MINIMIZE nao e bloqueado pelo UIPI
# (funciona sem admin, ao contrario de ShowWindow em processos elevados)
function MinimizarRoblox {
    $robloxPids = @(Get-Process -Name 'RobloxPlayerBeta','RobloxPlayer' -EA SilentlyContinue).Id
    if (-not $robloxPids -or $robloxPids.Count -eq 0) { return }
    $WM_SYSCOMMAND = [IntPtr]0x0112
    $SC_MINIMIZE   = [IntPtr]0xF020
    $callback = [WinAPI+EnumWindowsProc]{
        param($hwnd, $lp)
        if ([WinAPI]::IsWindowVisible($hwnd)) {
            $pid2 = 0
            [WinAPI]::GetWindowThreadProcessId($hwnd, [ref]$pid2) | Out-Null
            if ($robloxPids -contains $pid2) {
                [WinAPI]::PostMessage($hwnd, 0x0112, [IntPtr]0xF020, [IntPtr]::Zero) | Out-Null
            }
        }
        return $true
    }
    [WinAPI]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
}

# ── Background runspace: minimiza Roblox a cada 2s ──────────────
# MinimizarRoblox e chamado diretamente no loop principal a cada 2s (via $script:LastMin)

# ── VoltPro ──────────────────────────────────────────────────────
function GetVoltProc {
    Get-Process -EA SilentlyContinue | Where-Object {
        try { $_.Path -eq $VoltExe } catch { $false }
    } | Select-Object -First 1
}

function AbrirVolt {
    wLog 'Abrindo VoltPro...' 'OK'
    Start-Process $VoltExe
    Start-Sleep 8
    OrganizarJanela
}

function FecharVolt {
    wLog 'Fechando VoltPro...' 'WARN'
    GetVoltProc | Stop-Process -Force -EA SilentlyContinue
}

function ReiniciarVolt {
    Separador
    wLog 'Reiniciando VoltPro...' 'WARN'
    GetVoltProc | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 3
    Start-Process $VoltExe
    Start-Sleep 8
    OrganizarJanela
    Separador
}

# ── WebRB / Yummy ────────────────────────────────────────────────
function AbrirWebRB {
    wLog 'Abrindo WebRB...' 'OK'
    Start-Process 'cmd.exe' -ArgumentList "/c cd /d `"$WebRBDir`" & start `"`" `"$WebRBExe`""
}

function FecharWebRB {
    wLog 'Fechando WebRB/Yummy...' 'WARN'
    'webrb','WebRB','YummyWebPlayer','yummy' | ForEach-Object {
        Get-Process -Name $_ -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    }
    Get-Process -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*Yummy*' -or $_.MainWindowTitle -like '*WebRB*' } | Stop-Process -Force -EA SilentlyContinue
}

# ── FarmSync ─────────────────────────────────────────────────────
function GetFarmSyncProc {
    Get-Process -EA SilentlyContinue | Where-Object {
        try { $_.Path -eq $FarmSyncExe } catch { $false }
    } | Select-Object -First 1
}

# Detecta se o FarmSync esta aberto pelo exe
function FarmSyncAberto {
    $p = GetFarmSyncProc
    if ($p) { return $true }
    # Fallback: pelo nome do exe
    $exeName = [System.IO.Path]::GetFileNameWithoutExtension($FarmSyncExe)
    $p2 = Get-Process -Name $exeName -EA SilentlyContinue | Select-Object -First 1
    return ($null -ne $p2)
}

function AbrirFarmSync {
    wLog 'Abrindo FarmSync...' 'OK'
    if (-not (Test-Path $FarmSyncExe)) {
        wLog "FarmSync exe nao encontrado: $FarmSyncExe" 'ERROR'
        return
    }
    $farmDir = [System.IO.Path]::GetDirectoryName($FarmSyncExe)
    Start-Process -FilePath $FarmSyncExe -WorkingDirectory $farmDir -ErrorAction SilentlyContinue
    Start-Sleep 3
}

function FecharFarmSync {
    wLog 'Fechando FarmSync...' 'WARN'
    # Por path exato
    GetFarmSyncProc | Stop-Process -Force -EA SilentlyContinue
    # Por nome do exe (client_web.exe)
    Get-Process -Name 'client_web' -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    # Qualquer processo cujo exe esteja na pasta farmsync
    $farmDir = [System.IO.Path]::GetDirectoryName($FarmSyncExe)
    Get-Process -EA SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($farmDir, [System.StringComparison]::OrdinalIgnoreCase) } catch { $false }
    } | Stop-Process -Force -EA SilentlyContinue
}

function ReiniciarFarmSync {
    Separador
    wLog 'Reiniciando FarmSync...' 'WARN'
    FecharFarmSync
    Start-Sleep 2
    AbrirFarmSync
    Separador
}

function SetFarmSyncKey($key) {
    try {
        $key = $key.Trim()
        if ($key.Length -ne 64) {
            wLog "SetFarmSyncKey: key invalida (esperado 64 chars, recebido $($key.Length))" 'ERROR'
            return $false
        }
        $dir = Split-Path $FarmSyncKey
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($FarmSyncKey, $key, [System.Text.UTF8Encoding]::new($false))
        wLog "FarmSync key atualizada: $($key.Substring(0,8))..." 'OK'
        return $true
    } catch {
        wLog "Erro ao gravar FarmSync key: $_" 'ERROR'
        return $false
    }
}

# ── Roblox ───────────────────────────────────────────────────────
function FecharTodosRoblox {
    $procs = Get-Process -Name 'RobloxPlayerBeta','RobloxPlayer' -EA SilentlyContinue
    if ($procs) {
        wLog "Fechando $($procs.Count) processo(s) Roblox..." 'WARN'
        $procs | Stop-Process -Force -EA SilentlyContinue
    }
    Get-Process -Name 'RobloxCrashHandler' -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
}

# ── Fechar tudo ──────────────────────────────────────────────────
function FecharTudo {
    FecharTodosRoblox
    FecharVolt
    FecharWebRB
    FecharFarmSync
}

# ── Reiniciar tudo ───────────────────────────────────────────────
function ReiniciarTudo {
    Separador
    wLog 'REINICIANDO TUDO...' 'WARN'
    FecharTodosRoblox
    FecharVolt
    FecharWebRB
    FecharFarmSync
    $wsDir = $env:USERPROFILE + '\Desktop\VoltBlack\workspace'
    if (Test-Path $wsDir) {
        Get-ChildItem $wsDir -Recurse | Remove-Item -Force -Recurse -EA SilentlyContinue
        wLog 'Workspace limpo.' 'OK'
    }
    Start-Sleep 3
    wLog 'Abrindo VoltPro...' 'OK'
    Start-Process $VoltExe
    Start-Sleep 10
    wLog 'Abrindo WebRB...' 'OK'
    AbrirWebRB
    Start-Sleep 5
    OrganizarJanela
    Separador
}

# ── Autoexec ─────────────────────────────────────────────────────
function SetAutoexec($url) {
    $dir = $env:USERPROFILE + '\Desktop\VoltBlack\autoexec'
    try {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Get-ChildItem $dir | Where-Object { $_.Name -ne 'checkyummy.lua' } | Remove-Item -Force -EA SilentlyContinue
        $fileName = [System.IO.Path]::GetFileName(([uri]$url).LocalPath)
        if (-not $fileName -or $fileName -notmatch '\.\w+$') { $fileName = 'Script.txt' }
        $dest = "$dir\$fileName"
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 15 -EA Stop
        wLog "Autoexec baixado: $fileName" 'OK'
    } catch {
        wLog "Erro ao baixar autoexec: $_" 'ERROR'
    }
}

# ── Fechar erros Roblox ──────────────────────────────────────────
function CheckAndKillErrors {
    $robloxPids = (Get-Process -Name 'RobloxPlayerBeta','RobloxPlayer' -EA SilentlyContinue).Id
    if (-not $robloxPids) { return }
    $callback = [WinAPI+EnumWindowsProc]{
        param($hwnd, $lp)
        if ([WinAPI]::IsWindowVisible($hwnd)) {
            $pid2 = 0
            [WinAPI]::GetWindowThreadProcessId($hwnd, [ref]$pid2) | Out-Null
            if ($robloxPids -contains $pid2) {
                $sb = New-Object System.Text.StringBuilder 256
                [WinAPI]::GetWindowText($hwnd, $sb, 256) | Out-Null
                $title = $sb.ToString()
                foreach ($t in $ErrorTitles) {
                    if ($title -eq $t -or $title -like "*$t*") {
                        wLog "Roblox erro fechado: '$title'" 'OK'
                        [WinAPI]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
                        break
                    }
                }
            }
        }
        return $true
    }
    [WinAPI]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
}

# ── Detector de NOTICE (VoltPro) ─────────────────────────────────
function CheckNotice {
    $voltProc = GetVoltProc
    if (-not $voltProc) { $script:NoticeCount = 0; return }
    $allPids = @($voltProc.Id)
    try { $allPids += (Get-Process -EA SilentlyContinue | Where-Object { $_.Parent.Id -eq $voltProc.Id }).Id } catch {}
    $callback2 = [WinAPI+EnumWindowsProc]{
        param($hwnd, $lp)
        if ([WinAPI]::IsWindowVisible($hwnd)) {
            $pid2 = 0
            [WinAPI]::GetWindowThreadProcessId($hwnd, [ref]$pid2) | Out-Null
            if ($allPids -contains $pid2) {
                $sb2 = New-Object System.Text.StringBuilder 256
                [WinAPI]::GetWindowText($hwnd, $sb2, 256) | Out-Null
                $t2 = $sb2.ToString()
                if ($t2 -match 'Notice|NOTICE') {
                    $script:found_notice = $true
                    [WinAPI]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
                }
            }
        }
        return $true
    }
    $script:found_notice = $false
    [WinAPI]::EnumWindows($callback2, [IntPtr]::Zero) | Out-Null
    if ($script:found_notice) {
        $script:NoticeCount++
        wLog "NOTICE detectado ($($script:NoticeCount)x)" 'WARN'
        if ($script:NoticeCount -ge 2) {
            wLog 'NOTICE 2x consecutivo — Reiniciando VoltPro...' 'ERROR'
            $script:NoticeCount = 0
            try { ReiniciarVolt } catch { wLog "Erro ao reiniciar Volt apos NOTICE: $_" 'ERROR' }
        }
    } else {
        $script:NoticeCount = 0
    }
}

# ── Auto-update ──────────────────────────────────────────────────
function CheckUpdate {
    try {
        $raw   = (Invoke-WebRequest -Uri $GithubUrl -UseBasicParsing -TimeoutSec 10 -EA Stop).Content
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
        $hash  = ([System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash($bytes))).Replace('-','')
        if ($null -eq $script:CurHash) {
            $script:CurHash = $hash
        } elseif ($hash -ne $script:CurHash) {
            wLog 'Nova versao detectada. Atualizando...' 'WARN'
            $script:CurHash = $hash
            # Salva o script novo em disco e executa em nova janela,
            # passando o PID atual para que o novo processo feche esta janela.
            $tmpPath = "$env:TEMP\monitor_update.ps1"
            [System.IO.File]::WriteAllText($tmpPath, $raw, [System.Text.UTF8Encoding]::new($false))
            $selfPid = $PID
            # Wrapper: mata o processo antigo apos 3s e executa o novo script
            $launcher = "Start-Sleep 3; Stop-Process -Id $selfPid -Force -EA SilentlyContinue; & '$tmpPath'"
            Start-Process 'powershell.exe' -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$launcher`"" -WindowStyle Normal
            exit
        }
    } catch { }
}

# ── Metricas de sistema em background (CPU/RAM a cada 30s) ───────
$shared = [ref]@{ cpu = 0; ramUsed = 0; ramTotal = 0 }

$metricsScript = {
    param($sharedRef)
    while ($true) {
        try {
            $s1 = Get-CimInstance -Query "select PercentIdleTime, Timestamp_Sys100NS from Win32_PerfRawData_PerfOS_Processor where Name='_Total'" -EA Stop
            Start-Sleep -Milliseconds 1000
            $s2 = Get-CimInstance -Query "select PercentIdleTime, Timestamp_Sys100NS from Win32_PerfRawData_PerfOS_Processor where Name='_Total'" -EA Stop
            $idleDelta = $s2.PercentIdleTime    - $s1.PercentIdleTime
            $timeDelta = $s2.Timestamp_Sys100NS - $s1.Timestamp_Sys100NS
            $idle = if ($timeDelta -gt 0) { $idleDelta / $timeDelta * 100 } else { 100 }
            $cpu  = [Math]::Round(100 - $idle, 1)
            if ($cpu -lt 0) { $cpu = 0 }
            $os = Get-CimInstance Win32_OperatingSystem -EA Stop
            $total = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
            $free  = [Math]::Round($os.FreePhysicalMemory     / 1MB, 2)
            $used  = [Math]::Round($total - $free, 2)
            $sharedRef.Value = @{ cpu = $cpu; ramUsed = $used; ramTotal = $total }
        } catch {}
        Start-Sleep -Seconds 29
    }
}

$rs = [RunspaceFactory]::CreateRunspace()
$rs.Open()
$rs.SessionStateProxy.SetVariable('sharedRef', $shared)
$ps = [PowerShell]::Create()
$ps.Runspace = $rs
[void]$ps.AddScript($metricsScript)
[void]$ps.AddArgument($shared)
$ps.BeginInvoke() | Out-Null

# ── Reportar metricas ao servidor ───────────────────────────────
function ReportMetrics {
    try {
        $roblox   = @(Get-Process -Name 'RobloxPlayerBeta','RobloxPlayer' -EA SilentlyContinue).Count
        $volt     = if (GetVoltProc) { 1 } else { 0 }
        $webrb    = if (Get-Process -Name 'webrb','WebRB' -EA SilentlyContinue | Select-Object -First 1) { 1 } else { 0 }
        $farmsync = if (FarmSyncAberto) { 1 } else { 0 }
        $voltUser = ''
        $cfgPath = "$env:USERPROFILE\Desktop\VoltBlack\volt_config.json"
        if (Test-Path $cfgPath) {
            try { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json; $voltUser = if ($cfg.username) { $cfg.username } else { '' } } catch { }
        }
        $m        = $shared.Value
        $cpu      = if ($m.cpu)      { $m.cpu }      else { 0 }
        $ramUsed  = if ($m.ramUsed)  { $m.ramUsed }  else { 0 }
        $ramTotal = if ($m.ramTotal) { $m.ramTotal }  else { 0 }

        # Signature para detectar mudancas — CPU arredondado em 2% p/ evitar ruido
        $cpuR  = [Math]::Round($cpu / 2) * 2
        $sig   = "$roblox|$volt|$webrb|$farmsync|$voltUser|$cpuR|$([Math]::Round($ramUsed,1))"

        $script:ForceReportIn--
        $mustSend = ($sig -ne $script:LastReportSig) -or ($script:ForceReportIn -le 0)
        if (-not $mustSend) { return }  # nada mudou, pula o POST

        $script:LastReportSig = $sig
        $script:ForceReportIn = 60   # forca envio a cada ~5 min (60 * 5s)

        $body = @{ roblox = $roblox; volt = $volt; webrb = $webrb; farmsync = $farmsync; voltUser = $voltUser; cpu = $cpu; ramUsed = $ramUsed; ramTotal = $ramTotal } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "$ApiUrl/report/$MachineId" -Method POST -Headers $ApiHeaders -Body $body -ContentType 'application/json' -TimeoutSec 5 -EA Stop | Out-Null
    } catch { }
    # flush log buffer sempre (independente de delta)
    try {
        if ($script:LogBuffer.Count -gt 0) {
            $toSend = $script:LogBuffer.ToArray()
            $script:LogBuffer.Clear()
            $logBody = @{ entries = $toSend } | ConvertTo-Json -Compress -Depth 5
            Invoke-RestMethod -Uri "$ApiUrl/devicelog/$MachineId" -Method POST -Headers $ApiHeaders -Body $logBody -ContentType 'application/json' -TimeoutSec 5 -EA SilentlyContinue | Out-Null
        }
    } catch { }
}


# SendAck agora via ackQueue (definida no bloco do runspace de poll abaixo)

# ── Poll em runspace separado — nao bloqueia o loop principal ────
# Fila thread-safe: runspace deposita comandos, loop principal consome
$cmdQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
# Fila de ACKs: loop principal deposita, runspace envia ao servidor
$ackQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$pollStop = [ref]$false

# Runspace 1: long-poll — so recebe comandos, nao envia ACKs
$pollScript = {
    param($apiUrl, $machineId, $apiKey, $cmdQueue, $pollStop)
    $headers   = @{ 'X-Api-Key' = $apiKey }
    $failCount = 0
    while (-not $pollStop.Value) {
        try {
            $r = Invoke-RestMethod -Uri "$apiUrl/poll/$machineId" -Method GET -Headers $headers -TimeoutSec 15 -EA Stop
            if ($failCount -gt 0) {
                $cmdQueue.Enqueue(@{ _internal = 'restored'; failCount = $failCount })
                $failCount = 0
            }
            foreach ($item in $r.commands) { $cmdQueue.Enqueue($item) }
        } catch {
            $failCount++
            $cmdQueue.Enqueue(@{ _internal = 'fail'; count = $failCount; msg = "$_" })
            Start-Sleep -Seconds 2
        }
    }
}

# Runspace 2: ACK sender — loop rapido dedicado, envia assim que chega
$ackScript = {
    param($apiUrl, $machineId, $apiKey, $ackQueue, $pollStop)
    $headers = @{ 'X-Api-Key' = $apiKey }
    while (-not $pollStop.Value) {
        $ackItem = $null
        $sent = $false
        while ($ackQueue.TryDequeue([ref]$ackItem)) {
            try {
                $body = $ackItem | ConvertTo-Json -Compress
                Invoke-RestMethod -Uri "$apiUrl/ack/$machineId" -Method POST -Headers $headers -Body $body -ContentType 'application/json' -TimeoutSec 4 -EA Stop | Out-Null
            } catch {}
            $sent = $true
        }
        # So dorme se nao tinha nada — evita CPU desnecessaria
        if (-not $sent) { Start-Sleep -Milliseconds 200 }
    }
}

$rsPoll = [RunspaceFactory]::CreateRunspace(); $rsPoll.Open()
$psPoll = [PowerShell]::Create(); $psPoll.Runspace = $rsPoll
[void]$psPoll.AddScript($pollScript)
[void]$psPoll.AddArgument($ApiUrl)
[void]$psPoll.AddArgument($MachineId)
[void]$psPoll.AddArgument($ApiKey)
[void]$psPoll.AddArgument($cmdQueue)
[void]$psPoll.AddArgument($pollStop)
$psPoll.BeginInvoke() | Out-Null

$rsAck = [RunspaceFactory]::CreateRunspace(); $rsAck.Open()
$psAck = [PowerShell]::Create(); $psAck.Runspace = $rsAck
[void]$psAck.AddScript($ackScript)
[void]$psAck.AddArgument($ApiUrl)
[void]$psAck.AddArgument($MachineId)
[void]$psAck.AddArgument($ApiKey)
[void]$psAck.AddArgument($ackQueue)
[void]$psAck.AddArgument($pollStop)
$psAck.BeginInvoke() | Out-Null

function SendAck($cmd, $success, $errMsg) {
    $b = if ($errMsg) { @{ cmd = $cmd; success = $false; error = $errMsg } } else { @{ cmd = $cmd; success = [bool]$success } }
    $ackQueue.Enqueue($b)
}

function DrainCommands {
    $item = $null
    while ($cmdQueue.TryDequeue([ref]$item)) {
        if ($item -is [hashtable] -and $item['_internal']) {
            switch ($item['_internal']) {
                'restored' { wLog "Conexao restaurada apos $($item.failCount) falhas." 'OK' }
                'fail'     {
                    $fc = $item.count
                    if ($fc -eq 1 -or $fc % 10 -eq 0) {
                        wLog "Falha ao conectar ao servidor ($($fc)x): $($item.msg)" 'WARN'
                    }
                }
            }
            continue
        }
        if ($item -is [string]) { $cmd = $item; $data = $null }
        else                    { $cmd = $item.cmd; $data = $item.data }
        switch ($cmd) {
            'open_volt'          { try { AbrirVolt;         SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
            'close_volt'         { try { FecharVolt;        SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
            'restart_volt'       { try { ReiniciarVolt;     SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
            'open_webrb'         { try { AbrirWebRB;        SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
            'close_webrb'        { try { FecharWebRB;       SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
            'close_all_roblox'   { try { FecharTodosRoblox; SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
            'restart_all'        { try { ReiniciarTudo;     SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
            'organize_windows'   { try { OrganizarJanela;   SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
            'minimize_roblox'    { try { MinimizarRoblox;   SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
            'open_farmsync'      { try { AbrirFarmSync;     SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
            'close_farmsync'     { try { FecharFarmSync;    SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
            'restart_farmsync'   { try { ReiniciarFarmSync; SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
            'set_farmsync_key' {
                if ($data) {
                    try { $ok = SetFarmSyncKey $data; if ($ok) { SendAck $cmd $true } else { SendAck $cmd $false 'key invalida' } }
                    catch { SendAck $cmd $false "$_" }
                } else { wLog 'set_farmsync_key: key vazia' 'WARN'; SendAck $cmd $false 'key vazia' }
            }
            'restart_cmd' {
                SendAck $cmd $true; wLog 'Reiniciando CMD...' 'WARN'
                try {
                    $raw2 = (Invoke-WebRequest -Uri $GithubUrl -UseBasicParsing -TimeoutSec 10 -EA Stop).Content
                    $tmp2 = "$env:TEMP\monitor_update.ps1"
                    [System.IO.File]::WriteAllText($tmp2, $raw2, [System.Text.UTF8Encoding]::new($false))
                    $selfPid2  = $PID
                    $launcher2 = "Start-Sleep 3; Stop-Process -Id $selfPid2 -Force -EA SilentlyContinue; & '$tmp2'"
                    Start-Process 'powershell.exe' -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$launcher2`"" -WindowStyle Normal
                } catch {
                    $selfPid2  = $PID
                    $launcher2 = "Start-Sleep 3; Stop-Process -Id $selfPid2 -Force -EA SilentlyContinue; iex (irm '$GithubUrl')"
                    Start-Process 'powershell.exe' -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$launcher2`"" -WindowStyle Normal
                }
                exit
            }
            'set_autoexec' {
                if ($data) { try { SetAutoexec $data; SendAck $cmd $true } catch { SendAck $cmd $false "$_" } }
                else { wLog 'set_autoexec: URL vazia' 'WARN'; SendAck $cmd $false 'URL vazia' }
            }
            'set_cookies' {
                $ckPath = "$env:USERPROFILE\Desktop\WebRB\YummyWebPlayer\cookie.txt"
                if ($data) {
                    try {
                        $unicos = ($data | Where-Object { $_ -ne $null -and $_.Trim() -ne '' }) | Select-Object -Unique
                        [System.IO.File]::WriteAllLines($ckPath, $unicos, [System.Text.UTF8Encoding]::new($false))
                        wLog "Cookies gravados: $($unicos.Count) linhas" 'OK'; SendAck $cmd $true
                    } catch { wLog "Erro ao gravar cookies: $_" 'ERROR'; SendAck $cmd $false "$_" }
                } else { wLog 'set_cookies: dados vazios' 'WARN'; SendAck $cmd $false 'dados vazios' }
            }
            'clear_switched' {
                $swDir = "$env:USERPROFILE\Desktop\WebRB\YummyWebPlayer\switched"
                try {
                    if (Test-Path $swDir) {
                        $files = Get-ChildItem $swDir -Filter '*.txt' -EA SilentlyContinue
                        $files | Remove-Item -Force -EA SilentlyContinue
                        wLog "Pasta switched limpa: $($files.Count) arquivo(s)" 'OK'
                    } else { wLog 'Pasta switched nao encontrada' 'WARN' }
                    SendAck $cmd $true
                } catch { wLog "Erro ao limpar switched: $_" 'ERROR'; SendAck $cmd $false "$_" }
            }
            'apply_volt_config' {
                $cfgPath = "$env:USERPROFILE\Desktop\VoltBlack\volt_config.json"
                if ($data) {
                    try {
                        $keep = @{ password = $null; username = $null }
                        if (Test-Path $cfgPath) { $cur = Get-Content $cfgPath -Raw | ConvertFrom-Json; $keep.password = $cur.password; $keep.username = $cur.username }
                        $obj = $data | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                        if ($keep.password) { $obj | Add-Member -MemberType NoteProperty -Name 'password' -Value $keep.password -Force }
                        if ($keep.username)  { $obj | Add-Member -MemberType NoteProperty -Name 'username'  -Value $keep.username  -Force }
                        $obj | ConvertTo-Json -Depth 10 | Set-Content -Path $cfgPath -Encoding UTF8
                        wLog 'volt_config.json atualizado' 'OK'; SendAck $cmd $true
                    } catch { wLog "Erro ao gravar volt_config: $_" 'ERROR'; SendAck $cmd $false "$_" }
                } else { wLog 'apply_volt_config: dados vazios' 'WARN'; SendAck $cmd $false 'dados vazios' }
            }
            'apply_webrb_config' {
                $cfgPath = "$env:USERPROFILE\Desktop\WebRB\YummyWebPlayer\config.json"
                if ($data) {
                    try {
                        $dir = Split-Path $cfgPath
                        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
                        $json = ($data | ConvertTo-Json -Depth 10) -replace 'C:\\\\Users\\\\[^\\\\]+\\\\', "C:\\\\Users\\\\$($env:USERNAME)\\\\"
                        $json | Set-Content -Path $cfgPath -Encoding UTF8
                        wLog "config.json (WebRB) atualizado: $($env:USERNAME)" 'OK'; SendAck $cmd $true
                    } catch { wLog "Erro ao gravar config.json: $_" 'ERROR'; SendAck $cmd $false "$_" }
                } else { wLog 'apply_webrb_config: dados vazios' 'WARN'; SendAck $cmd $false 'dados vazios' }
            }
            'clear_cookies' {
                $ckPath = "$env:USERPROFILE\Desktop\WebRB\YummyWebPlayer\cookie.txt"
                try { [System.IO.File]::WriteAllText($ckPath, ''); wLog 'cookie.txt limpo' 'OK'; SendAck $cmd $true }
                catch { wLog "Erro ao limpar cookies: $_" 'ERROR'; SendAck $cmd $false "$_" }
            }
            'restart_pc' {
                wLog 'Reiniciando PC...' 'WARN'
                try { FecharTudo } catch { wLog "Aviso ao fechar: $_" 'WARN' }
                Start-Sleep 2
                try { & cmd.exe /c "shutdown /r /t 3 /f" 2>&1 | Out-Null; wLog 'Reinicio enviado.' 'OK'; SendAck $cmd $true }
                catch { wLog "Erro ao reiniciar: $_" 'ERROR'; SendAck $cmd $false "$_" }
            }
            'pause'  { $script:Paused = $true;  $host.UI.RawUI.WindowTitle = 'Monitor [PAUSADO]'; wLog 'Monitor PAUSADO.' 'WARN'; SendAck $cmd $true }
            'resume' { $script:Paused = $false; $host.UI.RawUI.WindowTitle = 'Monitor';            wLog 'Monitor RETOMADO.' 'OK';  SendAck $cmd $true }
            'set_volt_login' {
                $cfgPath = "$env:USERPROFILE\Desktop\VoltBlack\volt_config.json"
                if ($data -and $data.username -and $data.password) {
                    try {
                        if (-not (Test-Path $cfgPath)) { wLog 'volt_config.json nao encontrado' 'ERROR'; SendAck $cmd $false 'arquivo nao encontrado'; continue }
                        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
                        $cfg | Add-Member -MemberType NoteProperty -Name 'username' -Value $data.username -Force
                        $cfg | Add-Member -MemberType NoteProperty -Name 'password' -Value $data.password -Force
                        $cfg | ConvertTo-Json -Depth 10 | Set-Content -Path $cfgPath -Encoding UTF8
                        $v = Get-Content $cfgPath -Raw | ConvertFrom-Json
                        if ($v.username -eq $data.username -and $v.password -eq $data.password) { wLog "Login Volt: $($data.username)" 'OK'; SendAck $cmd $true }
                        else { wLog 'Falha na verificacao do login' 'ERROR'; SendAck $cmd $false 'verificacao falhou' }
                    } catch { wLog "Erro ao salvar login: $_" 'ERROR'; SendAck $cmd $false "$_" }
                } else { wLog 'set_volt_login: dados invalidos' 'WARN'; SendAck $cmd $false 'dados invalidos' }
            }
            'screenshot' {
                try {
                    Add-Type -AssemblyName System.Windows.Forms,System.Drawing -EA Stop
                    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                    $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
                    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
                    $gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
                    $ms  = New-Object System.IO.MemoryStream
                    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                    $b64 = [Convert]::ToBase64String($ms.ToArray())
                    $gfx.Dispose(); $bmp.Dispose(); $ms.Dispose()
                    $ssBody = @{ image = $b64 } | ConvertTo-Json -Compress
                    Invoke-RestMethod -Uri "$ApiUrl/screenshot/$MachineId" -Method POST -Headers $ApiHeaders -Body $ssBody -ContentType 'application/json' -TimeoutSec 30 -EA Stop | Out-Null
                    wLog 'Screenshot enviado' 'OK'; SendAck $cmd $true
                } catch { wLog "Erro screenshot: $_" 'ERROR'; SendAck $cmd $false "$_" }
            }
            'run_ps' {
                if ($data) {
                    try {
                        $result = Invoke-Expression $data 2>&1
                        $out = if ($result) { ($result | Out-String).Trim() } else { '(sem saida)' }
                        wLog "run_ps OK: $($out.Substring(0, [Math]::Min(200, $out.Length)))" 'OK'; SendAck $cmd $true
                    } catch { wLog "run_ps ERRO: $_" 'ERROR'; SendAck $cmd $false "$_" }
                } else { wLog 'run_ps: script vazio' 'WARN'; SendAck $cmd $false 'script vazio' }
            }
            default { wLog "Comando desconhecido: $cmd" 'WARN'; SendAck $cmd $false 'desconhecido' }
        }
    }
}


# ── Init ─────────────────────────────────────────────────────────
Clear-Host
Write-Host ''
Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
Write-Host '  |   MONITOR  -  VoltPro + FarmSync Watchdog + Roblox      |' -ForegroundColor DarkCyan
Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Volt     : ' -NoNewline -ForegroundColor DarkGray; Write-Host $VoltExe      -ForegroundColor Cyan
Write-Host '  FarmSync : ' -NoNewline -ForegroundColor DarkGray; Write-Host $FarmSyncExe  -ForegroundColor Cyan
Write-Host '  ID       : ' -NoNewline -ForegroundColor DarkGray; Write-Host $MachineId    -ForegroundColor Cyan
Write-Host ''
Separador; Write-Host ''
wLog 'Monitor iniciado' 'OK'
$host.UI.RawUI.WindowTitle = 'Monitor'
OrganizarJanela

# ── Loop ─────────────────────────────────────────────────────────
$tick = 0  # mantido por compatibilidade
while ($true) {
    if (Test-Path $StopFile) {
        Write-Host ''; Separador
        wLog 'Stop-file detectado. Encerrando.' 'WARN'
        Remove-Item $StopFile -Force; break
    }

    DrainCommands

    # Timers baseados em tempo real (tick nao representa mais segundos com long-poll)
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (($now - $script:LastReport)  -ge 5)  { ReportMetrics;   $script:LastReport  = $now }
    if (($now - $script:LastNotice)  -ge 5)  { CheckNotice;     $script:LastNotice  = $now }
    if (($now - $script:LastUpdate)  -ge 60) { CheckUpdate;     $script:LastUpdate  = $now }
    if (($now - $script:LastOrg)     -ge 60) { OrganizarJanela; $script:LastOrg     = $now }
    if (($now - $script:LastMin)      -ge 2)  { MinimizarRoblox;   $script:LastMin      = $now }
    CheckAndKillErrors

    if (-not $script:Paused) {
        if (($now - $script:LastVoltCheck) -ge 10) {
            $script:LastVoltCheck = $now
            $voltProc = GetVoltProc
            if (-not $voltProc) {
                wLog 'VoltPro nao encontrado. Iniciando...' 'WARN'
                Start-Process $VoltExe
                Start-Sleep 10
                OrganizarJanela
            }
        }
    }
}
