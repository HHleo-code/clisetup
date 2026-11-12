#!/usr/bin/env bash
# edmakers AI 도구 설치기 (맥)
# 사용법:  curl -fsSL edm.run/mac | bash
#
# Claude Code·Codex 를 Node/npm 없이 공식 설치기로 깔고,
# 수업에서 자주 막히던 것(옛 npm 설치 충돌·권한·PATH·별칭)을 먼저 고친다.
# 맥 기본 bash 3.2 에서 돌아야 한다.

set -u

WIN_CMD='irm edm.run/win | iex   (PowerShell 에 붙여넣기)'
BIN_DIR="$HOME/.local/bin"
LOG="$HOME/edm-설치기록.txt"
BLOCK_BEGIN="# >>> edmakers 설치기 >>>"
BLOCK_END="# <<< edmakers 설치기 <<<"
VER="2026-11-13"
REPORT_URL="${EDM_REPORT_URL:-https://edm.run/api/install-report}"
MODE="install"
CODEX_CFG=""
RES_CLAUDE=""; RES_CODEX=""; RES_PY=""; RES_KORDOC=""
GH_STATE=""
KORDOC_VER="4.24.69"
KORDOC_HOME="$HOME/.local/share/edm-kordoc"

# ── 화면 ──────────────────────────────────────────────
if [ -t 1 ]; then
  B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; C=$'\033[36m'; N=$'\033[0m'
else
  B=''; G=''; R=''; Y=''; C=''; N=''
fi
say()  { printf '%s\n' "$*"; printf '%s\n' "$*" >>"$LOG"; }
ok()   { say "  ${G}✔${N} $*"; }
fix()  { say "  ${Y}🔧${N} $*"; }
bad()  { say "  ${R}✘${N} $*"; }
step() { say ""; say "${B}${C}▶ $*${N}"; }

# curl | bash 로 돌면 표준입력이 스크립트 자신이라, 질문 답은 터미널에서 직접 읽는다
ask() {
  local answer=""
  if ( : </dev/tty ) 2>/dev/null; then
    printf '%s' "$1" >/dev/tty
    IFS= read -r answer </dev/tty || answer=""
  fi
  printf '%s' "$answer"
}

# ── 결과 보고 ────────────────────────────────────────────
# 설치기록을 edm.run 으로 보내고 접수번호를 받는다. 홈 경로·사용자 이름은 가린다. EDM_NO_REPORT=1 이면 안 보냄.
REPORT_CODE=""
send_report() {  # $1 ok|fail
  [ "${EDM_NO_REPORT:-0}" = 1 ] && return 1
  local f size
  f="$(mktemp)"
  size="$(wc -c <"$LOG" | tr -d ' ')"
  {
    if [ "$size" -gt 180000 ]; then head -c 24000 "$LOG"; printf '\n...(중간 생략)...\n'; tail -c 150000 "$LOG"; else cat "$LOG"; fi
  } | sed $'s/\033\\[[0-9;]*m//g' \
    | awk -v h="$HOME" -v u="$(whoami)" '{
        while ((i = index($0, h)) > 0) $0 = substr($0, 1, i - 1) "~" substr($0, i + length(h))
        if (length(u) >= 3) while ((i = index($0, u)) > 0) $0 = substr($0, 1, i - 1) "<사용자>" substr($0, i + length(u))
        print }' >"$f"
  REPORT_CODE="$(curl -fsS --max-time 15 -X POST -H 'Content-Type: text/plain; charset=utf-8' --data-binary @"$f" \
    "$REPORT_URL?os=mac&mode=$MODE&result=$1&claude=$RES_CLAUDE&codex=$RES_CODEX&py=$RES_PY&kordoc=$RES_KORDOC&gh=$GH_STATE&codexcfg=$CODEX_CFG&ver=$VER" 2>>"$LOG" | tr -d '[:space:]')"
  rm -f "$f"
  case "$REPORT_CODE" in [A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]*) return 0 ;; esac
  REPORT_CODE=""; return 1
}

