# ================================================================
#  MONITOR - VoltPro Watchdog + Roblox Error Killer
# ================================================================
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
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr lp);
}
'@ -ErrorAction SilentlyContinue

# ── Configuracoes ────────────────────────────────────────────────
$VoltExe     = "$env:USERPROFILE\Desktop\VoltBlack\VoltPro_6.5.exe"
$VoltProc    = [System.IO.Path]::GetFileNameWithoutExtension($VoltExe)

# Helper: encontra processo do VoltPro pelo caminho do exe
function GetVoltProc {
    Get-Process -EA SilentlyContinue | Where-Object {
        try { $_.Path -eq $VoltExe } catch { $false }
    } | Select-Object -First 1
}
$LogFile     = $env:TEMP + '\monitor.log'
$StopFile    = $env:TEMP + '\monitor.stop'
$WinW        = 900; $WinH = 500
$CmdW        = 700; $CmdH = 500
$ApiUrl      = 'https://vps-production-2bd3.up.railway.app'
$GithubUrl   = 'https://raw.githubusercontent.com/adsgage3t53535/soilve/refs/heads/main/volt-watchdog.ps1'
$WebRBDir    = "$env:USERPROFILE\Desktop\WebRB\YummyWebPlayer"
$WebRBExe    = 'webrb.exe'
$ErrorTitles = @('Error','Roblox Error','Crash','Disconnected','An error occurred','Notice')

# MachineId via auth.json (Note field)
$_authFile = "$WebRBDir\auth.json"
$MachineId = try {
    $j = Get-Content $_authFile -Raw -EA Stop | ConvertFrom-Json
    if ($j.Note) { $j.Note } else { $env:COMPUTERNAME }
} catch { $env:COMPUTERNAME }

$script:Paused  = $true   # inicia pausado — despause pelo painel
$script:CurHash = $null

# ── Log ─────────────────────────────────────────────────────────
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
}

# ── VoltPro ──────────────────────────────────────────────────────
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
    # Kill by window title containing Yummy
    Get-Process -EA SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*Yummy*' -or $_.MainWindowTitle -like '*WebRB*' } | Stop-Process -Force -EA SilentlyContinue
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
}

