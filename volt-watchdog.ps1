# ================================================================
#  MONITOR - Volt Watchdog + Roblox Error Killer
# ================================================================

$host.UI.RawUI.WindowTitle = 'Monitor'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string a, string b);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, ref RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr i, int x, int y, int w, int ht, uint f);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc p, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr wp, IntPtr lp2);
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr lp);
}
'@ -ErrorAction SilentlyContinue

# ── Configuracoes ───────────────────────────────────────────────
$VoltExe     = $env:LOCALAPPDATA + '\Volt\tauri-app.exe'
$AppTitle    = 'Volt'
$LogFile     = $env:TEMP + '\monitor.log'
$StopFile    = $env:TEMP + '\monitor.stop'
$WinW        = 900
$WinH        = 500
$CmdW        = 700
$CmdH        = 500
$ApiUrl      = 'https://vps-production-2bd3.up.railway.app'
$MachineId   = $env:COMPUTERNAME
$WebRBDir    = "$env:USERPROFILE\Desktop\WebRB\YummyWebPlayer"
$WebRBExe    = 'webrb.exe'
$ErrorTitles = @('Error', 'Roblox Error', 'Crash', 'Disconnected', 'An error occurred', 'Notice')

# Estado
$script:Paused = $false

# ── Log colorido ────────────────────────────────────────────────
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
        'DEBUG' { Write-Host $m -ForegroundColor DarkGray }
        default { Write-Host $m -ForegroundColor White }
    }
    Add-Content $LogFile $s -Encoding UTF8
    $lines = Get-Content $LogFile -EA SilentlyContinue
    if ($lines.Count -gt 500) { $lines | Select-Object -Last 250 | Set-Content $LogFile -Encoding UTF8 }
}

function Separador { Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray }

# ── Organizar janelas ───────────────────────────────────────────
function OrganizarJanela {
    $sw = [WinAPI]::GetSystemMetrics(0)
    $sh = [WinAPI]::GetSystemMetrics(1)
    $hwndVolt = [WinAPI]::FindWindow([NullString]::Value, $AppTitle)
    if ($hwndVolt -ne [IntPtr]::Zero) {
        $xV = $sw - $WinW - 10; $yV = $sh - $WinH - 50
        [WinAPI]::SetWindowPos($hwndVolt, [IntPtr]::Zero, $xV, $yV, $WinW, $WinH, 0x0040) | Out-Null
    }
    $hwndWebRB = [WinAPI]::FindWindow([NullString]::Value, 'WebRB')
    if ($hwndWebRB -eq [IntPtr]::Zero) {
        $pr = Get-Process -Name 'WebRB' -EA SilentlyContinue
        if ($pr) { $hwndWebRB = $pr.MainWindowHandle }
    }
    if ($hwndWebRB -ne [IntPtr]::Zero) {
        $xR = $sw - $WinW - 10; $yR = $sh - $WinH - 50 - $WinH - 10
        [WinAPI]::SetWindowPos($hwndWebRB, [IntPtr]::Zero, $xR, $yR, $WinW, $WinH, 0x0040) | Out-Null
    }
    $hwndCmd = [WinAPI]::GetConsoleWindow()
    if ($hwndCmd -ne [IntPtr]::Zero) {
        $xC = $sw - $WinW - 10 - $CmdW - 10; $yC = $sh - $CmdH - 50
        [WinAPI]::SetWindowPos($hwndCmd, [IntPtr]::Zero, $xC, $yC, $CmdW, $CmdH, 0x0040) | Out-Null
    }
}

# ── Helper: % branca e preta de qualquer janela ─────────────────
function GetScreenPcts($hwnd) {
    $r = New-Object WinAPI+RECT
    [WinAPI]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    $w = $r.R - $r.L; $h = $r.B - $r.T
    if ($w -le 0 -or $h -le 0) { return $null }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [WinAPI]::PrintWindow($hwnd, $hdc, 2) | Out-Null
    $g.ReleaseHdc($hdc); $g.Dispose()
    $white = 0; $black = 0
    for ($x = 0; $x -lt $w; $x += 5) {
        for ($y = 0; $y -lt $h; $y += 5) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -gt 240 -and $c.G -gt 240 -and $c.B -gt 240) { $white++ }
            elseif ($c.R -lt 15 -and $c.G -lt 15 -and $c.B -lt 15) { $black++ }
        }
    }
    $bmp.Dispose()
    $sampled = [math]::Floor($w / 5) * [math]::Floor($h / 5)
    if ($sampled -eq 0) { return $null }
    return @{
        White = [math]::Round(($white / $sampled) * 100, 1)
        Black = [math]::Round(($black / $sampled) * 100, 1)
    }
}