# ── Codex 설정 점검·수리 ─────────────────────────────────
# 설치 뒤에 Codex 가 설정 파일 오류로 아예 안 켜지는 일이 있다 (예: 깨진 폴더 이름 '??' 가 와일드카드로 읽혀 거부됨).
# Codex 자신에게 설정을 읽혀 보고(features list), 오류 문장에 찍힌 경로를 찾아 고친다.
find_codex() {
  if [ -x "$BIN_DIR/codex" ]; then printf '%s' "$BIN_DIR/codex"; return 0; fi
  command -v codex 2>/dev/null
}
codex_cfg_err() {  # 오류가 있으면 0 + 오류 문장 출력
  local out
  out="$("$1" features list 2>&1 </dev/null)"
  if printf '%s' "$out" | grep -Eiq 'error loading configuration|failed to load (bootstrap )?configuration'; then
    printf '%s' "$out" | tr '\n' ' '; return 0
  fi
  return 1
}
# 깨진 경로가 든 줄을 끈다 (키 줄이면 주석 처리, 배열 안이면 그 항목만 뺀다)
codex_off_path() {  # $1 설정파일  $2 경로   → 바꾼 게 있으면 0
  local tmp; tmp="$(mktemp)"
  awk -v p="$2" '
    BEGIN { q1 = "\"" p "\""; q2 = "\047" p "\047"; hit = 0 }
    {
      t = $0; sub(/^[ \t]+/, "", t)
      if (substr(t, 1, 1) != "#" && (index($0, q1) || index($0, q2))) {
        hit = 1
        c = substr(t, 1, 1)
        if (c == "\"" || c == "\047") { print "# edmakers 설치기가 끔 (깨진 경로): " $0; next }
        while ((i = index($0, q1)) > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(q1))
        while ((i = index($0, q2)) > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(q2))
        gsub(/\[[ \t]*,/, "[", $0); gsub(/,[ \t]*,/, ",", $0)
      }
      print
    }
    END { exit hit ? 0 : 1 }' "$1" >"$tmp" && { cat "$tmp" >"$1"; rm -f "$tmp"; return 0; }
  rm -f "$tmp"; return 1
}
# Codex 는 기본으로 작업 중 인터넷을 막는다. 작업 폴더 밖 쓰기 금지는 두고 인터넷만 연다. 바꿀 게 없으면 1
codex_net_text() {  # $1 설정파일  $2 새 내용 쓸 파일
  local cfg="$1" out="$2" prof
  [ -f "$cfg" ] || : >"$cfg"
  grep -Eq '^[[:space:]]*sandbox_mode[[:space:]]*=[[:space:]]*"danger-full-access"' "$cfg" && return 1
  prof="$(sed -nE "s/^[[:space:]]*default_permissions[[:space:]]*=[[:space:]]*[\"']([^\"']+)[\"'].*/\\1/p" "$cfg" | head -n 1)"
  if [ -n "$prof" ]; then
    case "$prof" in
      :*)
        grep -Eq '^[[:space:]]*\[[[:space:]]*permissions[[:space:]]*\.[[:space:]]*edmakers' "$cfg" && return 1
        sed -E 's/^([[:space:]]*)default_permissions[[:space:]]*=.*/\1default_permissions = "edmakers"/' "$cfg" >"$out"
        printf '\n[permissions.edmakers]\nextends = "%s"\n[permissions.edmakers.network]\nenabled = true\n' "$prof" >>"$out"
        return 0 ;;
    esac
    awk -v p="$prof" '
      BEGIN { target = "[permissions." p ".network]"; state = 0; found = 0; has = 0 }
      { lines[NR] = $0; h = $0; sub(/#.*/, "", h); gsub(/[ \t"\047]/, "", h)
        if (substr(h, 1, 1) == "[") { if (state == 1) state = 2; if (h == target) { state = 1; found = NR } }
        else if (state == 1 && h ~ /^enabled=/) has = 1 }
      END { if (has) exit 3
        for (i = 1; i <= NR; i++) { print lines[i]; if (i == found) print "enabled = true" }
        if (!found) { print ""; print "[permissions.\"" p "\".network]"; print "enabled = true" } }' "$cfg" >"$out" || return 1
    return 0
  fi
  grep -Eq '^[[:space:]]*\[[[:space:]]*permissions([[:space:]]|\.|\])' "$cfg" && return 1
  grep -Eq '^[[:space:]]*network_access[[:space:]]*=[[:space:]]*true' "$cfg" && return 1
  { printf 'default_permissions = "edmakers"\n'; cat "$cfg"
    printf '\n[permissions.edmakers]\nextends = ":workspace"\n[permissions.edmakers.network]\nenabled = true\n'; } >"$out"
  return 0
}
# 결과: ok(그대로 정상) / fixed(고침) / fail(못 고침)
repair_codex() {  # $1 codex 실행파일
  local cx="$1" cfg="${CODEX_HOME:-$HOME/.codex}/config.toml" backup="" state=ok err bad round tmp had
  save_backup() { if [ -z "$backup" ] && [ -f "$cfg" ]; then backup="$cfg.edm-backup-$(date +%Y%m%d-%H%M%S)"; cp "$cfg" "$backup"; fi; }
  round=0
  while [ $round -lt 8 ] && err="$(codex_cfg_err "$cx")"; do
    round=$((round+1))
    printf 'Codex 설정 오류: %s\n' "$err" >>"$LOG"
    save_backup; state=fixed
    bad="$(printf '%s' "$err" | sed -nE 's/.*filesystem glob path `([^`]+)`.*/\1/p')"
    if [ -n "$bad" ] && [ -f "$cfg" ] && codex_off_path "$cfg" "$bad"; then
      fix "Codex 설정에서 깨진 폴더 경로 한 줄을 껐어요 ($bad)"
    elif [ -f "$cfg" ]; then
      rm -f "$cfg"; fix "Codex 설정 파일에 고칠 수 없는 오류가 있어 새 설정으로 시작하게 했어요"
    else
      break
    fi
  done
  if codex_cfg_err "$cx" >/dev/null; then bad "Codex 설정 오류를 못 고쳤어요"; CODEX_CFG=fail; return 1; fi
  if [ $state = fixed ]; then ok "Codex 설정 정상으로 돌아왔어요 (원본: $backup)"; else ok "Codex 설정 정상"; fi

  mkdir -p "$(dirname "$cfg")"
  had=0; [ -f "$cfg" ] && had=1
  tmp="$(mktemp)"
  if codex_net_text "$cfg" "$tmp"; then
    save_backup
    local before; before="$(mktemp)"; cp "$cfg" "$before"
    cat "$tmp" >"$cfg"
    if err="$(codex_cfg_err "$cx")"; then
      printf '인터넷 허용 뒤 설정 오류 -> 되돌림: %s\n' "$err" >>"$LOG"
      if [ $had = 1 ]; then cat "$before" >"$cfg"; else rm -f "$cfg"; fi
      fix "Codex 인터넷 허용은 이 버전에 안 맞아서 건너뛰었어요"
    else
      fix "Codex 가 작업 중에 인터넷(깃허브·설치 명령)을 쓸 수 있게 열었어요 (작업 폴더 밖 쓰기 금지는 그대로)"
    fi
    rm -f "$before"
  else
    [ $had = 0 ] && [ ! -s "$cfg" ] && rm -f "$cfg"
    ok "Codex 인터넷 설정 그대로 둠"
  fi
  rm -f "$tmp"
  CODEX_CFG=$state
  return 0
}

# ── kordoc (한글 문서 도구) ───────────────────────────────
# 수업 중에 AI 가 깃허브·npx 로 받으려다 막히지 않게, 설치할 때 내 폴더에 미리 깔고 Claude·Codex 에 등록해 둔다.
# 글자 인식(OCR) 부품(onnxruntime, 300MB)은 빼서 교실 와이파이로도 1분 안에 받게 한다. 한글·PDF·워드 읽기/쓰기는 그대로 된다.
install_kordoc() {
  local npm; npm="$(PATH="$BIN_DIR:$PATH" command -v npm)" || { echo "npm 없음"; return 1; }
  mkdir -p "$KORDOC_HOME/no-ocr" || return 1
  printf '{"name":"onnxruntime-node","version":"0.0.0-edm","main":"index.js"}' >"$KORDOC_HOME/no-ocr/package.json"
  printf 'throw new Error("OCR parts were left out by the edmakers installer");\n' >"$KORDOC_HOME/no-ocr/index.js"
  printf '{"private":true,"dependencies":{"kordoc":"%s"},"overrides":{"onnxruntime-node":"file:./no-ocr"}}' "$KORDOC_VER" >"$KORDOC_HOME/package.json"
  PATH="$BIN_DIR:$PATH" "$npm" install --prefix "$KORDOC_HOME" --no-fund --no-audit --loglevel=error || return 1
  [ -f "$KORDOC_HOME/node_modules/kordoc/dist/cli.js" ]
}
# 설정 파일에서 [mcp_servers.kordoc] 표(와 그 아래 하위 표)를 뺀다
remove_kordoc_table() {  # $1 파일 → 표준출력
  awk '/^[ \t]*\[/ { skip = ($0 ~ /^[ \t]*\[[ \t]*mcp_servers[ \t]*\.[ \t]*["\047]?kordoc["\047]?[ \t]*(\.|\])/) } !skip' "$1"
}
register_kordoc_codex() {  # $1 codex  $2 node  $3 mcp.js
  local cfg="${CODEX_HOME:-$HOME/.codex}/config.toml" before="" had=0 base extra
  mkdir -p "$(dirname "$cfg")"
  if [ -f "$cfg" ]; then had=1; before="$(mktemp)"; cp "$cfg" "$before"; fi
  base="$(mktemp)"
  if [ $had = 1 ]; then remove_kordoc_table "$before" >"$base"; fi
  for extra in 'default_tools_approval_mode = "approve"' ''; do
    { cat "$base"; printf "\n[mcp_servers.kordoc]\ncommand = '%s'\nargs = ['%s']\n" "$2" "$3"; [ -n "$extra" ] && printf '%s\n' "$extra"; } >"$cfg"
    if ! err="$(codex_cfg_err "$1")"; then rm -f "$base" "$before"; return 0; fi
    printf 'Codex kordoc 등록 뒤 설정 오류 -> 다시: %s\n' "$err" >>"$LOG"
  done
  if [ $had = 1 ]; then cat "$before" >"$cfg"; else rm -f "$cfg"; fi
  rm -f "$base" "$before"; return 1
}
register_kordoc_claude() {  # $1 node  $2 mcp.js
  local cl="$BIN_DIR/claude"
  [ -x "$cl" ] || cl="$(command -v claude 2>/dev/null)" || return 1
  "$cl" mcp remove -s user kordoc >>"$LOG" 2>&1 </dev/null
  "$cl" mcp add -s user kordoc "$1" "$2" >>"$LOG" 2>&1 </dev/null
  "$cl" mcp get kordoc >>"$LOG" 2>&1 </dev/null
}

: >"$LOG"
say "edmakers 설치기록 — $(date '+%Y-%m-%d %H:%M:%S')"
say "맥OS $(sw_vers -productVersion 2>/dev/null) / $(uname -m) / 사용자 $(whoami)"

clear 2>/dev/null || true
cat <<EOF

${B}  ┌──────────────────────────────────────────┐
  │   edmakers  AI 도구 설치기               │
  │   Claude Code · Codex 를 한 번에          │
  └──────────────────────────────────────────┘${N}

  ※ 끝나면 설치 기록을 강사에게 자동으로 보냅니다 (사용자 이름은 가림).

${Y}  [고르는 법] 번호 목록이 나오면, 키보드에서 원하는 숫자를 누르고
              엔터(return) 키를 누르세요. 마우스로는 고를 수 없어요.${N}

EOF

# ── 1단계: 컴퓨터 종류 ────────────────────────────────
if [ "$(uname -s)" = "Darwin" ]; then
  HERE="맥"
else
  HERE="리눅스"
fi

say "${B}[1단계] 어떤 컴퓨터인가요?${N}"
say "   1) 맥 (Mac)          $( [ "$HERE" = 맥 ] && echo '← 지금 이 컴퓨터' )"
say "   2) 윈도우 (Windows)"
os_pick="$(ask '   원하는 숫자를 키보드로 누르고 엔터 (지금 이 컴퓨터면 그냥 엔터): ')"
say "   선택: ${os_pick:-1}"

if [ "$os_pick" = "2" ]; then
  say ""
  say "  이 컴퓨터는 ${B}${HERE}${N}이에요. 윈도우 컴퓨터라면 그쪽에서 아래 한 줄을 붙여넣으세요."
  say ""
  say "     ${B}${WIN_CMD}${N}"
  say ""
  cont="$(ask "  이 ${HERE} 컴퓨터에 계속 설치할까요? (그냥 엔터 = 예 / 그만두려면 n 누르고 엔터): ")"
  case "$cont" in n|N|no|아니*|ㅜ) say "  설치를 멈췄습니다."; exit 0 ;; esac
