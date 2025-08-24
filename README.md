# Artlink — 5-hour shipping contract for GitHub Copilot

### 제품 목표 (Product Goal)
배우와 크리에이티브를 위한 초직관 iOS 메모 앱. 학습 곡선 제로. 5시간 안에 출시(Ship). App Store 유료 선불(서버 無). AI는 사용자가 입력한 OpenAI 호환 API Key로만 동작하며 모든 데이터는 로컬에서만 흐름. (앱은 자체 서버 전송/수집 없음)

### 하드 제약 (Hard Constraints)
- 언어: Swift 5.9+ / SwiftUI, iOS 17 이상.
- 파일: Swift 소스 총 5개 이하(초과 금지). 서드파티 패키지 불가. 스토리보드 불가.
- 영속성: App Sandbox Documents 내 JSON 파일 1개. 변경 시 자동 저장(Autosave). Core Data 사용 금지.
- AI: 프로토콜 기반 서비스. 기본 구현 = OpenAI 호환 HTTPS(UrlSession 사용).
  - 사용자는 Settings에서 API Key 입력 → Keychain 저장.
  - 모델 응답은 JSON. 앱은 분석(analytics)이나 개인정보(PII) 전송 금지.
- 프라이버시: Privacy Manifest 포함 및 명확한 데이터 사용 문구. 추적(Tracking) 없음.
- UX: 리스트 화면 1개 + 에디터 시트 1개 + 최소 설정 화면. 큐(Cue) 모드에서 큰 글꼴.
- 접근성: Dynamic Type, VoiceOver 라벨, 고대비 친화.
- 다국어: 기본 영어. Placeholder/문구에 한국어 혼용 허용.
- 수익화: 유료(1회 구매). Day-1에 IAP 없음.

### 수용 기준 (Acceptance Criteria)
1) 런치 시 [All | Star] 세그먼트로 구분된 리스트. 검색 가능(.searchable). 각 아이템은 제목, 2줄 본문 요약, 상대적 날짜(relative date) 표시.
2) 탭하면 에디터 시트: 제목 필드 + 큰 본문(TextEditor). "Cue mode" 토글 시 폰트 확대.
3) 스와이프 액션: 즐겨찾기/해제(Star/Unstar), 삭제(Delete). 툴바: New, Settings.
4) 변경 후 300ms 내 자동 저장. `notes.json`에 저장. 부분 쓰기 실패 대비 → atomic write.
5) AI 도구 (오프라인-우선 UX):
	- "Suggest Title" → 48자 이하 간결 제목.
	- "Summarize for rehearsal" → logline + beat 목록(1~5 bullet).
	- "Extract Tags" → 최대 5개 해시태그.
	모든 AI 기능은 현재 노트 텍스트를 입력으로 사용. 응답 도착 즉시 렌더링. 네트워크 오류 시 사용자 친화적 우아한 강등.
6) Settings 화면:
	- API Key SecureField (Keychain 저장)
	- Model name TextField (기본값 `gpt-4o-mini` 수정 가능)
	- 온디바이스 프라이버시 안내 텍스트.
7) 파일 구성 ≤ 5 (정확한 파일명 고정):
	- `ActorNotesApp.swift` (앱 엔트리, 구조체명 ArtlinkApp)
	- `Models.swift` (Note, NotesStore, Keychain 헬퍼, 파일 IO)
	- `AIService.swift` (AIService 프로토콜 + OpenAIService 구현 + 스키마)
	- `ContentView.swift` (리스트/검색/별표/삭제/새로 만들기/설정)
	- `NoteEditorView.swift` (에디터 + AI 버튼)
8) 빌드 경고(Warning) 0. 네트워크/퍼시스턴스에 force unwrap 금지. 동시성은 async/await 사용.

