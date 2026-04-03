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
$VoltExe     = "$env:USERPROFILE\Desktop\VoltBlack\VoltPro_6.6.exe"
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
$ApiKey      = 'GobrinNoti'
$ApiHeaders  = @{ 'X-Api-Key' = $ApiKey }
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

$script:Paused  = $false
$script:CurHash = $null

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
    # buffer para envio ao servidor
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
        # deleta tudo exceto checkyummy.lua
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
        $voltUser = ''
        $cfgPath = "$env:USERPROFILE\Desktop\VoltBlack\volt_config.json"
        if (Test-Path $cfgPath) {
            try { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json; $voltUser = if ($cfg.username) { $cfg.username } else { '' } } catch { }
        }
        # CPU — Get-Counter leva 1s mas roda em job para nao bloquear o loop
        $cpuJob = Start-Job { (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -EA SilentlyContinue).CounterSamples.CookedValue }
        $cpuJob | Wait-Job -Timeout 3 | Out-Null
        $cpuRaw = Receive-Job $cpuJob -EA SilentlyContinue
        Remove-Job $cpuJob -Force -EA SilentlyContinue
        $cpu = if ($cpuRaw) { [Math]::Round([double]$cpuRaw, 1) } else { 0 }
        # RAM — igual ao gerenciador de tarefas: Em uso = Total - Disponivel (standby+livre)
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -EA SilentlyContinue
        if ($os) {
            $totalMB    = $os.TotalVisibleMemorySize / 1KB   # converter KB -> MB
            $availMB    = $os.FreePhysicalMemory    / 1KB
            $usedMB     = $totalMB - $availMB
            $ramUsed    = [Math]::Round($usedMB  / 1024, 2)  # GB
            $ramTotal   = [Math]::Round($totalMB / 1024, 2)  # GB
        } else { $ramUsed = 0; $ramTotal = 0 }
        $body = @{ roblox = $roblox; volt = $volt; webrb = $webrb; voltUser = $voltUser; cpu = $cpu; ramUsed = $ramUsed; ramTotal = $ramTotal } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "$ApiUrl/report/$MachineId" -Method POST -Headers $ApiHeaders -Body $body -ContentType 'application/json' -TimeoutSec 5 -EA Stop | Out-Null
        # flush log buffer
        if ($script:LogBuffer.Count -gt 0) {
            $toSend = $script:LogBuffer.ToArray()
            $script:LogBuffer.Clear()
            $logBody = @{ entries = $toSend } | ConvertTo-Json -Compress -Depth 5
            Invoke-RestMethod -Uri "$ApiUrl/devicelog/$MachineId" -Method POST -Headers $ApiHeaders -Body $logBody -ContentType 'application/json' -TimeoutSec 5 -EA SilentlyContinue | Out-Null
        }
    } catch { }
}

# ── ACK helper ───────────────────────────────────────────────────
function SendAck($cmd, $success, $errMsg) {
    try {
        $body = @{ cmd = $cmd; success = $success } | ConvertTo-Json -Compress
        if ($errMsg) { $body = @{ cmd = $cmd; success = $false; error = $errMsg } | ConvertTo-Json -Compress }
        Invoke-RestMethod -Uri "$ApiUrl/ack/$MachineId" -Method POST -Headers $ApiHeaders -Body $body -ContentType 'application/json' -TimeoutSec 4 -EA Stop | Out-Null
    } catch { }
}

$script:PollFailCount = 0