# ── Analise de tela do Volt ─────────────────────────────────────
function CheckVoltScreen {
    $hwnd = [WinAPI]::FindWindow([NullString]::Value, $AppTitle)
    if ($hwnd -eq [IntPtr]::Zero) { return 'none' }
    $pcts = GetScreenPcts $hwnd
    if (-not $pcts) { return 'none' }
    if ($pcts.White -gt 40) { return 'white' }
    if ($pcts.Black -gt 98) { return 'black' }
    return 'ok'
}

# ── Reiniciar Volt ──────────────────────────────────────────────
function ReiniciarVolt {
    Separador
    wLog 'Encerrando Volt...' 'WARN'
    Get-Process | Where-Object { $_.MainWindowTitle -eq $AppTitle -or $_.ProcessName -eq 'tauri-app' } | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 3
    wLog 'Iniciando Volt...' 'WARN'
    Start-Process $VoltExe
    Start-Sleep 8
    OrganizarJanela
    Separador
}

# ── Fechar Volt ─────────────────────────────────────────────────
function FecharVolt {
    wLog 'Fechando Volt...' 'WARN'
    Get-Process | Where-Object { $_.MainWindowTitle -eq $AppTitle -or $_.ProcessName -eq 'tauri-app' } | Stop-Process -Force -EA SilentlyContinue
}

# ── Abrir Volt ──────────────────────────────────────────────────
function AbrirVolt {
    wLog 'Abrindo Volt...' 'OK'
    Start-Process $VoltExe
    Start-Sleep 8
    OrganizarJanela
}

# ── Abrir WebRB ─────────────────────────────────────────────────
function AbrirWebRB {
    wLog 'Abrindo WebRB...' 'OK'
    Start-Process 'cmd.exe' -ArgumentList "/c cd /d `"$WebRBDir`" & start `"`" `"$WebRBExe`""
}

# ── Fechar WebRB ────────────────────────────────────────────────
function FecharWebRB {
    wLog 'Fechando WebRB...' 'WARN'
    Get-Process -Name 'WebRB' -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    Get-Process -Name 'webrb' -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
}

