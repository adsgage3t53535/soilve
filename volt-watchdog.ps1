# ================================================================
#  ROBLOX ERROR KILLER - Com organizador de janelas e detector Volt
# ================================================================

$host.UI.RawUI.WindowTitle = 'Roblox Error Killer'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class WinAPIR {
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
$LogFile     = $env:TEMP + '\roblox-error-killer.log'
$StopFile    = $env:TEMP + '\roblox-killer.stop'
$AppTitle    = 'Volt'
$WinW        = 900
$WinH        = 500
$CmdW        = 700
$CmdH        = 500
$ErrorTitles = @('Error', 'Roblox Error', 'Crash', 'Disconnected', 'An error occurred', 'Notice')

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
}

function Separador { Write-Host ('  ' + ('─' * 60)) -ForegroundColor DarkGray }

# ── Organizar janelas ───────────────────────────────────────────
function OrganizarJanela {
    $sw = [WinAPIR]::GetSystemMetrics(0)
    $sh = [WinAPIR]::GetSystemMetrics(1)

    $hwndVolt = [WinAPIR]::FindWindow([NullString]::Value, $AppTitle)
    if ($hwndVolt -ne [IntPtr]::Zero) {
        $xV = $sw - $WinW - 10
        $yV = $sh - $WinH - 50
        [WinAPIR]::SetWindowPos($hwndVolt, [IntPtr]::Zero, $xV, $yV, $WinW, $WinH, 0x0040) | Out-Null
        wLog "Volt  -> $xV,$yV  $($WinW)x$($WinH)" 'DEBUG'
    }

    $hwndWebRB = [WinAPIR]::FindWindow([NullString]::Value, 'WebRB')
    if ($hwndWebRB -eq [IntPtr]::Zero) {
        $pr = Get-Process -Name 'WebRB' -EA SilentlyContinue
        if ($pr) { $hwndWebRB = $pr.MainWindowHandle }
    }
    if ($hwndWebRB -ne [IntPtr]::Zero) {
        $xR = $sw - $WinW - 10
        $yR = $sh - $WinH - 50 - $WinH - 10
        [WinAPIR]::SetWindowPos($hwndWebRB, [IntPtr]::Zero, $xR, $yR, $WinW, $WinH, 0x0040) | Out-Null
        wLog "WebRB -> $xR,$yR  $($WinW)x$($WinH)" 'DEBUG'
    }

    $hwndCmd = [WinAPIR]::GetConsoleWindow()
    if ($hwndCmd -ne [IntPtr]::Zero) {
        $xC = $sw - $WinW - 10 - $CmdW - 10
        $yC = $sh - $CmdH - 50
        [WinAPIR]::SetWindowPos($hwndCmd, [IntPtr]::Zero, $xC, $yC, $CmdW, $CmdH, 0x0040) | Out-Null
        wLog "CMD   -> $xC,$yC  $($CmdW)x$($CmdH)" 'DEBUG'
    }
}

# ── Detector de cor do Volt ─────────────────────────────────────
function CheckVoltScreen {
    $hwnd = [WinAPIR]::FindWindow([NullString]::Value, $AppTitle)
    if ($hwnd -eq [IntPtr]::Zero) { return 'none' }
    $r = New-Object WinAPIR+RECT
    [WinAPIR]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    $w = $r.R - $r.L; $h = $r.B - $r.T
    if ($w -le 0 -or $h -le 0) { return 'none' }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [WinAPIR]::PrintWindow($hwnd, $hdc, 2) | Out-Null
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
    wLog "Volt  branca: $($wpct)%   preta: $($bpct)%" 'DEBUG'
    if ($wpct -gt 40) { return 'white' }
    if ($bpct -gt 98) { return 'black' }
    return 'ok'
}

# ── Fechar erros Roblox ─────────────────────────────────────────
function CheckAndKillErrors {
    foreach ($t in $ErrorTitles) {
        $r = taskkill /F /FI ('WINDOWTITLE eq ' + $t) /IM RobloxPlayerBeta.exe 2>&1
        if ($r -match 'SUCCESS') {
            wLog "Erro Roblox fechado: $t" 'OK'
        }
    }
}

# ── Inicializacao ───────────────────────────────────────────────
Clear-Host
Write-Host ''
Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
Write-Host '  |       ROBLOX ERROR KILLER  -  Monitor Ativo              |' -ForegroundColor DarkCyan
Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Log  : ' -NoNewline -ForegroundColor DarkGray; Write-Host $LogFile -ForegroundColor Cyan
Write-Host ''
Separador
Write-Host ''
wLog 'Iniciado' 'OK'
OrganizarJanela

# ── Loop principal ──────────────────────────────────────────────
$tick = 0
while ($true) {

    if (Test-Path $StopFile) {
        Separador
        wLog 'Stop-file detectado. Encerrando.' 'WARN'
        Remove-Item $StopFile -Force
        break
    }

    # Checa erros Roblox a cada 1 segundo
    CheckAndKillErrors

    # Checa tela do Volt a cada 10s
    if ($tick % 10 -eq 0) {
        $screen = CheckVoltScreen
        if ($screen -eq 'white')     { wLog 'Volt com tela branca!' 'WARN'  }
        elseif ($screen -eq 'black') { wLog 'Volt com tela preta!'  'ERROR' }
    }

    # Organiza janelas a cada 60s
    if ($tick % 60 -eq 0 -and $tick -gt 0) { OrganizarJanela }

    $tick++
    Start-Sleep 1
}