fi

# ── 2단계: 무엇을 설치할지 ─────────────────────────────
say ""
say "${B}[2단계] 무엇을 설치할까요?${N}"
say "   1) Claude Code"
say "   2) Codex"
say "   3) 둘 다"
say "   4) 이미 깔았는데 안 켜져요 (고장 수리만)"
pick=""
while :; do
  pick="$(ask '   원하는 숫자(1~4)를 키보드로 누르고 엔터 (그냥 엔터 = 3 둘 다): ')"
  case "$pick" in 1|2|3|4) break ;; "") pick=3; break ;; esac
  say "   ${Y}키보드 위쪽 줄의 숫자 1, 2, 3, 4 중 하나를 누르고 엔터를 치세요.${N}"
done
WANT_CLAUDE=0; WANT_CODEX=0; REPAIR_ONLY=0
case "$pick" in 1) WANT_CLAUDE=1 ;; 2) WANT_CODEX=1 ;; 3) WANT_CLAUDE=1; WANT_CODEX=1 ;; 4) REPAIR_ONLY=1; MODE=repair ;; esac
if [ $REPAIR_ONLY = 1 ]; then
  [ -x "$BIN_DIR/claude" ] && WANT_CLAUDE=1
  [ -x "$BIN_DIR/codex" ] && WANT_CODEX=1
  if [ $WANT_CLAUDE = 0 ] && [ $WANT_CODEX = 0 ] && [ -z "$(find_codex)" ]; then
    say "   이 컴퓨터에 Claude·Codex 가 없어요. 다시 실행해서 1~3 중에 고르세요."; exit 1
  fi
