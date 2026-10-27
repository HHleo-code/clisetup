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

: >"$LOG"
say "edmakers 설치기록 — $(date '+%Y-%m-%d %H:%M:%S')"
say "맥OS $(sw_vers -productVersion 2>/dev/null) / $(uname -m) / 사용자 $(whoami)"

clear 2>/dev/null || true
cat <<EOF

${B}  ┌──────────────────────────────────────────┐
  │   edmakers  AI 도구 설치기               │
  │   Claude Code · Codex 를 한 번에          │
  └──────────────────────────────────────────┘${N}

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
os_pick="$(ask '   번호를 누르고 엔터 (그냥 엔터 = 1): ')"
say "   선택: ${os_pick:-1}"

if [ "$os_pick" = "2" ]; then
  say ""
  say "  이 컴퓨터는 ${B}${HERE}${N}이에요. 윈도우 컴퓨터라면 그쪽에서 아래 한 줄을 붙여넣으세요."
  say ""
  say "     ${B}${WIN_CMD}${N}"
  say ""
  cont="$(ask "  이 ${HERE} 컴퓨터에 계속 설치할까요? (엔터 = 예, n = 그만): ")"
  case "$cont" in n|N|no|아니오|아니요) say "  설치를 멈췄습니다."; exit 0 ;; esac
fi

# ── 2단계: 무엇을 설치할지 ─────────────────────────────
say ""
say "${B}[2단계] 무엇을 설치할까요?${N}"
say "   1) Claude Code"
say "   2) Codex"
say "   3) 둘 다"
pick=""
while :; do
  pick="$(ask '   번호를 누르고 엔터: ')"
  case "$pick" in 1|2|3) break ;; "") pick=3; break ;; esac
  say "   1, 2, 3 중에서 골라 주세요."
done
WANT_CLAUDE=0; WANT_CODEX=0
case "$pick" in 1) WANT_CLAUDE=1 ;; 2) WANT_CODEX=1 ;; 3) WANT_CLAUDE=1; WANT_CODEX=1 ;; esac
say "   선택: $( [ $WANT_CLAUDE = 1 ] && printf 'Claude Code ' )$( [ $WANT_CODEX = 1 ] && printf 'Codex' )"

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
NET_OK=1
[ $WANT_CLAUDE = 1 ] && { check_net "https://downloads.claude.ai/claude-code-releases/latest" "Claude" || NET_OK=0; }
[ $WANT_CODEX = 1 ]  && { check_net "https://chatgpt.com/codex/install.sh" "Codex" || NET_OK=0; }
[ $NET_OK = 1 ] || exit 1

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

RES_CLAUDE=""; RES_CODEX=""
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
node_now="$(PATH="$BIN_DIR:$PATH" command -v node 2>/dev/null)"
[ -n "$node_now" ] && ok "Node  ${B}$("$node_now" -v)${N} / npm $("$(dirname "$node_now")/npm" -v 2>/dev/null)" || bad "Node: 없음"

# ── 결과 ──────────────────────────────────────────────
say ""
say "${B}──────────────── 결과 ────────────────${N}"
[ -n "$RES_CLAUDE" ] && say "  Claude Code : $( [ "$RES_CLAUDE" = ok ] && echo "${G}성공${N}" || echo "${R}실패${N}" )"
[ -n "$RES_CODEX" ]  && say "  Codex       : $( [ "$RES_CODEX" = ok ] && echo "${G}성공${N}" || echo "${R}실패${N}" )"
say ""
if [ "$RES_CLAUDE" != fail ] && [ "$RES_CODEX" != fail ]; then
  say "  ${B}이제 이 터미널 창을 닫고(⌘Q), 새로 연 다음${N} 아래를 입력하세요."
  [ $WANT_CLAUDE = 1 ] && say "     ${B}claude${N}"
  [ $WANT_CODEX = 1 ]  && say "     ${B}codex${N}"
  say ""
  say "  처음 실행하면 브라우저가 열리면서 로그인을 물어봅니다."
  [ "${GIT_PENDING:-0}" = 1 ] && say "  ${Y}※ Git(개발자 도구) 설치 창이 끝날 때까지 기다려 주세요.${N}"
  exit 0
else
  say "  ${R}일부가 실패했어요.${N} 아래 기록 파일을 강사에게 보여 주세요."
  say "     $LOG"
  say "  와이파이를 휴대폰 핫스팟으로 바꾸고 한 번 더 실행하면 대부분 해결됩니다."
  exit 1
fi
