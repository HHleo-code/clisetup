# edmakers AI 도구 설치기 (윈도우)
# 사용법 (PowerShell 에 붙여넣기):
#   irm edm.run/win | iex
# 'powershell -ExecutionPolicy Bypass ...' 형태는 백신이 막는 PC 가 있어 쓰지 않는다.
#
# Claude Code·Codex 를 공식 설치기로 깔고, Node·Git 까지 관리자 권한 없이 맞춰 둔다.
# 수업에서 자주 막히던 것(실행 정책·옛 npm 설치·옛 Node·PATH)을 먼저 고친다.
# 윈도우 기본 PowerShell 5.1 에서 돌아야 한다. iex 로 돌기 때문에 exit 대신 return 을 쓴다.

& {
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$MacCmd  = 'curl -fsSL edm.run/mac | bash'
$Ver     = '2026-11-13'
$ReportUrl = if ($env:EDM_REPORT_URL) { $env:EDM_REPORT_URL } else { 'https://edm.run/api/install-report' }
$Mode    = 'install'
$CodexCfg = ''
$ResClaude = $null; $ResCodex = $null; $ResPy = $null
$Log     = Join-Path $env:USERPROFILE 'edm-설치기록.txt'
$ClaudeBin = Join-Path $env:USERPROFILE '.local\bin'
$CodexBin  = Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin'
$NodeHome  = Join-Path $env:LOCALAPPDATA 'Programs\edm-node'
$NpmPrefix = Join-Path $env:APPDATA 'npm'
$Tmp       = Join-Path $env:TEMP ("edm-setup-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

Set-Content -Path $Log -Value "edmakers 설치기록 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding UTF8
function L([string]$t)   { Add-Content -Path $Log -Value $t -Encoding UTF8 }
function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c; L $t }
function Ok([string]$t)  { Say "  [OK] $t" 'Green' }
function Fix([string]$t) { Say "  [고침] $t" 'Yellow' }
function Bad([string]$t) { Say "  [실패] $t" 'Red' }
function Step([string]$t){ Say ""; Say "> $t" 'Cyan' }

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
L "Windows $($os.Version) / $env:PROCESSOR_ARCHITECTURE / 사용자 $env:USERNAME / PowerShell $($PSVersionTable.PSVersion)"

# ── PATH 도우미 ──────────────────────────────────────
function Get-UserPath { $p = [Environment]::GetEnvironmentVariable('Path', 'User'); if ($p) { $p } else { '' } }
function Add-UserPath([string]$dir) {
    $parts = @((Get-UserPath) -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ne $dir.TrimEnd('\')) })
    $new = (@($dir) + $parts) -join ';'
    if ($new -ne (Get-UserPath)) { [Environment]::SetEnvironmentVariable('Path', $new, 'User') }
}
function Refresh-SessionPath {
    $env:Path = (Get-UserPath) + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
}
# 새 터미널을 열면 Windows 는 '시스템 PATH → 사용자 PATH' 순으로 찾는다. 그 순서로 실제 잡히는 파일을 찾는다.
function Resolve-NewTerminal([string]$name) {
    $dirs = ([Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + (Get-UserPath)) -split ';' | Where-Object { $_ }
    foreach ($d in $dirs) {
        $d = [Environment]::ExpandEnvironmentVariables($d)
        foreach ($ext in @('.exe', '.cmd', '.bat', '.ps1')) {
            $f = Join-Path $d ($name + $ext)
            if (Test-Path -LiteralPath $f -PathType Leaf) { return $f }
        }
    }
    return $null
}
function Node-Major([string]$exe) {
    try { $v = & $exe -v 2>$null; if ($v -match '^v(\d+)') { return [int]$Matches[1] } } catch {}
    return 0
}

# ── Codex 설정 점검·수리 ─────────────────────────────────
# 설치 뒤에 Codex 가 "Error loading configuration" 으로 아예 안 켜지는 일이 있다.
# 예) 한글 폴더 이름이 '??' 로 깨져 config.toml 에 들어가면 '??' 가 와일드카드로 읽혀 거부된다.
# Codex 자신에게 설정을 읽혀 보고(features list), 오류 문장에 찍힌 경로를 찾아 고친다.
$Utf8NoBom = New-Object Text.UTF8Encoding($false)
function Find-Codex {
    $c = Join-Path $CodexBin 'codex.exe'
    if (Test-Path -LiteralPath $c) { return $c }
    foreach ($n in @('codex.exe', 'codex')) {
        $g = Get-Command $n -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($g) { return $g.Source }
    }
    return $null
}
function Get-CodexConfigPath {
    $h = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    return (Join-Path $h 'config.toml')
}
function Test-CodexConfig([string]$exe) {
    # 판마다 문구가 다르다: 'Error loading configuration: ...' / 'Error: failed to load (bootstrap) configuration' + 'Caused by:' 아래 줄
    $out = (& $exe features list 2>&1 | ForEach-Object { "$_" }) -join "`n"
    if ($out -match '(?i)error loading configuration|failed to load (bootstrap )?configuration') {
        return ((($out -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' / ')
    }
    return $null
}
# 'C:\Users\me\Downloads\??' 처럼 깨진 경로를 실제 한글 폴더로 되돌린다. 후보가 딱 하나일 때만.
function Resolve-MangledPath([string]$bad) {
    $parts = @($bad -split '[\\/]')
    if ($parts.Count -lt 2) { return $null }
    $cur = if ($parts[0] -eq '~') { $env:USERPROFILE } elseif ($parts[0] -eq '') { [IO.Path]::DirectorySeparatorChar.ToString() } else { $parts[0] + '\' }
    for ($i = 1; $i -lt $parts.Count; $i++) {
        $seg = $parts[$i]
        if ($seg -eq '') { continue }
        if ($seg -notmatch '[?*\[]') { $cur = Join-Path $cur $seg; continue }
        if (-not (Test-Path -LiteralPath $cur -PathType Container)) { return $null }
        $kids = @(Get-ChildItem -LiteralPath $cur -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '[^\x00-\x7F]' })
        $m = @($kids | Where-Object { $_.Name -like $seg })
        if ($m.Count -ne 1) {
            $loose = '^' + ((($seg -split '[?*]+') | ForEach-Object { [regex]::Escape($_) }) -join '.+') + '$'
            $m = @($kids | Where-Object { $_.Name -match $loose })
        }
        if ($m.Count -ne 1) { return $null }
        $cur = Join-Path $cur $m[0].Name
    }
    return $cur
}
function Enc-Path([string]$p, [string]$k) {
    switch ($k) { 'dbl' { return $p.Replace('\', '\\') } 'slash' { return $p.Replace('\', '/') } default { return $p } }
}
function Repair-GlobEntry([string]$text, [string]$bad) {
    $real = Resolve-MangledPath $bad
    $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    $lines = @($text -split "`r?`n")
    $changed = $false
    foreach ($k in @('dbl', 'raw', 'slash')) {
        $f = Enc-Path $bad $k
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $ln = $lines[$i]
            if ($ln.TrimStart().StartsWith('#') -or -not $ln.Contains($f)) { continue }
            if ($real) { $lines[$i] = $ln.Replace($f, (Enc-Path $real $k)) }
            elseif ($ln -match '^\s*["'']') { $lines[$i] = '# edmakers 설치기가 끔 (깨진 경로): ' + $ln }
            else { $lines[$i] = [regex]::Replace($ln, '\s*["'']' + [regex]::Escape($f) + '["'']\s*,?', '') }
            $changed = $true
        }
        if ($changed) { break }
    }
    if (-not $changed) { return $null }
    return @{ text = ($lines -join $nl); real = $real }
}
# Codex 는 기본으로 작업 중 인터넷을 막아서 '깃허브 연결 안 됨'·'pip 설치 실패'가 난다. 작업 폴더 밖 쓰기 금지는 그대로 두고 인터넷만 연다.
function Get-NetworkText([string]$text) {
    $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    if ($text -match '(?m)^\s*sandbox_mode\s*=\s*"danger-full-access"') { return $null }
    $m = [regex]::Match($text, '(?m)^(\s*)default_permissions\s*=\s*["'']([^"'']+)["''][^\r\n]*')
    if ($m.Success) {
        $prof = $m.Groups[2].Value
        if ($prof.StartsWith(':')) {
            if ($text -match '(?m)^\s*\[\s*permissions\s*\.\s*edmakers\b') { return $null }
            $text = $text.Substring(0, $m.Index) + $m.Groups[1].Value + 'default_permissions = "edmakers"' + $text.Substring($m.Index + $m.Length)
            return $text.TrimEnd() + "$nl$nl[permissions.edmakers]${nl}extends = `"$prof`"$nl[permissions.edmakers.network]${nl}enabled = true$nl"
        }
        $esc = [regex]::Escape($prof)
        $h = [regex]::Match($text, '(?m)^\s*\[\s*permissions\s*\.\s*("' + $esc + '"|''' + $esc + '''|' + $esc + ')\s*\.\s*network\s*\][^\r\n]*')
        if ($h.Success) {
            $rest = $text.Substring($h.Index + $h.Length)
            $next = [regex]::Match($rest, '(?m)^\s*\[')
            $body = if ($next.Success) { $rest.Substring(0, $next.Index) } else { $rest }
            if ($body -match '(?m)^\s*enabled\s*=') { return $null }
            return $text.Insert($h.Index + $h.Length, "${nl}enabled = true")
        }
        return $text.TrimEnd() + "$nl$nl[permissions.`"$prof`".network]${nl}enabled = true$nl"
    }
    if ($text -match '(?m)^\s*\[\s*permissions\b') { return $null }
    if ($text -match '(?m)^\s*network_access\s*=\s*true') { return $null }
    return "default_permissions = `"edmakers`"$nl" + $text.TrimEnd() + "$nl$nl[permissions.edmakers]${nl}extends = `":workspace`"$nl[permissions.edmakers.network]${nl}enabled = true$nl"
}
# 결과: ok(그대로 정상) / fixed(고침) / fail(못 고침)
function Repair-Codex([string]$exe) {
    $cfg = Get-CodexConfigPath
    $state = 'ok'
    function Save-Backup { if (-not $script:cfgBackup -and (Test-Path -LiteralPath $cfg)) { $script:cfgBackup = "$cfg.edm-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"; Copy-Item -LiteralPath $cfg $script:cfgBackup -Force } }
    $script:cfgBackup = $null
    for ($round = 1; $round -le 8; $round++) {
        $err = Test-CodexConfig $exe
        if (-not $err) { break }
        L "Codex 설정 오류: $err"
        Save-Backup
        $state = 'fixed'
        $text = if (Test-Path -LiteralPath $cfg) { [IO.File]::ReadAllText($cfg) } else { '' }
        $r = $null
        if ($err -match 'filesystem glob path `([^`]+)`') { $r = Repair-GlobEntry $text $Matches[1] }
        if ($r) {
            [IO.File]::WriteAllText($cfg, $r.text, $Utf8NoBom)
            if ($r.real) { Fix "Codex 설정에 깨진 폴더 이름을 바로잡았어요 -> $($r.real)" } else { Fix "Codex 설정에서 깨진 폴더 경로 한 줄을 껐어요 ($($Matches[1]))" }
        } elseif (Test-Path -LiteralPath $cfg) {
            Remove-Item -LiteralPath $cfg -Force
            Fix "Codex 설정 파일에 고칠 수 없는 오류가 있어 새 설정으로 시작하게 했어요"
        } else { $round = 99 }
    }
    if (Test-CodexConfig $exe) { Bad "Codex 설정 오류를 못 고쳤어요"; return 'fail' }
    if ($state -eq 'fixed') { Ok "Codex 설정 정상으로 돌아왔어요 (원본: $script:cfgBackup)" } else { Ok "Codex 설정 정상" }

    $before = if (Test-Path -LiteralPath $cfg) { [IO.File]::ReadAllText($cfg) } else { $null }
    $after = Get-NetworkText $(if ($null -ne $before) { $before } else { '' })
    if ($null -eq $after) { Ok "Codex 인터넷 설정 그대로 둠"; L "Codex 인터넷 설정: 이미 있거나 손대지 않는 형태"; return $state }
    Save-Backup
    New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
    [IO.File]::WriteAllText($cfg, $after, $Utf8NoBom)
    $err = Test-CodexConfig $exe
    if ($err) {
        L "인터넷 허용 뒤 설정 오류 -> 되돌림: $err"
        if ($null -ne $before) { [IO.File]::WriteAllText($cfg, $before, $Utf8NoBom) } else { Remove-Item -LiteralPath $cfg -Force }
        Fix "Codex 인터넷 허용은 이 버전에 안 맞아서 건너뛰었어요"
    } else {
        Fix "Codex 가 작업 중에 인터넷(깃허브·설치 명령)을 쓸 수 있게 열었어요 (작업 폴더 밖 쓰기 금지는 그대로)"
    }
    return $state
}

# ── 결과 보고 ────────────────────────────────────────────
# 설치기록을 edm.run 으로 보내고 접수번호를 받는다. 사용자 이름·홈 경로는 가린다. EDM_NO_REPORT=1 이면 안 보냄.
function St($v) { if ($null -eq $v) { '' } elseif ($v -is [string]) { $v } elseif ($v) { 'ok' } else { 'fail' } }
function Send-Report([string]$result) {
    if ($env:EDM_NO_REPORT -eq '1') { return $null }
    try {
        $txt = [IO.File]::ReadAllText($Log)
        $txt = [regex]::Replace($txt, [regex]::Escape($env:USERPROFILE), '~', 'IgnoreCase')
        if ($env:USERNAME -and $env:USERNAME.Length -ge 3) { $txt = [regex]::Replace($txt, [regex]::Escape($env:USERNAME), '<사용자>', 'IgnoreCase') }
        if ($txt.Length -gt 60000) { $txt = $txt.Substring(0, 8000) + "`n...(중간 생략)...`n" + $txt.Substring($txt.Length - 50000) }
        $qs = "os=windows&mode=$Mode&result=$result&claude=$(St $ResClaude)&codex=$(St $ResCodex)&py=$(St $ResPy)&codexcfg=$CodexCfg&ver=$Ver"
        $code = Invoke-RestMethod -Uri "$ReportUrl`?$qs" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($txt)) -ContentType 'text/plain; charset=utf-8' -TimeoutSec 15 -UseBasicParsing
        $code = "$code".Trim()
        if ($code -match '^[A-Z0-9]{4,8}$') { return $code }
    } catch { L "보고 실패: $($_.Exception.Message)" }
    return $null
}

Clear-Host
Write-Host ""
Write-Host "  +------------------------------------------+" -ForegroundColor White
Write-Host "  |   edmakers  AI 도구 설치기               |" -ForegroundColor White
Write-Host "  |   Claude Code · Codex 를 한 번에          |" -ForegroundColor White
Write-Host "  +------------------------------------------+" -ForegroundColor White
Write-Host ""
Write-Host "  ※ 끝나면 설치 기록을 강사에게 자동으로 보냅니다 (사용자 이름은 가림)." -ForegroundColor DarkGray
Write-Host ""

# ── 1단계: 컴퓨터 종류 ────────────────────────────────
Say "[1단계] 어떤 컴퓨터인가요?" 'White'
Say "   1) 맥 (Mac)"
Say "   2) 윈도우 (Windows)     <- 지금 이 컴퓨터"
$osPick = Read-Host "   번호를 누르고 엔터 (그냥 엔터 = 2)"
L "   선택: $osPick"
if ($osPick -eq '1') {
    Say ""
    Say "  이 컴퓨터는 윈도우예요. 맥이라면 맥의 '터미널'에서 아래 한 줄을 붙여넣으세요." 'White'
    Say ""
    Say "     $MacCmd" 'White'
    Say ""
    $cont = Read-Host "  이 윈도우 컴퓨터에 계속 설치할까요? (엔터 = 예, n = 그만)"
    if ($cont -match '^(n|N|no|아니)') { Say "  설치를 멈췄습니다."; return }
}

# ── 2단계: 무엇을 설치할지 ─────────────────────────────
Say ""
Say "[2단계] 무엇을 설치할까요?" 'White'
Say "   1) Claude Code"
Say "   2) Codex"
Say "   3) 둘 다"
Say "   4) 이미 깔았는데 안 켜져요 (고장 수리만)"
while ($true) {
    $pick = Read-Host "   번호를 누르고 엔터"
    if ($pick -eq '') { $pick = '3' }
    if ($pick -in @('1', '2', '3', '4')) { break }
    Say "   1, 2, 3, 4 중에서 골라 주세요."
}
$RepairOnly = $pick -eq '4'
if ($RepairOnly) {
    $Mode = 'repair'
    $WantClaude = [bool]((Test-Path -LiteralPath (Join-Path $ClaudeBin 'claude.exe')) -or (Get-Command claude -ErrorAction SilentlyContinue))
    $WantCodex  = [bool](Find-Codex)
    if (-not ($WantClaude -or $WantCodex)) { Say "   이 컴퓨터에 Claude·Codex 가 없어요. 다시 실행해서 1~3 중에 고르세요." 'Yellow'; return }
} else {
    $WantClaude = $pick -in @('1', '3')
    $WantCodex  = $pick -in @('2', '3')
}
L "   선택: 수리만=$RepairOnly Claude=$WantClaude Codex=$WantCodex"

# ── 3단계: 데이터 분석 도구 ───────────────────────────
$WantPy = $false
if (-not $RepairOnly) {
    Say ""
    Say "[3단계] 파이썬(데이터 분석·한글 문서 도구용)도 설치할까요?" 'White'
    Say "   AI 가 파일을 다룰 때 자주 필요해서 기본은 '예'예요. 2~3분 더 걸려요."
    $pyPick = Read-Host "   그냥 엔터 = 예, n = 아니오"
    $WantPy = (-not ($pyPick -match '^(n|N|no|아니|ㅜ)')) -or ($env:EDM_WITH_PY -eq '1')
    L "   선택: Python=$WantPy"
}

# ── 점검·자동 수정 ────────────────────────────────────
Step "설치 전에 컴퓨터를 점검하고, 문제가 있으면 바로 고칩니다"

if (-not [Environment]::Is64BitOperatingSystem) {
    Bad "32비트 윈도우는 Claude·Codex 가 지원하지 않아요. 다른 컴퓨터를 쓰세요."; return
}
if ([Environment]::OSVersion.Version.Build -lt 17763) {
    Bad "윈도우가 너무 옛날 버전이에요 (Windows 10 1809 이상 필요). 윈도우 업데이트 후 다시 실행하세요."; return
}
Ok "윈도우 버전 정상 ($([Environment]::OSVersion.Version))"

# 1) 스크립트 실행 정책: npm·codex 같은 명령이 '스크립트를 실행할 수 없습니다'로 막히는 원인
$cu = Get-ExecutionPolicy -Scope CurrentUser
$lm = Get-ExecutionPolicy -Scope LocalMachine
$eff = if ($cu -ne 'Undefined') { $cu } elseif ($lm -ne 'Undefined') { $lm } else { 'Restricted' }
$gpo = @((Get-ExecutionPolicy -Scope MachinePolicy), (Get-ExecutionPolicy -Scope UserPolicy)) | Where-Object { $_ -ne 'Undefined' }
if ($gpo) {
    Fix "학교·회사 정책으로 실행 정책이 잠겨 있어요($($gpo -join ',')). npm 은 npm.cmd 로 쓰도록 안내합니다."
} elseif ($eff -in @('Restricted', 'AllSigned', 'Undefined')) {
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
        Fix "스크립트 실행 정책을 풀었어요 ($eff -> RemoteSigned, 이 사용자만)"
    } catch { Fix "실행 정책을 못 바꿨어요: $($_.Exception.Message)" }
} else {
    Ok "스크립트 실행 정책 정상 ($eff)"
}

if (-not $RepairOnly) {
# 2) 인터넷·학교 방화벽
function Test-Net([string]$url, [string]$name) {
    for ($i = 1; $i -le 3; $i++) {
        try { Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15 -Method Get | Out-Null; Ok "$name 서버 연결됨"; return $true } catch { Start-Sleep 2 }
    }
    Bad "$name 서버에 연결이 안 돼요 ($url)"
    Say "     -> 학교·회사 와이파이가 막는 경우가 많아요. 휴대폰 핫스팟으로 바꾼 뒤 다시 실행하세요."
    return $false
}
$netOk = $true
if ($WantClaude -and -not (Test-Net 'https://downloads.claude.ai/claude-code-releases/latest' 'Claude')) { $netOk = $false }
if ($WantCodex  -and -not (Test-Net 'https://chatgpt.com/codex/install.ps1' 'Codex')) { $netOk = $false }
if (-not $netOk) {
    $c = Send-Report 'fail'
    if ($c) { Say "  강사에게 기록을 보냈어요. 접수번호: $c" 'White' }
    return
}

# 3) 예전 npm 설치본 정리 (경로 충돌의 주범). npm.ps1 은 실행 정책에 막힐 수 있어 npm.cmd 를 직접 부른다.
$npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
function Remove-NpmPkg([string]$pkg, [string]$name) {
    if (-not $npmCmd) { return }
    & $npmCmd.Source ls -g --depth=0 $pkg 2>&1 | Out-String | ForEach-Object { L $_ }
    if ($LASTEXITCODE -eq 0) {
        Fix "예전에 npm 으로 깐 $name 가 있어서 지웁니다 (새 설치와 충돌해요)"
        & $npmCmd.Source uninstall -g $pkg 2>&1 | Out-String | ForEach-Object { L $_ }
        if ($LASTEXITCODE -eq 0) { Ok "npm 판 $name 삭제" } else { Fix "npm 판 $name 를 못 지웠어요 -> 경로 순서로 해결합니다" }
    }
}
if ($WantClaude) { Remove-NpmPkg '@anthropic-ai/claude-code' 'Claude Code' }
if ($WantCodex)  { Remove-NpmPkg '@openai/codex' 'Codex' }
Ok "옛 설치본 점검 끝"

# ── 기본 도구: Node·Git ───────────────────────────────
# Claude·Codex 자체는 Node 가 필요 없지만, 수업 중 MCP 서버·npx·git 을 쓰는 순간 막히므로 미리 깐다.
Step "기본 도구(Node·Git) 점검·설치"

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
function Get-NodeLts {
    $idx = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -TimeoutSec 30
    return ($idx | Where-Object { $_.lts } | Select-Object -First 1).version
}
function Get-Sha([string]$ver, [string]$file) {
    $sums = (Invoke-WebRequest -Uri "https://nodejs.org/dist/$ver/SHASUMS256.txt" -UseBasicParsing -TimeoutSec 30).Content
    foreach ($line in ($sums -split "`n")) { if ($line.Trim().EndsWith(" $file")) { return $line.Split(' ')[0] } }
    return $null
}
function Install-NodeZip {
    $ver = Get-NodeLts
    $zip = "node-$ver-win-$arch.zip"
    $zf = Join-Path $Tmp $zip
    Invoke-WebRequest -Uri "https://nodejs.org/dist/$ver/$zip" -OutFile $zf -UseBasicParsing -TimeoutSec 600
    if ((Get-FileHash $zf -Algorithm SHA256).Hash.ToLower() -ne (Get-Sha $ver $zip)) { throw "체크섬 불일치" }
    $ex = Join-Path $Tmp 'node-x'
    Expand-Archive -Path $zf -DestinationPath $ex -Force
    if (Test-Path $NodeHome) { Remove-Item $NodeHome -Recurse -Force }
    Move-Item -Path (Get-ChildItem $ex | Select-Object -First 1).FullName -Destination $NodeHome
    L "Node $ver -> $NodeHome"
}
# 시스템(Program Files)에 옛 Node 가 있으면 새 터미널에서 그게 먼저 잡힌다 -> 관리자 확인 한 번으로 그 자리를 새 버전으로 올린다
function Upgrade-SystemNode {
    $ver = Get-NodeLts
    $msi = "node-$ver-$arch.msi"
    $mf = Join-Path $Tmp $msi
    Invoke-WebRequest -Uri "https://nodejs.org/dist/$ver/$msi" -OutFile $mf -UseBasicParsing -TimeoutSec 600
    if ((Get-FileHash $mf -Algorithm SHA256).Hash.ToLower() -ne (Get-Sha $ver $msi)) { throw "체크섬 불일치" }
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$mf`" /qn /norestart" -Verb RunAs -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "msiexec 종료코드 $($p.ExitCode)" }
}

$nodeFound = Resolve-NewTerminal 'node'
$nodeMajor = if ($nodeFound) { Node-Major $nodeFound } else { 0 }
$machineNode = $false
if ($nodeFound) { $machineNode = -not $nodeFound.StartsWith($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase) -and -not $nodeFound.StartsWith($env:LOCALAPPDATA, [StringComparison]::OrdinalIgnoreCase) }

if ($nodeMajor -ge 20) {
    Ok "Node $(& $nodeFound -v) 이미 있음"
} elseif ($nodeFound -and $machineNode) {
    Fix "컴퓨터 전체에 옛 Node($(& $nodeFound -v))가 깔려 있어요. 새 버전으로 올립니다."
    Say "     화면에 '이 앱이 변경하도록 허용하시겠어요?' 창이 뜨면 [예] 를 누르세요." 'White'
    try { Upgrade-SystemNode; Ok "Node 를 새 버전으로 올렸어요" }
    catch {
        Fix "관리자 승인이 안 돼서 내 폴더에 새 Node 를 깔고 경로 순서로 우회합니다 ($($_.Exception.Message))"
        try { Install-NodeZip; Add-UserPath $NodeHome; Ok "Node 설치 (내 폴더)" } catch { Bad "Node 설치 실패: $($_.Exception.Message)" }
    }
} else {
    if ($nodeFound) { Fix "Node 가 너무 옛날 버전이라 새로 깝니다" } else { Fix "Node 가 없어서 설치합니다 (관리자 권한 불필요)" }
    $done = $false
    for ($i = 1; $i -le 3 -and -not $done; $i++) {
        try { Install-NodeZip; $done = $true } catch { L "Node 시도 $i 실패: $($_.Exception.Message)"; Start-Sleep 3 }
    }
    if ($done) { Add-UserPath $NodeHome; Ok "Node 설치 끝" } else { Bad "Node 설치 실패 (Claude·Codex 설치는 계속 진행)" }
}
Refresh-SessionPath

# npm 전역 설치 위치: 내 폴더(%APPDATA%\npm)로 고정하고 PATH 에 넣는다
$npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
if ($npmCmd) {
    New-Item -ItemType Directory -Force -Path $NpmPrefix | Out-Null
    & $npmCmd.Source config set prefix $NpmPrefix 2>&1 | Out-String | ForEach-Object { L $_ }
    Add-UserPath $NpmPrefix
    Ok "npm 전역 설치 위치를 내 폴더로 지정 (권한 오류 예방)"
}

# Git: 없으면 Claude 가 Bash 도구를 못 쓴다. 관리자 권한 없이 '이 사용자만' 설치한다.
function Find-GitBash {
    foreach ($b in @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
        if ($b -and (Test-Path -LiteralPath $b)) { return $b }
    }
    $g = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($g) { $b = Join-Path (Split-Path (Split-Path $g.Source)) 'bin\bash.exe'; if (Test-Path -LiteralPath $b) { return $b } }
    return $null
}
function Install-Git {
    # API 대신 'latest' 주소가 넘겨주는 태그로 파일 이름을 만든다 (교실 한 IP 에서 수십 명이 받아도 API 횟수 제한에 안 걸리게)
    $req = [Net.WebRequest]::Create('https://github.com/git-for-windows/git/releases/latest')
    $req.AllowAutoRedirect = $false
    $resp = $req.GetResponse(); $loc = $resp.Headers['Location']; $resp.Close()
    if ($loc -notmatch '/tag/v(\d+\.\d+\.\d+)\.windows\.(\d+)$') { throw "Git 최신 버전을 못 찾음 ($loc)" }
    $gv = if ($Matches[2] -eq '1') { $Matches[1] } else { "$($Matches[1]).$($Matches[2])" }
    $tag = "v$($Matches[1]).windows.$($Matches[2])"
    $suffix = if ($arch -eq 'arm64') { 'arm64' } else { '64-bit' }
    $exe = "Git-$gv-$suffix.exe"
    $ef = Join-Path $Tmp $exe
    Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/$tag/$exe" -OutFile $ef -UseBasicParsing -TimeoutSec 900
    $sig = Get-AuthenticodeSignature $ef
    if ($sig.Status -ne 'Valid') { throw "Git 설치파일 서명 확인 실패 ($($sig.Status))" }
    $p = Start-Process $ef -ArgumentList '/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES /CURRENTUSER' -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Git 설치 종료코드 $($p.ExitCode)" }
}
$gitBash = Find-GitBash
if ($gitBash) {
    Ok "Git 있음"
} else {
    Fix "Git 이 없어서 설치합니다 (2~3분, 관리자 권한 불필요)"
    $done = $false
    for ($i = 1; $i -le 2 -and -not $done; $i++) {
        try { Install-Git; $done = $true } catch { L "Git 시도 $i 실패: $($_.Exception.Message)"; Start-Sleep 3 }
    }
    if (-not $done) {
        $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($wg) {
            Fix "다른 경로(winget)로 다시 시도합니다"
            & $wg.Source install --id Git.Git -e --scope user --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String | ForEach-Object { L $_ }
        }
    }
    $gitBash = Find-GitBash
    if ($gitBash) { Ok "Git 설치 끝" } else { Bad "Git 설치 실패 (Claude 는 PowerShell 로 동작하니 수업은 진행 가능)" }
}
if ($gitBash) {
    Add-UserPath (Join-Path (Split-Path (Split-Path $gitBash)) 'cmd')
    # Claude 가 Git Bash 를 못 찾는 경우를 막기 위해 위치를 직접 알려 둔다
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $gitBash, 'User')
    $env:CLAUDE_CODE_GIT_BASH_PATH = $gitBash
}
Refresh-SessionPath

# ── 설치 ──────────────────────────────────────────────
# 공식 설치 스크립트는 실패하면 exit 를 부른다. PowerShell 을 새로 띄우면 백신이 '악성 패턴'으로 막는 PC 가 있어서,
# 같은 프로세스 안의 별도 실행공간(runspace)에서 돌린다. 거기서 exit 해도 이 창은 안 닫힌다.
# 성공 여부는 종료코드 대신 '실행 파일이 실제로 돌아가는지'로 판단한다.
function Run-Official([string]$url, [string]$name, [hashtable]$envs, [string]$exe) {
    for ($i = 1; $i -le 3; $i++) {
        Say "  . $name 설치 중... (시도 $i/3, 1~2분 걸려요)"
        $saved = @{}
        try {
            $code = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 60).Content
            if ($code -is [byte[]]) { $code = [Text.Encoding]::UTF8.GetString($code) }
            foreach ($k in $envs.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process'); [Environment]::SetEnvironmentVariable($k, $envs[$k], 'Process') }
            $ps = [PowerShell]::Create()
            try {
                [void]$ps.AddScript($code)
                $out = $ps.Invoke()
                L ($out | Out-String)
                foreach ($s in @($ps.Streams.Information) + @($ps.Streams.Warning) + @($ps.Streams.Error)) { L ([string]$s) }
            } finally { $ps.Dispose() }
        } catch { L "$name 시도 $i 오류: $($_.Exception.Message)" }
        finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') } }
        if ((Test-Path -LiteralPath $exe) -and (& $exe --version 2>$null)) { return $true }
        L "$name 시도 $i 뒤에도 $exe 가 실행되지 않음"
        Start-Sleep 3
    }
    return $false
}

$ResClaude = $null; $ResCodex = $null
if ($WantClaude) {
    Step "Claude Code 설치"
    if (Run-Official 'https://claude.ai/install.ps1' 'Claude Code' @{} (Join-Path $ClaudeBin 'claude.exe')) { Ok "Claude Code 설치 끝" } else { Bad "Claude Code 설치 실패" }
    Add-UserPath $ClaudeBin
}
if ($WantCodex) {
    Step "Codex 설치"
    if (Run-Official 'https://chatgpt.com/codex/install.ps1' 'Codex' @{ CODEX_NON_INTERACTIVE = '1' } (Join-Path $CodexBin 'codex.exe')) {
        Ok "Codex 설치 끝"
    } else {
        Fix "기본 서버가 안 돼서 깃허브 경로로 다시 받습니다"
        if (Run-Official 'https://chatgpt.com/codex/install.ps1' 'Codex' @{ CODEX_NON_INTERACTIVE = '1'; CODEX_INSTALLER_USE_RELEASES_OPENAI_COM = 'false' } (Join-Path $CodexBin 'codex.exe')) { Ok "Codex 설치 끝" } else { Bad "Codex 설치 실패" }
    }
    Add-UserPath $CodexBin
}
# ── 데이터 분석 도구: 파이썬 3.13 + pandas ──────────────
# 관리자 권한 없이 uv 로 내 폴더에 파이썬을 깐다. 3.13 고정: 최신판은 pandas 가 아직 안 맞을 수 있다.
# 내 폴더의 python.exe 가 사용자 PATH 앞에 오므로, 'python' 치면 스토어가 열리던 가짜 python 도 함께 해결된다.
$ResPy = $null
$UvExe = Join-Path $ClaudeBin 'uv.exe'
$PyExe = Join-Path $ClaudeBin 'python.exe'
function Install-Python {
    if (-not (Test-Path -LiteralPath $UvExe)) {
        if (-not (Run-Official 'https://astral.sh/uv/install.ps1' 'uv' @{ UV_NO_MODIFY_PATH = '1'; UV_INSTALL_DIR = $ClaudeBin } $UvExe)) { throw "uv 설치 실패" }
    }
    & $UvExe python install 3.13 --default 2>&1 | Out-String | ForEach-Object { L $_ }
    if (-not (Test-Path -LiteralPath $PyExe)) { throw "python.exe 가 생기지 않음" }
    # pip install 이 '관리되는 환경' 이라며 거부하지 않게 잠금 파일을 지운다 (내 폴더 전용 파이썬이라 안전)
    $pyRoot = (& $UvExe python dir 2>$null | Select-Object -First 1)
    if ($pyRoot -and (Test-Path -LiteralPath $pyRoot)) {
        Get-ChildItem -LiteralPath $pyRoot -Recurse -Filter 'EXTERNALLY-MANAGED' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    & $UvExe pip install --system --python $PyExe pandas openpyxl matplotlib 2>&1 | Out-String | ForEach-Object { L $_ }
    if ($LASTEXITCODE -ne 0) { throw "pandas 설치 실패 (종료코드 $LASTEXITCODE)" }
    # 그래프 한글 깨짐 방지
    $mpl = Join-Path $env:USERPROFILE '.matplotlib'
    New-Item -ItemType Directory -Force -Path $mpl | Out-Null
    [IO.File]::WriteAllText((Join-Path $mpl 'matplotlibrc'), "font.family : Malgun Gothic`naxes.unicode_minus : False`n")
}
if ($WantPy) {
    Step "데이터 분석 도구(파이썬·pandas) 설치"
    $done = $false
    for ($i = 1; $i -le 3 -and -not $done; $i++) {
        Say "  . 파이썬·pandas 설치 중... (시도 $i/3, 2~3분 걸려요)"
        try { Install-Python; $done = $true } catch { L "파이썬 시도 $i 실패: $($_.Exception.Message)"; Start-Sleep 3 }
    }
    if ($done) { Ok "파이썬·pandas 설치 끝" } else { Bad "파이썬·pandas 설치 실패" }
    Add-UserPath $ClaudeBin
}
Refresh-SessionPath
}  # ← 수리만 모드면 여기까지(인터넷 점검·Node·Git·설치)를 건너뛴다

# ── Codex 설정 점검·수리 (설치 직후 + 수리 모드) ─────────
if ($WantCodex) {
    $cx = Find-Codex
    if ($cx) { Step "Codex 설정 점검"; $CodexCfg = Repair-Codex $cx }
}

# ── 확인: 새 터미널을 연 것과 같은 순서로 찾아지는지 ───
Step "제대로 깔렸는지 확인합니다"
function Verify([string]$cmd, [string]$label, [string]$expectDir) {
    $exe = Join-Path $expectDir "$cmd.exe"
    if (-not (Test-Path -LiteralPath $exe)) { $exe = (Get-Command "$cmd.exe" -ErrorAction SilentlyContinue).Source }
    if (-not $exe) { Bad "${label}: 실행 파일이 없어요"; return $false }
    $ver = (& $exe --version 2>$null | Select-Object -First 1)
    if (-not $ver) { Bad "${label}: 실행이 안 돼요"; return $false }
    $hit = Resolve-NewTerminal $cmd
    if ($hit -and -not $hit.StartsWith($expectDir, [StringComparison]::OrdinalIgnoreCase)) {
        Fix "${label}: 새 창에서 다른 위치($hit)가 먼저 잡혀요"
        if ($hit -like '*\npm\*') {
            Remove-Item -LiteralPath $hit -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath ($hit -replace '\.(cmd|ps1)$', '') -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath ($hit -replace '\.cmd$', '.ps1') -Force -ErrorAction SilentlyContinue
            Fix "${label}: 옛 npm 실행 파일을 치웠어요"
        }
    }
    Ok "$label  $ver"
    return $true
}
if ($WantClaude) { $ResClaude = Verify 'claude' 'Claude Code' $ClaudeBin }
if ($WantCodex)  { $ResCodex  = Verify 'codex' 'Codex' $CodexBin; if ($CodexCfg -eq 'fail') { $ResCodex = $false } }
if ($WantPy) {
    $ResPy = $false
    if (Test-Path -LiteralPath $PyExe) {
        $chk = Join-Path $env:TEMP 'edm-hangul-check.py'
        [IO.File]::WriteAllText($chk, "import pandas, openpyxl, sys`nimport matplotlib`nmatplotlib.use('Agg')`nimport matplotlib.pyplot as plt`nfig, ax = plt.subplots(); ax.set_title('한글 그래프 확인 -1'); fig.savefig(r'$env:TEMP\edm-hangul-check.png')`nprint(sys.version.split()[0], pandas.__version__)`n", (New-Object Text.UTF8Encoding($false)))
        $pyOut = & $PyExe -W error::UserWarning $chk 2>&1 | Out-String
        $pyRc = $LASTEXITCODE
        L $pyOut
        if ($pyRc -eq 0) {
            $last = (($pyOut.Trim() -split "`n") | Select-Object -Last 1).Trim().Split(' ')
            Ok "파이썬 $($last[0]) / pandas $($last[1]) / 그래프 한글 정상"; $ResPy = $true
        } else { Bad "파이썬·pandas 확인 실패" }
        $hit = Resolve-NewTerminal 'python'
        if ($hit -and -not $hit.StartsWith($ClaudeBin, [StringComparison]::OrdinalIgnoreCase)) { Fix "새 창에서 다른 파이썬($hit)이 먼저 잡혀요. 'py' 대신 'python' 으로 쓰면 이 컴퓨터의 다른 파이썬이 실행될 수 있어요." }
    } else { Bad "파이썬: 실행 파일이 없어요" }
}
$n = Resolve-NewTerminal 'node'
if ($n) { Ok "Node  $(& $n -v)" } else { Bad "Node: 없음" }

# ── 결과 ──────────────────────────────────────────────
Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
Say ""
Say "---------------- 결과 ----------------" 'White'
if ($WantClaude) { if ($ResClaude) { Say "  Claude Code : 성공" 'Green' } else { Say "  Claude Code : 실패" 'Red' } }
if ($WantCodex)  { if ($ResCodex)  { Say "  Codex       : 성공" 'Green' } else { Say "  Codex       : 실패" 'Red' } }
if ($WantPy)     { if ($ResPy)     { Say "  파이썬·pandas: 성공" 'Green' } else { Say "  파이썬·pandas: 실패" 'Red' } }
Say ""
$allOk = ($ResClaude -ne $false) -and ($ResCodex -ne $false) -and ($ResPy -ne $false)
$code = Send-Report $(if ($allOk) { 'ok' } else { 'fail' })
if ($allOk -and $RepairOnly) {
    Say "  고칠 것을 다 고쳤어요. 이 창을 닫고 PowerShell 을 새로 연 다음 claude 나 codex 를 다시 실행해 보세요." 'White'
    Say "  Codex 앱이 열려 있었다면 앱도 껐다가 다시 켜세요."
    if ($code) { Say "  (기록 접수번호: $code)" 'DarkGray' }
} elseif ($allOk) {
    Say "  이제 이 창을 닫고, PowerShell 을 새로 연 다음 아래를 입력하세요." 'White'
    if ($WantClaude) { Say "     claude" 'White' }
    if ($WantCodex)  { Say "     codex" 'White' }
    Say ""
    Say "  처음 실행하면 브라우저가 열리면서 로그인을 물어봅니다."
    Say "  나중에 안 켜지면 같은 명령을 다시 붙여넣고 4번(고장 수리)을 고르세요."
    if ($code) { Say "  (설치 기록 접수번호: $code)" 'DarkGray' }
} else {
    Say "  일부가 실패했어요." 'Red'
    if ($code) {
        Say "  강사에게 기록이 자동으로 전달됐어요. 강사에게 이 번호를 알려 주세요." 'White'
        Say ""
        Say "     접수번호:  $code" 'Yellow'
    } else {
        Say "  아래 기록 파일을 강사에게 보여 주세요."
        Say "     $Log"
    }
    Say ""
    Say "  와이파이를 휴대폰 핫스팟으로 바꾸고 한 번 더 실행하면 대부분 해결됩니다."
}
}