fi
say "   선택: $( [ $REPAIR_ONLY = 1 ] && printf '고장 수리만 · ' )$( [ $WANT_CLAUDE = 1 ] && printf 'Claude Code ' )$( [ $WANT_CODEX = 1 ] && printf 'Codex' )"

# ── 3단계: 데이터 분석 도구 ───────────────────────────
WANT_PY=0
if [ $REPAIR_ONLY = 0 ]; then
  say ""
  say "${B}[3단계] 파이썬(데이터 분석·한글 문서 도구용)도 설치할까요?${N}"
  say "   AI 가 파일을 다룰 때 자주 필요해서 기본은 '예'예요. 2~3분 더 걸려요."
  py_pick="$(ask '   그냥 엔터 = 예 / 싫으면 n 누르고 엔터: ')"
  WANT_PY=1
  case "$py_pick" in n|N|no|아니*|ㅜ) WANT_PY=0 ;; esac
  [ "${EDM_WITH_PY:-0}" = 1 ] && WANT_PY=1
  say "   선택: $( [ $WANT_PY = 1 ] && echo '예' || echo '아니오' )"
fi

# ── 4단계: 한글 문서 도구 kordoc ───────────────────────
WANT_KORDOC=0
if [ $REPAIR_ONLY = 0 ]; then
  say ""
  say "${B}[4단계] 한글 문서 도구(kordoc)도 미리 설치할까요?${N}"
  say "   AI 가 한글(HWP)·PDF·워드 문서를 읽고 만들 수 있게 해 줘요. 1분쯤 더 걸려요."
  say "   미리 깔아 두면 수업 중에 와이파이가 깃허브를 막아도 그대로 쓸 수 있어요."
  kd_pick="$(ask '   그냥 엔터 = 예 / 싫으면 n 누르고 엔터: ')"
  WANT_KORDOC=1
  case "$kd_pick" in n|N|no|아니*|ㅜ) WANT_KORDOC=0 ;; esac
  say "   선택: $( [ $WANT_KORDOC = 1 ] && echo '예' || echo '아니오' )"
elif [ -f "$KORDOC_HOME/node_modules/kordoc/dist/mcp.js" ]; then
  WANT_KORDOC=1  # 수리 모드: 전에 깐 kordoc 이 있으면 연결만 다시 해 둔다
fi

# ── 점검·자동 수정 ────────────────────────────────────
step "설치 전에 컴퓨터를 점검하고, 문제가 있으면 바로 고칩니다"