### 구현 추가 가치 (Progress Beyond Baseline)
- Keychain 헬퍼 (API Key 저장/조회/삭제)
- Navigation push 기반 에디터 (sheet 제거)
- Zoom Summaries (Line / Key / Brief / Full) 휴리스틱 캐시
- Beats 추출(빈 줄/구분자) + 가로 스크롤 카드
- Monochrome 아티스트 톤 UI + Star 배지 오버레이
- Debounced autosave (300ms) + atomic write

### 아키텍처
에디터는 NotesStore에 변경을 전달하며, NotesStore는 JSON 저장/로드 담당. AIService는 에디터로부터 호출, Store에는 간접적으로(결과 적용 후) 반영.

### 데이터 모델 (Data Model)
Swift 구조체는 원문 코드와 동일. `isEmpty`는 제목+본문 트림 후 비었는지. `touch()`는 updatedAt 업데이트.
Persistence 상세:
- 파일 경로: Documents/notes.json
- 인코딩: JSONEncoder(.iso8601, .prettyPrinted, .sortedKeys)
- 쓰기: 스냅샷 복사 후 `data.write(.atomic)` (Task.detached)
- 로드 실패 시 샘플 2개 노트 시드(seed)

### AI 인터페이스 (예정 구현)
`AIService` (suggestTitle / rehearsalSummary / extractTags) + `RehearsalSummary`(logline, beats)
OpenAI 요구사항:
- Base URL: `/v1/responses`
- Headers: Bearer + JSON Content-Type
- JSON 모드 엄격 스키마
- 기본 모델: `gpt-4o-mini`
- Timeout 12s → 실패 시 휴리스틱 fallback (현재 로컬 요약/키워드 활용)

### JSON 출력 계약
- SuggestTitle: { "title": "..." } (≤48 chars)
- RehearsalSummary: { "logline": "...", "beats": [ ...1~5개 각각 ≤80자 ] }
- ExtractTags: { "tags": ["#tag", ...] } 최대 5개, 소문자, 공백 없음.

### 시스템 프롬프트 (System Prompts)
각 작업별 역할(role) 프롬프트를 요청 본문에 포함. 응답은 반드시 JSON만.

### UI 구현 디테일
- 리스트: NavigationStack + 세그먼트(All/Star) + .searchable
- 행(Row): 별표(채워진 아이콘) if starred, 제목 1줄, 본문 2줄, trailing 상대 시간
- 스와이프: 즐겨찾기 토글(노란), 삭제(파괴적)
- 에디터: 제목 TextField, Cue 모드 Toggle, 본문 TextEditor
- AI 버튼: [Suggest Title] [Rehearsal Summary] [Tags]
- 성공 후 적용 규칙:
  - 제목: 현재 제목이 비어 있을 때 자동 대체, 비어 있지 않으면 "Apply?" Alert로 확인
  - 요약: 본문 끝에 `\n---\n` 구분선 뒤 append
  - 태그: 본문 말미에 중복되지 않는 해시태그 append
- Settings: API Key SecureField, 모델 TextField, "Validate key" 버튼(테스트 API 호출)

### 비기능 요구사항
- 오류 처리: timeout, 401, 429 → 자연어 메시지. 크래시 금지.
- 접근성: 모든 인터랙티브 요소 .accessibilityLabel 지정, Dynamic Type 대응.
- 테스트 용이성: 트리밍, 태그 머지, 스키마 디코딩 등은 순수 함수 분리.

### 제외 범위 (What NOT to build)
- IAP, 푸시, Core Data, Analytics, Background fetch, 외부 패키지 모두 제외.

### 산출물 (Deliverables)
- 위 5개 Swift 파일
- 단색 플레이스홀더 AppIcon
- Privacy manifest + Info.plist 네트워킹 관련 문자열
- 사용자용 README (본 파일)

### 완료 정의 (Definition of Done)
- iOS 17 시뮬레이터 깨끗한 빌드/실행
- 생성/편집/별표/삭제/검색 정상 작동
- 유효한 키 시 AI 정상, 키 없으면 우아한 안내
- Swift 파일 수 5개, 경고 0, 강제 종료 후 재실행 시 데이터 유지

