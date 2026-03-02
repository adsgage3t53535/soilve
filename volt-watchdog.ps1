# ================================================================
#  VOLT WATCHDOG - Monitor automatico
# ================================================================

$host.UI.RawUI.WindowTitle = 'Volt Watchdog'
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
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
'@ -ErrorAction SilentlyContinue

# ── Configuracoes ───────────────────────────────────────────────
$VoltExe  = $env:LOCALAPPDATA + '\Volt\tauri-app.exe'
$AppTitle = 'Volt'
$LogFile  = $env:TEMP + '\volt-watchdog.log'
$StopFile = $env:TEMP + '\watchdog.stop'
$WinW     = 900
$WinH     = 500
$CmdW     = 700
$CmdH     = 500

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

function Separador { Write-Host ('  ' + ('─' * 60)) -ForegroundColor DarkGray }

# ── Organizar janelas ───────────────────────────────────────────
function OrganizarJanela {
    Start-Sleep 2
    $sw = [WinAPI]::GetSystemMetrics(0)
    $sh = [WinAPI]::GetSystemMetrics(1)

    $hwndVolt = [WinAPI]::FindWindow([NullString]::Value, $AppTitle)
    if ($hwndVolt -ne [IntPtr]::Zero) {
        $xV = $sw - $WinW - 10
        $yV = $sh - $WinH - 50
        [WinAPI]::SetWindowPos($hwndVolt, [IntPtr]::Zero, $xV, $yV, $WinW, $WinH, 0x0040) | Out-Null
        wLog "Volt  -> $xV,$yV  $($WinW)x$($WinH)" 'DEBUG'
    } else { wLog 'Janela Volt nao encontrada' 'WARN' }

    $hwndWebRB = [WinAPI]::FindWindow([NullString]::Value, 'WebRB')
    if ($hwndWebRB -eq [IntPtr]::Zero) {
        $pr = Get-Process -Name 'WebRB' -EA SilentlyContinue
        if ($pr) { $hwndWebRB = $pr.MainWindowHandle }
    }
    if ($hwndWebRB -ne [IntPtr]::Zero) {
        $xR = $sw - $WinW - 10
        $yR = $sh - $WinH - 50 - $WinH - 10
        [WinAPI]::SetWindowPos($hwndWebRB, [IntPtr]::Zero, $xR, $yR, $WinW, $WinH, 0x0040) | Out-Null
        wLog "WebRB -> $xR,$yR  $($WinW)x$($WinH)" 'DEBUG'
    } else { wLog 'Janela WebRB nao encontrada' 'WARN' }

    $hwndCmd = [WinAPI]::GetConsoleWindow()
    if ($hwndCmd -ne [IntPtr]::Zero) {
        $xC = $sw - $WinW - 10 - $CmdW - 10
        $yC = $sh - $CmdH - 50
        [WinAPI]::SetWindowPos($hwndCmd, [IntPtr]::Zero, $xC, $yC, $CmdW, $CmdH, 0x0040) | Out-Null
        wLog "CMD   -> $xC,$yC  $($CmdW)x$($CmdH)" 'DEBUG'
    }
}

# ── Analise de tela ─────────────────────────────────────────────
function CheckScreen {
    $hwnd = [WinAPI]::FindWindow([NullString]::Value, $AppTitle)
    if ($hwnd -eq [IntPtr]::Zero) { return 'none' }
    $r = New-Object WinAPI+RECT
    [WinAPI]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    $w = $r.R - $r.L; $h = $r.B - $r.T
    if ($w -le 0 -or $h -le 0) { return 'none' }
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
    if ($sampled -eq 0) { return 'none' }
    $wpct = [math]::Round(($white / $sampled) * 100, 1)
    $bpct = [math]::Round(($black / $sampled) * 100, 1)
    wLog "Tela  branca: $($wpct)%   preta: $($bpct)%" 'DEBUG'
    if ($wpct -gt 40) { return 'white' }
    if ($bpct -gt 98) { return 'black' }
    return 'ok'
}