# 1) sudo 로 실행하면 관리자 폴더에 깔려 다음부터 계속 꼬인다
if [ "$(id -u)" = "0" ]; then
  bad "관리자(sudo)로 실행됐어요. 이렇게 깔면 나중에 권한 오류가 납니다."
  say "     sudo 를 빼고 다시 붙여넣으세요:  curl -fsSL edm.run/mac | bash"
  exit 1
fi
ok "일반 사용자로 실행 중"

# 2) 인터넷·학교 방화벽
check_net() {  # $1 주소  $2 이름
  local i
  for i in 1 2 3; do
    if curl -fsS -o /dev/null --max-time 10 "$1" 2>/dev/null; then
      ok "$2 서버 연결됨"; return 0
    fi
    sleep 2
  done
  bad "$2 서버에 연결이 안 돼요 ($1)"
  say "     → 학교·회사 와이파이가 막는 경우가 많아요. 휴대폰 핫스팟으로 바꾼 뒤 다시 실행하세요."
  return 1
}
# 깃허브 연결: 막혀도 설치는 계속한다. 수업 중 AI 가 깃허브에서 받으려 할 때 막힐 수 있다는 것만 알리고 기록에 남긴다.
if curl -fsS -o /dev/null --max-time 10 -I https://github.com 2>>"$LOG" || curl -fsS -o /dev/null --max-time 10 -I https://github.com 2>>"$LOG"; then
  ok "깃허브 연결됨"; GH_STATE=ok
else
  GH_STATE=blocked
  fix "이 와이파이는 깃허브(github.com)를 막고 있어요. 설치는 계속합니다."
  say "     ${Y}→ 수업 중에 AI 가 깃허브에서 뭔가 받으려 하면 실패할 수 있어요. 가능하면 휴대폰 핫스팟을 쓰세요.${N}"
fi
NET_OK=1
if [ $REPAIR_ONLY = 0 ]; then
  [ $WANT_CLAUDE = 1 ] && { check_net "https://downloads.claude.ai/claude-code-releases/latest" "Claude" || NET_OK=0; }
  [ $WANT_CODEX = 1 ]  && { check_net "https://chatgpt.com/codex/install.sh" "Codex" || NET_OK=0; }
fi
if [ $NET_OK = 0 ]; then
  send_report fail && say "  강사에게 기록을 보냈어요. 접수번호: ${B}$REPORT_CODE${N}"
  exit 1
fi

# 3) 예전에 sudo 로 설치하다 생긴 '주인이 관리자인 폴더' 되돌리기
need_own=""
for d in "$HOME/.local" "$HOME/.local/bin" "$HOME/.local/share" "$HOME/.claude" "$HOME/.codex" "$HOME/.claude.json"; do
  if [ -e "$d" ] && [ ! -w "$d" ]; then need_own="$need_own $d"; fi
done
if [ -n "$need_own" ]; then
  fix "관리자 소유로 잠긴 폴더가 있어요:$need_own"
  say "     맥 로그인 비밀번호를 물으면 입력하세요 (화면에 안 보여도 입력되고 있어요)."
  # shellcheck disable=SC2086
  if sudo chown -R "$(id -u):$(id -g)" $need_own </dev/tty; then
    ok "폴더 권한을 되돌렸어요"
  else
    bad "권한을 못 바꿨어요. 강사에게 이 화면을 보여 주세요."
  fi
else
  ok "폴더 권한 정상"
fi
mkdir -p "$BIN_DIR"

# 4) 예전 npm 설치본 정리 (경로 충돌의 주범)
remove_npm_pkg() {  # $1 패키지  $2 이름
  command -v npm >/dev/null 2>&1 || return 0
  if npm ls -g --depth=0 "$1" >/dev/null 2>&1; then
    fix "예전에 npm 으로 깐 $2 가 있어서 지웁니다 (새 설치와 충돌해요)"
    if npm uninstall -g "$1" >>"$LOG" 2>&1; then
      ok "npm 판 $2 삭제"
    else
      fix "npm 판 $2 는 권한 때문에 못 지웠어요 → 새 설치가 먼저 실행되도록 경로 순서로 해결합니다"
    fi
  fi
}
[ $WANT_CLAUDE = 1 ] && remove_npm_pkg "@anthropic-ai/claude-code" "Claude Code"
[ $WANT_CODEX = 1 ]  && remove_npm_pkg "@openai/codex" "Codex"

# 5) 셸 설정에 남은 옛 별칭(alias claude=..., alias codex=...) 끄기
RC_FILES="$HOME/.zshrc $HOME/.zprofile $HOME/.bash_profile $HOME/.bashrc $HOME/.profile"
names=""
[ $WANT_CLAUDE = 1 ] && names="claude"
[ $WANT_CODEX = 1 ] && names="${names:+$names|}codex"
alias_fixed=0
for f in $RC_FILES; do
  [ -f "$f" ] || continue
  if grep -Eq "^[[:space:]]*alias[[:space:]]+($names)=" "$f"; then
    cp "$f" "$f.edm-backup"
    sed -E -i '' "s/^([[:space:]]*alias[[:space:]]+($names)=)/# edmakers 설치기가 끔: \1/" "$f"
    fix "$(basename "$f") 의 옛 별칭을 껐어요 (원본: $(basename "$f").edm-backup)"
    alias_fixed=1
  fi
done
[ $alias_fixed = 0 ] && ok "충돌하는 별칭 없음"