# ── Definir autoexec do Volt ─────────────────────────────────────
function SetAutoexec($content) {
    $dir = $env:LOCALAPPDATA + '\Volt\autoexec'
    try {
        if (Test-Path $dir) {
            Get-ChildItem $dir -File | Remove-Item -Force -EA SilentlyContinue
        } else {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        [System.IO.File]::WriteAllText("$dir\Script.txt", $content, [System.Text.Encoding]::UTF8)
        wLog "Autoexec definido ($($content.Length) chars)" 'OK'
    } catch {
        wLog "Erro ao definir autoexec: $_" 'ERROR'
    }
}

# ── Fechar erros Roblox (EnumWindows) ───────────────────────────
function CheckAndKillErrors {
    $robloxPids = (Get-Process -Name 'RobloxPlayerBeta' -EA SilentlyContinue).Id
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
                        wLog "Roblox janela fechada: '$title'" 'OK'
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

# ── Auto-update (compara hash direto no GitHub) ───────────
$GithubUrl      = 'https://raw.githubusercontent.com/adsgage3t53535/soilve/refs/heads/main/volt-watchdog.ps1'
$script:CurHash = $null

function CheckUpdate {
    try {
        $raw   = (Invoke-WebRequest -Uri $GithubUrl -UseBasicParsing -TimeoutSec 10 -EA Stop).Content
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
        $hash  = ([System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash($bytes))).Replace('-','')
        if ($null -eq $script:CurHash) {
            $script:CurHash = $hash
        } elseif ($hash -ne $script:CurHash) {
            wLog 'Nova versao detectada no GitHub. Reiniciando...' 'WARN'
            Start-Sleep 2
            Start-Process 'cmd.exe' -ArgumentList "/c powershell -ExecutionPolicy Bypass -Command `"iex (irm '$GithubUrl')`""
            exit
        }
    } catch { }
}
            $script:CurVer = $r.version
        }
    } catch { }
}

# ── Poll do servidor Railway ─────────────────────────────────────
function PollApi {
    try {
        $r = Invoke-RestMethod -Uri "$ApiUrl/poll/$MachineId" -Method GET -TimeoutSec 5 -EA Stop
        foreach ($item in $r.commands) {
            # suporta tanto string simples quanto objeto {cmd, data}
            if ($item -is [string]) { $cmd = $item; $data = $null }
            else                    { $cmd = $item.cmd; $data = $item.data }

            switch ($cmd) {
                'open_webrb'       { AbrirWebRB }
                'close_webrb'      { FecharWebRB }
                'open_volt'        { AbrirVolt }
                'close_volt'       { FecharVolt }
                'restart_volt'     { wLog 'API: reiniciando Volt...' 'OK'; ReiniciarVolt }
                'close_all_roblox' { FecharTodosRoblox }
                'restart_all'      { wLog 'API: reiniciando tudo...' 'OK'; ReiniciarTudo }
                'organize_windows' { wLog 'API: organizando janelas...' 'OK'; OrganizarJanela }
                'set_autoexec'     {
                    if ($data) { SetAutoexec $data }
                    else { wLog 'set_autoexec: conteudo vazio' 'WARN' }
                }
                'restart_pc'       {
                    wLog 'API: reiniciando PC em 5s...' 'WARN'
                    FecharTudo
                    Start-Sleep 5
                    Restart-Computer -Force
                }
                'pause' {
                    $script:Paused = $true
                    $host.UI.RawUI.WindowTitle = 'Monitor [PAUSADO]'
                    wLog 'Monitor PAUSADO por comando API.' 'WARN'
                }
                'resume' {
                    $script:Paused = $false
                    $host.UI.RawUI.WindowTitle = 'Monitor'
                    wLog 'Monitor RETOMADO por comando API.' 'OK'
                }
                default { wLog "API: comando desconhecido: $cmd" 'WARN' }
            }
        }
    } catch { }
}

# ── Inicializacao ───────────────────────────────────────────────
Clear-Host
Write-Host ''
Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
Write-Host '  |         MONITOR  -  Volt Watchdog + Roblox Killer        |' -ForegroundColor DarkCyan
Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Volt : ' -NoNewline -ForegroundColor DarkGray; Write-Host $VoltExe   -ForegroundColor Cyan
Write-Host '  Log  : ' -NoNewline -ForegroundColor DarkGray; Write-Host $LogFile   -ForegroundColor Cyan
Write-Host '  API  : ' -NoNewline -ForegroundColor DarkGray; Write-Host $ApiUrl    -ForegroundColor Cyan
Write-Host '  ID   : ' -NoNewline -ForegroundColor DarkGray; Write-Host $MachineId -ForegroundColor Cyan
Write-Host ''
Separador
Write-Host ''
wLog 'Monitor iniciado' 'OK'
OrganizarJanela

# ── Loop principal (tick = 1s) ───────────────────────────────────
$tick = 0
while ($true) {

    if (Test-Path $StopFile) {
        Write-Host ''; Separador
        wLog 'Stop-file detectado. Encerrando.' 'WARN'
        Remove-Item $StopFile -Force; break
    }

    # Sempre: poll API (aceita comandos manuais mesmo pausado)
    PollApi

    # Auto-update: verifica nova versao a cada 60s
    if ($tick % 60 -eq 0) { CheckUpdate }

    # Sempre: fecha erros Roblox instantaneamente
    CheckAndKillErrors

    # Automatico apenas se nao pausado
    if (-not $script:Paused) {

        # Volt: checks a cada 10s
        if ($tick % 10 -eq 0) {
            $voltProc = Get-Process -Name 'tauri-app' -EA SilentlyContinue
            if (-not $voltProc) {
                wLog 'tauri-app.exe nao encontrado. Iniciando Volt...' 'WARN'
                Start-Process $VoltExe
                Start-Sleep 10
                OrganizarJanela
                $tick++
                Start-Sleep 1
                continue
            }
            $webviews = Get-Process msedgewebview2 -EA SilentlyContinue
            if (-not $webviews) {
                wLog 'WebView2 ausente! Reiniciando Volt...' 'ERROR'
                ReiniciarVolt
            }
        }

        # Volt: checa tela branca/preta a cada 20s
        if ($tick % 20 -eq 0) {
            $screen = CheckVoltScreen
            if ($screen -eq 'white')     { wLog 'Volt tela branca. Reiniciando...' 'WARN';  ReiniciarVolt }
            elseif ($screen -eq 'black') { wLog 'Volt tela preta. Reiniciando...'  'ERROR'; ReiniciarVolt }
        }

        # Organiza janelas a cada 60s
        if ($tick % 60 -eq 0 -and $tick -gt 0) { OrganizarJanela }
    }

    $tick++
    Start-Sleep 1
}