# ── Enviar F5 ───────────────────────────────────────────────────
function SendF5 {
    $tries  = 0
    $shell  = New-Object -ComObject WScript.Shell
    $screen = CheckScreen
    while ($screen -eq 'white' -and $tries -lt 10) {
        wLog "Enviando F5... tentativa $($tries+1)/10" 'WARN'
        $shell.AppActivate($AppTitle) | Out-Null
        $shell.SendKeys('{F5}')
        $tries++
        Start-Sleep 2
        $screen = CheckScreen
    }
    if ($tries -gt 0 -and $tries -lt 10) {
        wLog 'Volt recuperado com F5!' 'OK'
    } elseif ($tries -ge 10) {
        wLog 'Volt NAO recuperou apos 10x F5!' 'ERROR'
    }
}

# ── Reiniciar Volt ──────────────────────────────────────────────
function ReiniciarVolt {
    Separador
    wLog 'Encerrando Volt...' 'WARN'
    Get-Process | Where-Object { $_.MainWindowTitle -eq $AppTitle -or $_.ProcessName -eq 'tauri-app' } | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 3
    wLog 'Reiniciando Volt...' 'WARN'
    Start-Process $VoltExe
    Start-Sleep 8
    OrganizarJanela
    Separador
}

# ── Inicializacao ───────────────────────────────────────────────
Clear-Host
Write-Host ''
Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
Write-Host '  |          VOLT WATCHDOG  -  Monitor Ativo                 |' -ForegroundColor DarkCyan
Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Volt : ' -NoNewline -ForegroundColor DarkGray; Write-Host $VoltExe -ForegroundColor Cyan
Write-Host '  Log  : ' -NoNewline -ForegroundColor DarkGray; Write-Host $LogFile -ForegroundColor Cyan
Write-Host ''
Separador
Write-Host ''
wLog 'Watchdog iniciado' 'OK'
OrganizarJanela

# ── Loop principal ──────────────────────────────────────────────
$tick = 0
while ($true) {

    if (Test-Path $StopFile) {
        Write-Host ''; Separador
        wLog 'Stop-file detectado. Encerrando.' 'WARN'
        Remove-Item $StopFile -Force
        break
    }

    $voltProc = Get-Process -Name 'tauri-app' -EA SilentlyContinue
    if (-not $voltProc) {
        wLog 'tauri-app.exe nao encontrado. Iniciando Volt...' 'WARN'
        Start-Process $VoltExe
        Start-Sleep 10
        OrganizarJanela
        $tick++
        Start-Sleep 10
        continue
    }

    $webviews = Get-Process msedgewebview2 -EA SilentlyContinue
    if (-not $webviews) {
        wLog 'WebView2 ausente! Reiniciando Volt...' 'ERROR'
        ReiniciarVolt
    } else {
        $biggest = $webviews | Sort-Object WorkingSet -Descending | Select-Object -First 1
        $mb      = [math]::Round($biggest.WorkingSet / 1MB, 1)
        wLog "WebView2 PID $($biggest.Id)   RAM: $($mb) MB" 'DEBUG'

        if ($tick % 2 -eq 0) {
            $screen = CheckScreen
            if ($screen -eq 'white')     { wLog 'Tela branca detectada. Mandando F5...'     'WARN';  SendF5        }
            elseif ($screen -eq 'black') { wLog 'Tela preta detectada. Reiniciando Volt...' 'ERROR'; ReiniciarVolt }
        }
    }

    if ($tick % 180 -eq 0 -and $tick -gt 0) {
        wLog 'Reinicio programado (30 minutos).' 'WARN'
        ReiniciarVolt
    }

    if ($tick % 6 -eq 0) { OrganizarJanela }
    $tick++
    Start-Sleep 10
}