# 6) 새 터미널에서 바로 찾도록 PATH 등록 (zsh·bash 둘 다)
add_path_block() {  # $1 파일
  local f="$1"
  [ -f "$f" ] || touch "$f"
  if grep -Fq "$BLOCK_BEGIN" "$f"; then return 0; fi
  {
    printf '\n%s\n' "$BLOCK_BEGIN"
    printf 'export PATH="$HOME/.local/bin:$PATH"\n'
    printf '%s\n' "$BLOCK_END"
  } >>"$f"
}
for f in "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.bash_profile"; do add_path_block "$f"; done
export PATH="$BIN_DIR:$PATH"
ok "실행 경로(PATH) 등록"

GIT_PENDING=0
if [ $REPAIR_ONLY = 0 ]; then  # ← 수리만 모드면 Node·Git·설치를 건너뛴다
# ── 기본 도구: Node·Git ───────────────────────────────
# Claude·Codex 자체는 Node 가 필요 없지만, 수업 중 MCP 서버·npx·git 을 쓰는 순간 막히므로 미리 깐다.
step "기본 도구(Node·Git) 점검·설치"

NODE_HOME="$HOME/.local/share/edm-node"
node_major() { "$1" -v 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/'; }

install_node() {
  local arch ver tarball url sums tmp
  case "$(uname -m)" in arm64) arch=arm64 ;; *) arch=x64 ;; esac
  ver="$(curl -fsSL --max-time 20 https://nodejs.org/dist/index.json \
        | tr '{' '\n' | grep -v '"lts":false' | grep -o '"version":"v[0-9.]*"' | head -n 1 | cut -d'"' -f4)"
  [ -n "$ver" ] || return 1
  tarball="node-$ver-darwin-$arch.tar.gz"
  url="https://nodejs.org/dist/$ver/$tarball"
  tmp="$(mktemp -d)"
  curl -fsSL --max-time 300 "$url" -o "$tmp/$tarball" || return 1
  sums="$(curl -fsSL --max-time 20 "https://nodejs.org/dist/$ver/SHASUMS256.txt" | grep " $tarball\$" | cut -d' ' -f1)"
  [ "$(shasum -a 256 "$tmp/$tarball" | cut -d' ' -f1)" = "$sums" ] || { say "     체크섬 불일치"; return 1; }
  rm -rf "$NODE_HOME" && mkdir -p "$NODE_HOME"
  tar -xzf "$tmp/$tarball" -C "$NODE_HOME" --strip-components 1 || return 1
  rm -rf "$tmp"
  for b in node npm npx corepack; do ln -sf "$NODE_HOME/bin/$b" "$BIN_DIR/$b"; done
  say "     Node $ver 설치"
}

HAS_NVM=0
{ [ -d "$HOME/.nvm" ] || [ -n "${NVM_DIR:-}" ]; } && HAS_NVM=1
cur_node="$(command -v node 2>/dev/null || true)"
cur_major="$( [ -n "$cur_node" ] && node_major "$cur_node" || echo 0 )"
if [ "${cur_major:-0}" -ge 20 ] 2>/dev/null; then
  ok "Node $("$cur_node" -v) 이미 있음"
else
  [ -n "$cur_node" ] && fix "Node 가 너무 옛날 버전($("$cur_node" -v))이라 새로 깝니다" || fix "Node 가 없어서 설치합니다 (관리자 권한 불필요)"
  i=0; node_done=0
  while [ $i -lt 3 ]; do
    i=$((i+1))
    if install_node >>"$LOG" 2>&1; then node_done=1; break; fi
    sleep 3
  done
  if [ $node_done = 1 ]; then ok "Node $("$BIN_DIR/node" -v) 설치 끝"; else bad "Node 설치 실패 (Claude·Codex 설치는 계속 진행)"; fi
fi

# npm 전역 설치가 관리자 폴더로 가면 EACCES 가 난다 → 내 폴더(~/.local)로 돌린다 (nvm 쓰는 사람은 건드리지 않음)
if command -v npm >/dev/null 2>&1 && [ $HAS_NVM = 0 ]; then
  npm_prefix="$(npm config get prefix 2>/dev/null)"
  if [ ! -w "$npm_prefix/lib" ] 2>/dev/null || [ "$npm_prefix" != "$HOME/.local" ]; then
    npm config set prefix "$HOME/.local" >>"$LOG" 2>&1 && ok "npm 전역 설치 위치를 내 폴더로 지정 (권한 오류 예방)"
  else
    ok "npm 전역 설치 위치 정상"
  fi
fi

# Git: 맥은 '개발자 도구(Command Line Tools)'에 들어 있다
if xcode-select -p >/dev/null 2>&1 && /usr/bin/git --version >/dev/null 2>&1; then
  ok "Git 있음 ($(/usr/bin/git --version | cut -d' ' -f3))"
  GIT_PENDING=0
else
  fix "Git(맥 개발자 도구)이 없어서 설치 창을 띄웁니다 → 뜨는 창에서 ${B}[설치]${N} 를 누르세요"
  xcode-select --install >>"$LOG" 2>&1 || true
  say "     (5~10분 걸려요. 기다리는 동안 아래 설치는 계속 진행됩니다)"
  GIT_PENDING=1
fi

# ── 설치 ──────────────────────────────────────────────
run_with_retry() {  # $1 이름  나머지: 명령
  local name="$1"; shift
  local i
  for i in 1 2 3; do
    say "  · $name 설치 중... (시도 $i/3, 1~2분 걸려요)"
    if "$@" >>"$LOG" 2>&1 </dev/null; then return 0; fi
    sleep 3
  done
  return 1
}