### 파일별 로컬 지시문 (Header Comments)
소스 5파일의 헤더 주석은 원문 그대로 사용(이미 README 상단에 존재). 구현 시 반드시 반영.

### Copilot Chat 즉시 사용 문장 (한국어 설명)
- 위 영어 문장을 그대로 전송하면 동일 동작, 필요 시 한국어 부연 가능.

### 출시 체크리스트 (한국어 재진술)
- Info.plist: ATS 기본 유지, Settings 내 간단 프라이버시 안내 문자열
- Privacy Manifest: 네트워크 접근 API 한 항목
- AppIcon: 단색 PNG placeholder
- 로컬라이제이션: Base English, 필요시 소규모 한국어 inline OK
- API 키 없으면 AI 버튼 Alert (크래시 금지)

### 남은 단기 실행 순서 (Revised)
1. AIService.swift 추가 (프로토콜 + 단일 request 기반 OpenAI wrapper)
2. Settings 시트 (API Key + Model + Validate ping)
3. 에디터 AI 버튼 활성 (idle/loading/error/done 상태, fallback 즉시 사용)
4. 결과 적용 UX (제목 충돌 Alert, summary append 구분선 검사, tag merge)
5. Privacy Manifest & AppIcon & 접근성 라벨 보강
6. 오류 피드백 (toast/banner) + QA 체크리스트 마무리

### 커밋 템플릿
원문 커밋 메시지 그대로 사용 가능(국문 주석 불필요). 필요시 한글 주석 추가해도 무방.

### OpenAI 요청 바디 예시 (설명 추가)
`/v1/responses` 사용 시 `input` 필드에 system+user 합성 문자열을 줄 수도 있고, messages 배열을 사용할 수도 있음. 선택한 한 방식만 일관 유지.

### 적용 가이드 추가 조언 (Enhancement Guidance)
1. Autosave Debounce: 300ms Throttle/Debounce 구현 시 `Task` 취소 토큰 또는 `DispatchWorkItem` 대신 `@MainActor` + `async let`/`sleep` 패턴 고려.
2. Atomic Save: 임시 파일(`notes.json.tmp`)에 쓰기 후 교체는 `Data.write(.atomic)`이 이미 보장.
3. 키체인 Helper: kSecClassGenericPassword, service = Bundle id or fixed string, account = "OPENAI_API_KEY".
4. 에러 도메인: NetworkError(enum) → case noAPIKey, unauthorized, rateLimited, timeout, decoding, emptyResponse, other(statusCode:Int)
5. AI 버튼 비활성 조건: API Key 없음 or 현재 본문 공백 (일부 기능). 대신 탭 시 Alert로 안내.
6. Tag Merge Logic: 기존 본문 끝부분에서 `#` 토큰 Regex 스캔하여 중복 제거 후 append.
7. Relative Date: `Text(note.updatedAt, style: .relative)` 사용.
8. Dynamic Type: TextEditor 내부 폰트 커스텀 시 `UIFont.preferredFont(forTextStyle:)` 또는 SwiftUI `.font(.body)` 유지.
9. Cue Mode: Editor 내 `@State var cueMode: Bool` → `.font(cueMode ? .title2 : .body)`.
10. Summary Append Separator 중복 방지: 이미 마지막 10~15자 내 `---` 존재 시 새로 추가 생략.

### 품질 점검 Quicklist
- [ ] 파일 수 5개 확인
- [ ] 빌드 경고 0
- [ ] notes.json 생성 및 재시작 복원
- [ ] Star 필터/검색 동시 적용
- [ ] AI 세 가지 기능 정상 (mock 키로 401 시 메시지)
- [ ] Dynamic Type 변경 시 레이아웃 수용
- [ ] VoiceOver 라벨 (Row, Star Toggle, New, Settings, AI buttons)
- [ ] 다국어 문자열 하드코딩 최소화 (필수 아님)