# ── Poll API ─────────────────────────────────────────────────────
function PollApi {
    try {
        $r = Invoke-RestMethod -Uri "$ApiUrl/poll/$MachineId" -Method GET -Headers $ApiHeaders -TimeoutSec 5 -EA Stop
        if ($script:PollFailCount -gt 0) {
            wLog "Conexao restaurada apos $($script:PollFailCount) falhas." 'OK'
            $script:PollFailCount = 0
        }
        foreach ($item in $r.commands) {
            if ($item -is [string]) { $cmd = $item; $data = $null }
            else                    { $cmd = $item.cmd; $data = $item.data }
            switch ($cmd) {
                'open_volt'        { try { AbrirVolt;         SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
                'close_volt'       { try { FecharVolt;        SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
                'restart_volt'     { try { wLog 'Reiniciando VoltPro...' 'OK'; ReiniciarVolt; SendAck $cmd $true } catch { SendAck $cmd $false "$_" } }
                'open_webrb'       { try { AbrirWebRB;        SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
                'close_webrb'      { try { FecharWebRB;       SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
                'close_all_roblox' { try { FecharTodosRoblox; SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
                'restart_all'      { try { ReiniciarTudo;     SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
                'organize_windows' { try { OrganizarJanela;   SendAck $cmd $true  } catch { SendAck $cmd $false "$_" } }
                'restart_cmd'      {
                    SendAck $cmd $true
                    wLog 'Reiniciando CMD...' 'WARN'
                    Start-Sleep 1
                    $c = 'iex (irm ''' + $GithubUrl + ''')'
                    Start-Process 'powershell.exe' -ArgumentList "-ExecutionPolicy Bypass -Command $c"
                    exit
                }
                'set_autoexec'     {
                    if ($data) {
                        try { SetAutoexec $data; SendAck $cmd $true }
                        catch { SendAck $cmd $false "$_" }
                    } else { wLog 'set_autoexec: URL vazia' 'WARN'; SendAck $cmd $false 'URL vazia' }
                }
                'set_cookies'      {
                    $cookiePath = "$env:USERPROFILE\Desktop\WebRB\YummyWebPlayer\cookie.txt"
                    if ($data) {
                        try {
                            $lista = $data | Where-Object { $_ -ne $null -and $_.Trim() -ne '' }
                            $unicos = $lista | Select-Object -Unique
                            [System.IO.File]::WriteAllLines($cookiePath, $unicos, [System.Text.UTF8Encoding]::new($false))
                            wLog "Cookies gravados: $($unicos.Count) linhas" 'OK'
                            SendAck $cmd $true
                        } catch { wLog "Erro ao gravar cookies: $_" 'ERROR'; SendAck $cmd $false "$_" }
                    } else { wLog 'set_cookies: dados vazios' 'WARN'; SendAck $cmd $false 'dados vazios' }
                }
                'clear_switched'   {
                    $swDir = "$env:USERPROFILE\Desktop\WebRB\YummyWebPlayer\switched"
                    try {
                        if (Test-Path $swDir) {
                            $files = Get-ChildItem $swDir -Filter '*.txt' -EA SilentlyContinue
                            $files | Remove-Item -Force -EA SilentlyContinue
                            wLog "Pasta switched limpa: $($files.Count) arquivo(s) removido(s)" 'OK'
                        } else { wLog 'Pasta switched nao encontrada' 'WARN' }
                        SendAck $cmd $true
                    } catch { wLog "Erro ao limpar switched: $_" 'ERROR'; SendAck $cmd $false "$_" }
                }
                'apply_volt_config' {
                    $cfgPath = "$env:USERPROFILE\Desktop\VoltBlack\volt_config.json"
                    if ($data) {
                        try {
                            # preserva password e username do arquivo existente
                            $keep = @{ password = $null; username = $null }
                            if (Test-Path $cfgPath) {
                                $cur = Get-Content $cfgPath -Raw | ConvertFrom-Json
                                $keep.password = $cur.password
                                $keep.username  = $cur.username
                            }
                            # converte data para PSObject e injeta as credenciais preservadas
                            $obj = $data | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                            if ($keep.password) { $obj | Add-Member -MemberType NoteProperty -Name 'password' -Value $keep.password -Force }
                            if ($keep.username)  { $obj | Add-Member -MemberType NoteProperty -Name 'username'  -Value $keep.username  -Force }
                            $obj | ConvertTo-Json -Depth 10 | Set-Content -Path $cfgPath -Encoding UTF8
                            wLog 'volt_config.json atualizado' 'OK'
                            SendAck $cmd $true
                        } catch { wLog "Erro ao gravar volt_config: $_" 'ERROR'; SendAck $cmd $false "$_" }
                    } else { wLog 'apply_volt_config: dados vazios' 'WARN'; SendAck $cmd $false 'dados vazios' }
                }
                'apply_webrb_config' {
                    $cfgPath = "$env:USERPROFILE\Desktop\WebRB\YummyWebPlayer\config.json"
                    if ($data) {
                        try {
                            $dir = Split-Path $cfgPath
                            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
                            # converte para JSON string, substitui qualquer C:\Users\QUALQUER\ pelo usuario correto
                            $json = $data | ConvertTo-Json -Depth 10
                            $json = $json -replace 'C:\\\\Users\\\\[^\\\\]+\\\\', "C:\\\\Users\\\\$($env:USERNAME)\\\\"
                            $json | Set-Content -Path $cfgPath -Encoding UTF8
                            wLog "config.json (WebRB) atualizado com caminhos de: $($env:USERNAME)" 'OK'
                            SendAck $cmd $true
                        } catch { wLog "Erro ao gravar config.json: $_" 'ERROR'; SendAck $cmd $false "$_" }
                    } else { wLog 'apply_webrb_config: dados vazios' 'WARN'; SendAck $cmd $false 'dados vazios' }
                }
                'clear_cookies'    {
                    $cookiePath = "$env:USERPROFILE\Desktop\WebRB\YummyWebPlayer\cookie.txt"
                    try {
                        [System.IO.File]::WriteAllText($cookiePath, '')
                        wLog 'cookie.txt limpo' 'OK'
                        SendAck $cmd $true
                    } catch { wLog "Erro ao limpar cookies: $_" 'ERROR'; SendAck $cmd $false "$_" }
                }
                'restart_pc'       {
                    wLog 'Reiniciando PC...' 'WARN'
                    try { FecharTudo } catch { wLog "Aviso ao fechar processos: $_" 'WARN' }
                    Start-Sleep 2
                    try {
                        & cmd.exe /c "shutdown /r /t 3 /f" 2>&1 | Out-Null
                        wLog 'Comando de reinicio enviado.' 'OK'
                        SendAck $cmd $true
                    } catch {
                        wLog "Erro ao reiniciar: $_" 'ERROR'
                        SendAck $cmd $false "$_"
                    }
                }
                'pause' {
                    $script:Paused = $true
                    $host.UI.RawUI.WindowTitle = 'Monitor [PAUSADO]'
                    wLog 'Monitor PAUSADO.' 'WARN'
                    SendAck $cmd $true
                }
                'resume' {
                    $script:Paused = $false
                    $host.UI.RawUI.WindowTitle = 'Monitor'
                    wLog 'Monitor RETOMADO.' 'OK'
                    SendAck $cmd $true
                }
                'set_volt_login'    {
                    $cfgPath = "$env:USERPROFILE\Desktop\VoltBlack\volt_config.json"
                    if ($data -and $data.username -and $data.password) {
                        try {
                            if (-not (Test-Path $cfgPath)) {
                                wLog 'volt_config.json nao encontrado' 'ERROR'
                                SendAck $cmd $false 'arquivo nao encontrado'
                                break
                            }
                            $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
                            $cfg | Add-Member -MemberType NoteProperty -Name 'username' -Value $data.username -Force
                            $cfg | Add-Member -MemberType NoteProperty -Name 'password' -Value $data.password -Force
                            $cfg | ConvertTo-Json -Depth 10 | Set-Content -Path $cfgPath -Encoding UTF8
                            # verifica se foi salvo corretamente
                            $verify = Get-Content $cfgPath -Raw | ConvertFrom-Json
                            if ($verify.username -eq $data.username -and $verify.password -eq $data.password) {
                                wLog "Login Volt aplicado: $($data.username)" 'OK'
                                SendAck $cmd $true
                            } else {
                                wLog 'Falha na verificacao do login' 'ERROR'
                                SendAck $cmd $false 'verificacao falhou'
                            }
                        } catch { wLog "Erro ao salvar login: $_" 'ERROR'; SendAck $cmd $false "$_" }
                    } else { wLog 'set_volt_login: dados invalidos' 'WARN'; SendAck $cmd $false 'dados invalidos' }
                }
                'screenshot'       {
                    try {
                        Add-Type -AssemblyName System.Windows.Forms,System.Drawing -EA Stop
                        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                        $bmp    = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
                        $gfx    = [System.Drawing.Graphics]::FromImage($bmp)
                        $gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
                        $ms     = New-Object System.IO.MemoryStream
                        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                        $b64    = [Convert]::ToBase64String($ms.ToArray())
                        $gfx.Dispose(); $bmp.Dispose(); $ms.Dispose()
                        $ssBody = @{ image = $b64 } | ConvertTo-Json -Compress
                        Invoke-RestMethod -Uri "$ApiUrl/screenshot/$MachineId" -Method POST -Headers $ApiHeaders -Body $ssBody -ContentType 'application/json' -TimeoutSec 30 -EA Stop | Out-Null
                        wLog 'Screenshot enviado' 'OK'
                        SendAck $cmd $true
                    } catch { wLog "Erro screenshot: $_" 'ERROR'; SendAck $cmd $false "$_" }
                }
                'run_ps'           {
                    if ($data) {
                        try {
                            $result = Invoke-Expression $data 2>&1
                            $out = if ($result) { ($result | Out-String).Trim() } else { '(sem saida)' }
                            wLog "run_ps OK: $($out.Substring(0, [Math]::Min(200, $out.Length)))" 'OK'
                            SendAck $cmd $true
                        } catch { wLog "run_ps ERRO: $_" 'ERROR'; SendAck $cmd $false "$_" }
                    } else { wLog 'run_ps: script vazio' 'WARN'; SendAck $cmd $false 'script vazio' }
                }
                default { wLog "Comando desconhecido: $cmd" 'WARN'; SendAck $cmd $false 'desconhecido' }
            }
        }
    } catch {
        $script:PollFailCount++
        if ($script:PollFailCount -eq 1 -or $script:PollFailCount % 30 -eq 0) {
            wLog "Falha ao conectar ao servidor ($($script:PollFailCount)x): $_" 'WARN'
        }
    }
}

# ── Init ─────────────────────────────────────────────────────────
Clear-Host
Write-Host ''
Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
Write-Host '  |        MONITOR  -  VoltPro Watchdog + Roblox Killer      |' -ForegroundColor DarkCyan
Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Volt : ' -NoNewline -ForegroundColor DarkGray; Write-Host $VoltExe   -ForegroundColor Cyan
Write-Host '  ID   : ' -NoNewline -ForegroundColor DarkGray; Write-Host $MachineId -ForegroundColor Cyan
Write-Host ''
Separador; Write-Host ''
wLog 'Monitor iniciado' 'OK'
$host.UI.RawUI.WindowTitle = 'Monitor'
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