# ── Reiniciar tudo ───────────────────────────────────────────────
function ReiniciarTudo {
    Separador
    wLog 'REINICIANDO TUDO...' 'WARN'
    FecharTodosRoblox
    FecharVolt
    FecharWebRB
    # Limpa workspace do Volt
    $wsDir = $env:LOCALAPPDATA + '\Volt\workspace'
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
    $dir = $env:LOCALAPPDATA + '\Volt\autoexec'
    try {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Get-ChildItem $dir -Filter '*.txt' | Remove-Item -Force -EA SilentlyContinue
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

# ── Auto-update ──────────────────────────────────────────────────
function CheckUpdate {
    try {
        $raw   = (Invoke-WebRequest -Uri $GithubUrl -UseBasicParsing -TimeoutSec 10 -EA Stop).Content
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
        $hash  = ([System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash($bytes))).Replace('-','')
        if ($null -eq $script:CurHash) {
            $script:CurHash = $hash
        } elseif ($hash -ne $script:CurHash) {
            wLog 'Nova versao detectada. Reiniciando...' 'WARN'
            Start-Sleep 2
            $c = 'iex (irm ''' + $GithubUrl + ''')'
            Start-Process 'powershell.exe' -ArgumentList "-ExecutionPolicy Bypass -Command $c"
            exit
        }
    } catch { }
}

# ── Reportar metricas ao servidor ───────────────────────────────
function ReportMetrics {
    try {
        $roblox = @(Get-Process -Name 'RobloxPlayerBeta','RobloxPlayer' -EA SilentlyContinue).Count
        $volt   = if (GetVoltProc) { 1 } else { 0 }
        $webrb  = if (Get-Process -Name 'webrb','WebRB' -EA SilentlyContinue | Select-Object -First 1) { 1 } else { 0 }
        $body   = '{"roblox":' + $roblox + ',"volt":' + $volt + ',"webrb":' + $webrb + '}'
        Invoke-RestMethod -Uri "$ApiUrl/report/$MachineId" -Method POST -Body $body -ContentType 'application/json' -TimeoutSec 5 -EA Stop | Out-Null
    } catch { }
}

# ── Poll API ─────────────────────────────────────────────────────
function PollApi {
    try {
        $r = Invoke-RestMethod -Uri "$ApiUrl/poll/$MachineId" -Method GET -TimeoutSec 5 -EA Stop
        foreach ($item in $r.commands) {
            if ($item -is [string]) { $cmd = $item; $data = $null }
            else                    { $cmd = $item.cmd; $data = $item.data }
            switch ($cmd) {
                'open_volt'        { AbrirVolt }
                'close_volt'       { FecharVolt }
                'restart_volt'     { wLog 'Reiniciando VoltPro...' 'OK'; ReiniciarVolt }
                'open_webrb'       { AbrirWebRB }
                'close_webrb'      { FecharWebRB }
                'close_all_roblox' { FecharTodosRoblox }
                'restart_all'      { ReiniciarTudo }
                'organize_windows' { OrganizarJanela }
                'restart_cmd'      {
                    wLog 'Reiniciando CMD...' 'WARN'
                    Start-Sleep 1
                    $c = 'iex (irm ''' + $GithubUrl + ''')'
                    Start-Process 'powershell.exe' -ArgumentList "-ExecutionPolicy Bypass -Command $c"
                    exit
                }
                'set_autoexec'     {
                    if ($data) { SetAutoexec $data }
                    else { wLog 'set_autoexec: URL vazia' 'WARN' }
                }
                'restart_pc'       {
                    wLog 'Reiniciando PC em 5s...' 'WARN'
                    FecharTudo; Start-Sleep 5; Restart-Computer -Force
                }
                'pause' {
                    $script:Paused = $true
                    $host.UI.RawUI.WindowTitle = 'Monitor [PAUSADO]'
                    wLog 'Monitor PAUSADO.' 'WARN'
                }
                'resume' {
                    $script:Paused = $false
                    $host.UI.RawUI.WindowTitle = 'Monitor'
                    wLog 'Monitor RETOMADO.' 'OK'
                }
                default { wLog "Comando desconhecido: $cmd" 'WARN' }
            }
        }
    } catch { }
}

# ── Init ─────────────────────────────────────────────────────────
Clear-Host
Write-Host ''
Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
Write-Host '  |        MONITOR  -  VoltPro Watchdog + Roblox Killer      |' -ForegroundColor DarkCyan
Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Volt : ' -NoNewline -ForegroundColor DarkGray; Write-Host $VoltExe   -ForegroundColor Cyan
Write-Host '  API  : ' -NoNewline -ForegroundColor DarkGray; Write-Host $ApiUrl    -ForegroundColor Cyan
Write-Host '  ID   : ' -NoNewline -ForegroundColor DarkGray; Write-Host $MachineId -ForegroundColor Cyan
Write-Host ''
Separador; Write-Host ''
wLog 'Monitor iniciado [PAUSADO - despause pelo painel]' 'WARN'
$host.UI.RawUI.WindowTitle = 'Monitor [PAUSADO]'
OrganizarJanela

# ── Loop ─────────────────────────────────────────────────────────
$tick = 0
while ($true) {
    if (Test-Path $StopFile) {
        Write-Host ''; Separador
        wLog 'Stop-file detectado. Encerrando.' 'WARN'
        Remove-Item $StopFile -Force; break
    }

    PollApi
    if ($tick % 5  -eq 0) { ReportMetrics }
    if ($tick % 60 -eq 0) { CheckUpdate }
    CheckAndKillErrors

    if (-not $script:Paused) {
        if ($tick % 10 -eq 0) {
            $voltProc = GetVoltProc
            if (-not $voltProc) {
                wLog 'VoltPro nao encontrado. Iniciando...' 'WARN'
                Start-Process $VoltExe
                Start-Sleep 10
                OrganizarJanela
                $tick++; Start-Sleep 1; continue
            }
        }
        if ($tick % 60 -eq 0 -and $tick -gt 0) { OrganizarJanela }
    }

    $tick++
    Start-Sleep 1
}
