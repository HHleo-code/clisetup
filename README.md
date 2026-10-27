# edmakers AI 도구 설치기

Claude Code · Codex 를 한 줄로 설치합니다. Node·Git 까지 같이 맞춰 두고, 수업에서 자주 막히던 문제(옛 npm 설치 충돌, 권한, PATH, 실행 정책)를 설치 전에 자동으로 고칩니다. 관리자 권한은 필요 없습니다.

## 맥 — '터미널'에 붙여넣기

```
curl -fsSL edm.run/mac | bash
```

## 윈도우 — PowerShell 에 붙여넣기 (시작 메뉴에서 "PowerShell" 검색)

```
irm edm.run/win | iex
```

실행하면 두 가지를 묻습니다.

1. 어떤 컴퓨터인가요? (맥 / 윈도우)
2. 무엇을 설치할까요? (Claude Code / Codex / 둘 다)

설치가 끝나면 창을 닫고 새로 연 뒤 `claude` 또는 `codex` 를 입력하세요.
문제가 생기면 홈 폴더의 `edm-설치기록.txt` 를 강사에게 보여 주세요.