install_claude() {
  curl -fsSL https://claude.ai/install.sh | bash
}
install_codex() {
  curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
}
install_codex_github() {
  # OpenAI 다운로드 서버가 막힐 때 깃허브에서 받는 방식
  curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 CODEX_INSTALLER_USE_RELEASES_OPENAI_COM=false sh
}

if [ $WANT_CLAUDE = 1 ]; then
  step "Claude Code 설치"
  if run_with_retry "Claude Code" install_claude; then ok "Claude Code 설치 끝"; else bad "Claude Code 설치 실패"; fi
fi
if [ $WANT_CODEX = 1 ]; then
  step "Codex 설치"
  if run_with_retry "Codex" install_codex; then
    ok "Codex 설치 끝"
  else
    fix "기본 서버가 안 돼서 깃허브 경로로 다시 받습니다"
    if run_with_retry "Codex" install_codex_github; then ok "Codex 설치 끝"; else bad "Codex 설치 실패"; fi
  fi
fi

# ── 데이터 분석 도구: 파이썬 3.13 + pandas ──────────────
# 관리자 권한 없이 uv 로 내 폴더에 파이썬을 깐다. 3.13 고정: 최신판은 pandas 가 아직 안 맞을 수 있다.
install_python() {
  if [ ! -x "$BIN_DIR/uv" ]; then
    curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh || return 1
  fi
  "$BIN_DIR/uv" python install 3.13 --default || return 1
  # pip install 이 '관리되는 환경' 이라며 거부하지 않게 잠금 파일을 지운다 (내 폴더 전용 파이썬이라 안전)
  find "$HOME/.local/share/uv/python" -path '*cpython-3.13*' -name EXTERNALLY-MANAGED -delete 2>/dev/null
  "$BIN_DIR/uv" pip install --system --python "$BIN_DIR/python" pandas openpyxl matplotlib || return 1
  # 그래프 한글 깨짐 방지
  mkdir -p "$HOME/.matplotlib"
  printf 'font.family : AppleGothic\naxes.unicode_minus : False\n' >"$HOME/.matplotlib/matplotlibrc"
}
if [ $WANT_PY = 1 ]; then
  step "데이터 분석 도구(파이썬·pandas) 설치"
  if run_with_retry "파이썬·pandas" install_python; then ok "파이썬·pandas 설치 끝"; else bad "파이썬·pandas 설치 실패"; fi
fi
if [ $WANT_KORDOC = 1 ]; then
  step "한글 문서 도구(kordoc) 설치"
  if run_with_retry "kordoc" install_kordoc; then ok "kordoc 설치 끝"; else bad "kordoc 설치 실패"; fi
fi
fi  # ← 수리만 모드 건너뛰기 끝

# ── Codex 설정 점검·수리 (설치 직후 + 수리 모드) ─────────
CX="$(find_codex)"
if [ -n "$CX" ] && { [ $WANT_CODEX = 1 ] || [ $REPAIR_ONLY = 1 ]; }; then
  step "Codex 설정 점검"
  repair_codex "$CX"
fi

# ── kordoc 을 Claude·Codex 에 등록 ─────────────────────
K_JS="$KORDOC_HOME/node_modules/kordoc/dist/mcp.js"
K_NODE=""
if [ $WANT_KORDOC = 1 ] && [ -f "$K_JS" ]; then
  step "kordoc 을 AI 도구에 연결"
  K_NODE="$(PATH="$BIN_DIR:$PATH" command -v node)"
  RES_KORDOC=ok
  if [ $WANT_CLAUDE = 1 ]; then
    if register_kordoc_claude "$K_NODE" "$K_JS"; then ok "Claude Code 에 kordoc 연결"; else bad "Claude Code 에 kordoc 연결 실패"; RES_KORDOC=fail; fi
  fi
  if [ $WANT_CODEX = 1 ]; then
    CX="$(find_codex)"
    if [ -n "$CX" ] && [ "$CODEX_CFG" != fail ] && register_kordoc_codex "$CX" "$K_NODE" "$K_JS"; then ok "Codex 에 kordoc 연결"; else bad "Codex 에 kordoc 연결 실패"; RES_KORDOC=fail; fi
  fi
elif [ $WANT_KORDOC = 1 ]; then
  RES_KORDOC=fail
fi

