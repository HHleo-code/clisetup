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

실행하면 세 가지를 묻습니다.

1. 어떤 컴퓨터인가요? (맥 / 윈도우)
2. 무엇을 설치할까요? (Claude Code / Codex / 둘 다 / **이미 깔았는데 안 켜져요 = 고장 수리만**)
3. 파이썬(3.13 · pandas · openpyxl · matplotlib)도 설치할까요? (기본 예)

설치가 끝나면 창을 닫고 새로 연 뒤 `claude` 또는 `codex` 를 입력하세요.

- 끝나면 설치 기록을 강사에게 자동으로 보내고 **접수번호**를 보여 줍니다 (홈 경로·사용자 이름은 가림). 안 보내려면 `EDM_NO_REPORT=1`.
- Codex 설정 파일(`~/.codex/config.toml`)이 깨져서 안 켜지면 자동으로 고칩니다 (원본은 `config.toml.edm-backup-날짜` 로 남김).
- Codex 가 작업 중에 인터넷(깃허브·설치 명령)을 쓸 수 있게 엽니다. 작업 폴더 밖 쓰기 금지는 그대로입니다.
- 기록 파일은 홈 폴더의 `edm-설치기록.txt` 에도 남습니다.
