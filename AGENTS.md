# Lines

Lines는 강의 자료 위에 잠깐 필기한 뒤 발표로 돌아가는 macOS 메뉴 막대 앱이다. 사용법과 단축키는 `README.md`에 있다.

## 커밋 메시지

Conventional Commits 형식을 사용한다. `feat`, `fix`, `docs`처럼 변경에 맞는 유형 뒤에 콜론과 공백을 쓰고, 제목과 필요한 본문은 한국어로 작성한다. 예시 제목은 `fix: 텍스트 상자 배경을 투명하게 변경`이다.

## 빌드와 실행

- macOS 14 이상과 Xcode Command Line Tools를 사용한다. 프로젝트 루트에서 `make`를 실행하면 Swift 소스를 컴파일하고 `Lines.app`을 로컬 서명한다.
- `make run`으로 실행한다. 이전 버전이 이미 실행 중이면 필기를 마치고 메뉴 막대에서 **Lines 종료**를 선택한 뒤 새 빌드를 연다.
- 번들 서명은 `codesign --verify --deep --strict Lines.app`으로 확인한다. `Lines.app/`과 `.build/`는 로컬 빌드 산출물이다.

## 코드 위치

- `Sources/main.swift`는 AppKit 이벤트 루프를 시작한다.
- `Sources/AppDelegate.swift`는 메뉴 막대, Carbon 전역 단축키, 포인터가 있는 디스플레이의 필기 창 수명과 키보드 이벤트 모니터를 관리한다.
- `Sources/Canvas.swift`의 `InkPanel`은 필기 단축키를 처리하고, `InkCanvas`는 각 획의 경로·색상과 실행 취소 기록을 관리한다.
- `Sources/InkToolbar.swift`는 화면 상단의 펜·레이저 전환, 캡처, 실행 취소, 종료 버튼을 표시한다.
- `Sources/InkStroke.swift`는 드래그 좌표 사이의 곡선과 포인터까지의 마지막 구간을 그린다.
- `Sources/LaserPointerView.swift`는 필기 기록과 별도로 움직임을 따라가는 레이저 점과 꼬리를 그린다.
- `Sources/ScreenCapture.swift`는 ScreenCaptureKit으로 선택한 디스플레이를 캡처하고 필기와 합성해 PNG로 저장한다.
- `Sources/PenPalette.swift`는 색상 선택 메뉴와 마지막 색상의 UserDefaults 저장을 담당한다.
- `Sources/Shortcuts.swift`는 단축키 기본값·저장·입력 매칭을, `Sources/ShortcutSettings.swift`는 설정창과 키 입력을 담당한다.

## 동작 확인

필기나 창 동작을 변경하면 발표 앱을 앞에 둔 상태에서 다음 흐름으로 확인한다.

1. `⌥ Option`과 백틱으로 펜을 켜고 빨강과 파랑으로 한 획씩 그린다. 두 색이 그대로 보여야 한다.
2. `⌘Z`로 파란 획만 취소한다. `Delete`로 빨간 획을 지우고 다시 `⌘Z`를 누르면 빨간 획이 복원되어야 한다.
3. `Esc`로 필기를 마치고 바로 방향키로 슬라이드를 넘긴다. 다시 펜을 켰을 때 캔버스는 비어 있어야 한다.

창의 레벨이나 좌표 처리를 바꿀 때는 전체 화면 발표와 외부 디스플레이에서도 확인한다.