# ── 확인: 새 터미널을 연 것과 똑같이 찾아지는지 ────────
step "제대로 깔렸는지 확인합니다"
verify() {  # $1 명령이름  $2 표시이름
  local found ver
  found="$(env -i HOME="$HOME" USER="$USER" PATH="/usr/bin:/bin:/usr/sbin:/sbin" TERM=dumb \
           /bin/zsh -lic "whence -p $1" 2>/dev/null | tail -n 1)"
  ver="$("$BIN_DIR/$1" --version 2>/dev/null | head -n 1)"
  if [ -z "$ver" ]; then
    bad "$2: 실행이 안 돼요"; return 1
  fi
  if [ "$found" != "$BIN_DIR/$1" ]; then
    if [ -n "$found" ]; then
      fix "$2: 새 터미널에서 다른 위치($found)가 먼저 잡혀서 경로 순서를 고칩니다"
    else
      fix "$2: 새 터미널에서 못 찾아서 경로를 다시 등록합니다"
    fi
    for f in "$HOME/.zshrc" "$HOME/.bash_profile"; do
      printf '\n%s\nexport PATH="$HOME/.local/bin:$PATH"\n%s\n' "$BLOCK_BEGIN (뒤쪽)" "$BLOCK_END" >>"$f"
    done
  fi
  ok "$2  ${B}$ver${N}"
  return 0
}
[ $WANT_CLAUDE = 1 ] && { verify claude "Claude Code" && RES_CLAUDE=ok || RES_CLAUDE=fail; }
[ $WANT_CODEX = 1 ]  && { verify codex "Codex" && RES_CODEX=ok || RES_CODEX=fail; }
[ "$CODEX_CFG" = fail ] && RES_CODEX=fail
if [ $WANT_PY = 1 ]; then
  pyout="$(cd /tmp && MPLBACKEND=Agg "$BIN_DIR/python" -W error::UserWarning -c "
import pandas, openpyxl, matplotlib.pyplot as plt, sys
fig, ax = plt.subplots(); ax.set_title('한글 그래프 확인 -1'); fig.savefig('/tmp/edm-hangul-check.png')
print(sys.version.split()[0], pandas.__version__)" 2>&1)"; pyrc=$?; pyver="$(echo "$pyout" | tail -n 1)"
  if [ $pyrc = 0 ]; then
    ok "파이썬 $(echo "$pyver" | cut -d' ' -f1) / pandas $(echo "$pyver" | cut -d' ' -f2) / 그래프 한글 정상"; RES_PY=ok
  else
    bad "파이썬·pandas 확인 실패"; say "$pyout" >>"$LOG"; RES_PY=fail
  fi
fi
if [ "$RES_KORDOC" = ok ]; then
  kv="$("$K_NODE" "$KORDOC_HOME/node_modules/kordoc/dist/cli.js" --version 2>/dev/null | head -n 1)"
  if [ -n "$kv" ]; then ok "kordoc  ${B}$kv${N}"; else bad "kordoc: 실행이 안 돼요"; RES_KORDOC=fail; fi
fi
node_now="$(PATH="$BIN_DIR:$PATH" command -v node 2>/dev/null)"
[ -n "$node_now" ] && ok "Node  ${B}$("$node_now" -v)${N} / npm $("$(dirname "$node_now")/npm" -v 2>/dev/null)" || bad "Node: 없음"

# ── 결과 ──────────────────────────────────────────────
say ""
say "${B}──────────────── 결과 ────────────────${N}"
[ -n "$RES_CLAUDE" ] && say "  Claude Code : $( [ "$RES_CLAUDE" = ok ] && echo "${G}성공${N}" || echo "${R}실패${N}" )"
[ -n "$RES_CODEX" ]  && say "  Codex       : $( [ "$RES_CODEX" = ok ] && echo "${G}성공${N}" || echo "${R}실패${N}" )"
[ -n "$RES_PY" ]     && say "  파이썬·pandas: $( [ "$RES_PY" = ok ] && echo "${G}성공${N}" || echo "${R}실패${N}" )"
[ -n "$RES_KORDOC" ] && say "  kordoc      : $( [ "$RES_KORDOC" = ok ] && echo "${G}성공${N}" || echo "${R}실패${N}" )"
[ "$GH_STATE" = blocked ] && say "  깃허브 연결 : ${Y}막힘 (이 와이파이)${N}"
say ""
if [ "$RES_CLAUDE" != fail ] && [ "$RES_CODEX" != fail ] && [ "$RES_PY" != fail ] && [ "$RES_KORDOC" != fail ]; then
  send_report ok
  if [ $REPAIR_ONLY = 1 ]; then
    say "  ${B}고칠 것을 다 고쳤어요.${N} 터미널 창을 닫고(⌘Q) 새로 연 다음 claude 나 codex 를 다시 실행해 보세요."
  else
    say "  ${B}이제 이 터미널 창을 닫고(⌘Q), 새로 연 다음${N} 아래를 입력하세요."
    [ $WANT_CLAUDE = 1 ] && say "     ${B}claude${N}"
    [ $WANT_CODEX = 1 ]  && say "     ${B}codex${N}"
    say ""
    say "  처음 실행하면 브라우저가 열리면서 로그인을 물어봅니다."
  fi
  say "  나중에 안 켜지면 같은 명령을 다시 붙여넣고 4번(고장 수리)을 고르세요."
  [ "${GIT_PENDING:-0}" = 1 ] && say "  ${Y}※ Git(개발자 도구) 설치 창이 끝날 때까지 기다려 주세요.${N}"
  [ -n "$REPORT_CODE" ] && say "  (설치 기록 접수번호: $REPORT_CODE)"
  exit 0
else
  say "  ${R}일부가 실패했어요.${N}"
  if send_report fail; then
    say "  강사에게 기록이 자동으로 전달됐어요. 강사에게 이 번호를 알려 주세요."
    say ""
    say "     접수번호:  ${B}${Y}$REPORT_CODE${N}"
  else
    say "  아래 기록 파일을 강사에게 보여 주세요."
    say "     $LOG"
  fi
  say ""
  say "  와이파이를 휴대폰 핫스팟으로 바꾸고 한 번 더 실행하면 대부분 해결됩니다."
  exit 1
fi
