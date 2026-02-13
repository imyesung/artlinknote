# Artlink

배우와 크리에이터를 위한 iOS 메모 앱.
모든 데이터는 기기에서만 저장되며 외부 서버와 통신하지 않습니다.

## Features

### Note Management
- 노트 생성 / 편집 / 삭제 / 복제
- 즐겨찾기(Star) 필터 (All / Star)
- 제목 + 본문 실시간 검색
- 자동 저장 (300ms debounce, atomic write)
- 상대 시간 표시 (방금, 5분 전 등)

### Smart Zoom (4 Levels)
| Level | 설명 |
|-------|------|
| **Keywords** | 핵심 키워드 + 해시태그 그리드 |
| **Line** | 대표 문장 1줄 |
| **Brief** | 핵심 문장 3개 요약 |
| **Full** | 전체 본문 편집 |

모든 요약 및 키워드 추출은 **온디바이스 휴리스틱**으로 동작합니다.
네트워크 연결이 필요 없습니다.

### Keyword & Beat Extraction
- TF-IDF 기반 키워드 추출 (한국어/영어 불용어 필터링)
- 연기/창작 도메인 키워드 부스팅 (감정, 캐릭터, 동기, scene, beat 등)
- 본문 구조 분석을 통한 비트(Beat) 추출
- 해시태그 자동 인식 및 표시

### Privacy
- 모든 노트는 기기 로컬(`Documents/notes.json`)에만 저장
- 외부 서버 전송 / 수집 / 추적 없음
- Privacy Manifest 포함

## Tech Stack

| 항목 | 사양 |
|------|------|
| Language | Swift 5.9+ |
| UI | SwiftUI |
| Target | iOS 17.0+ |
| Persistence | JSON (Documents directory) |
| Dependencies | 없음 (서드파티 패키지 0개) |

## Project Structure

```
artlinknote/
├── ActorNotesApp.swift      # 앱 엔트리 포인트
├── Models.swift             # Note 모델, NotesStore, Keychain 헬퍼, 휴리스틱
├── AIService.swift          # AI 서비스 프로토콜 + 휴리스틱 fallback
├── ContentView.swift        # 노트 리스트, 검색, 설정
├── NoteEditorView.swift     # 에디터, 줌 레벨, 키워드 표시
├── Assets.xcassets/         # 앱 아이콘, 색상
└── PrivacyInfo.xcprivacy    # Privacy Manifest
```

Swift 소스 파일 5개 이하 제약을 유지합니다.

## Build & Run

1. `artlinknote.xcodeproj`를 Xcode에서 열기
2. iOS 17+ 시뮬레이터 또는 실기기 선택
3. Build & Run (서드파티 의존성 없으므로 별도 설치 불필요)

## Roadmap

- [ ] AI 챗봇 연동 (서버사이드 프록시 방식 검토 중)
- [ ] Cue 모드 확장 (리허설 전용 UI)
- [ ] 다국어 지원 강화

## License

All rights reserved.
