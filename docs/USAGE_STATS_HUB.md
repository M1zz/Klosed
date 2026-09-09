# 사용 통계·피드백 허브 (FeedbackHub)

앱이 실제로 쓰이는지 **앱 안에서** 확인하기 위한 장치. 익명 사용 통계와 사용자 피드백을
같은 CloudKit 컨테이너(`iCloud.com.Ysoup.FeedbackHub`, public DB)에 쌓고,
설정 ▸ 지원 ▸ 사용 통계에서 그대로 읽는다. 별도 서버 없음, 외부 분석 SDK 없음.

- 전송·조회 엔진: LeeoKit `LeeoUsageReporter` / `LeeoUsageStatsView` (핀: **3.7.1**, upToNextMajor)
- 계약: `DontGoMart/DontGoMartSpec.swift` (`LeeoAppSpec`)
- 앱 정책(무엇을 언제 보낼지): `DontGoMart/Manager/UsageReporter.swift` (`AppUsage`)
- 조회 화면: 설정 ▸ 지원 ▸ **사용 통계 (개발자)** — 마스터 모드에서만 보인다

## 무엇을 보내나

| 레코드 | 언제 | 내용 |
|---|---|---|
| `UsageSnapshot` | 앱을 열 때, 설치당 1건 upsert (12시간 쓰로틀) | 익명 설치 UUID, 앱 버전·플랫폼·OS·로케일, 실행 횟수, 주요 행동 수, 설치 후 경과일, 마지막 활동 시각, `metrics` JSON |
| `UsageEvent` | 주요 행동 시, **이름당 6시간에 1건** | 이벤트 이름, 앱 버전·플랫폼, 익명 설치 UUID, 발생 시각(`occurredAt`) |
| `Feedback` | 사용자가 피드백을 보낼 때 | LeeoKit 표준 피드백 (유형·내용·연락처는 사용자가 적은 것만) |

`metrics` — 설치당 대략 지표, 전부 숫자:

| 키 | 뜻 | 왜 보나 |
|---|---|---|
| `marts` | 추적 중인 마트 수 | 0이면 설치만 하고 설정을 안 한 사람이다. 이 앱의 첫 관문 |
| `customMarts` | 직접 만든 마트 수 | '나만의 마트' 가 실제로 쓰이는 기능인지 |
| `notification` | 휴무 알림 켬(1/0) | 이 앱의 핵심 가치가 알림이라, 켠 비율이 곧 효용 지표 |
| `leadDays` | 며칠 전 알림 (알림 켠 경우만) | 기본값 3일이 맞는지 |
| `beforeDay` | 전날 '장보기 좋은 날' 알림 켬(1/0) | 기본 켜짐이 성가신지 |
| `tips` | 누적 후원 횟수 | 후원자 비율 (대부분 0이다) |

**보내지 않는 것**: 이름, 이메일, 선택한 마트가 무엇인지, 커스텀 마트 이름,
기기 식별자(IDFA/IDFV), 위치. 설치 식별은 LeeoKit 이 만든 무작위 UUID(`leeo.usage.installID`)
하나뿐이고, 앱을 지웠다 깔면 새 값이 된다.

**옵트아웃 없음**: 사용자가 끄는 설정은 두지 않는다. 그래서 보내는 항목을 늘릴 때는
"이게 정말 익명 집계 수치인가" 를 더 엄격히 따져야 하고, App Privacy 설문과
개인정보 처리방침에 수집 사실이 정확히 적혀 있어야 한다.

## 이벤트는 어디서 나오나

`AppUsage.log(_:)` 를 각 행동 지점에서 직접 부른다. 지금 배선된 곳:

| 이벤트 | 위치 | 뜻 |
|---|---|---|
| `share` | `ClosedDaysView` 공유 버튼 | 휴무 소식이 밖으로 나간 순간 — 이 앱의 aha 지점 |
| `calendar` | `ClosedDaysView` 캘린더 버튼 | 달력까지 들어가 본 사람 |
| `mart_changed` | `SettingsView` 마트 토글 | 설정을 실제로 손봤다 |
| `custom_mart_saved` | `CustomMartEditView.saveMart()` | 나만의 마트를 만들었다 |
| `notification_on` | `SettingsView` 알림 켬(권한 승인 후) | 핵심 가치를 켠 순간 |
| `tip` | `CoffeeTipStore.celebrate()` | 후원 완료 |

이벤트 이름은 `AppUsage.Event` 에서만 정의한다. 호출부에 문자열을 적으면
오타 하나가 대시보드에서 별개 이벤트가 된다.

⚠️ 이벤트에 **6시간 쓰로틀**이 걸려 있어 건수는 실제보다 작다. 절대 건수 대신
"설치 몇 곳이 하는가" 와 단계 사이 비율을 본다.

## 무엇을 보고 판단하나

1. **첫 관문** — `marts` 가 0인 설치 비율. 설치는 늘어도 이 비율이 안 줄면
   온보딩이 없어서 사람들이 설정을 못 찾고 있는 것이다.
2. **핵심 가치** — `notification` 이 1인 설치 비율. 이 앱은 알림이 값의 전부라
   이 숫자가 곧 효용이다.
3. **확산** — `share` 를 한 설치 비율. 이 앱은 광고를 안 하므로 유일한 유입 경로다.
4. **버전 분포** — 옛 버전이 오래 남아 있으면 버그 수정이 안 퍼지고 있다는 뜻.
5. **피드백** — 숫자가 왜 그런지는 결국 사람이 적어 준 문장에 있다.

## CloudKit Dashboard 준비 (1회, 사람이 해야 함 — 아직 안 함)

https://icloud.developer.apple.com → `iCloud.com.Ysoup.FeedbackHub`

0. **Apple Developer 포털**: App ID `com.leeo.DontGoMart` 의 iCloud 컨테이너에
   `iCloud.com.Ysoup.FeedbackHub` 가 들어 있는지 확인하고 프로비저닝 프로파일을 갱신한다.
   (엔타이틀먼트에는 이미 있다 — 포털 쪽이 안 맞으면 서명이 실패한다.)
1. **스키마 생성**: Development 환경에서 앱을 한 번 실행하면 `UsageSnapshot` 이,
   주요 행동을 한 번 하면 `UsageEvent` 가 자동 생성된다. 피드백도 한 번 보내 `Feedback` 을 만든다.
2. **인덱스**:
   - `UsageSnapshot`: `recordName` **Queryable**
   - `UsageEvent`: `recordName` **Queryable** + `createdTimestamp` **Sortable**
     (`occurredAt` 은 값만 저장하고 인덱스는 두지 않는다 — 지금은 조회에 안 쓴다)
   - `appId` 는 인덱스 없이 클라이언트에서 필터한다(인덱스 배포를 늘리지 않으려고).
3. **Security Roles**: `_world` 는 create 만, read 제거.
   admin 역할에 read + 개발자 본인 userRecordName 등록.
4. **Production 배포**: Schema → Deploy Schema Changes to Production.

배포 전에는 통계 화면이 "불러오지 못했어요 / read 권한 필요" 안내를 보여준다(정상).

### 🚨 순서 주의 — Production 스키마는 잠겨 있다
레코드 타입에 없는 필드를 담아 저장하면 **그 저장이 통째로 실패한다.**
`metrics` 처럼 새 필드를 쓰는 빌드를 심사에 올리기 **전에** Development 에서 필드를 만들고
Production 에 배포할 것. 순서가 뒤집히면 그 기간의 스냅샷은 복구되지 않는다.

## App Store 제출 시

익명 사용 데이터를 수집하므로 **App Privacy 설문**을 갱신해야 한다:

- Data Type: *Product Interaction* (Usage Data) — 목적 Analytics,
  **사용자와 연결되지 않음**, 추적(Tracking) 아님(ATT 불필요).
- 피드백에 사용자가 직접 적은 이메일·이름이 들어갈 수 있다 → *Contact Info*, 목적 Customer Support.
- 개인정보 처리방침(`docs/privacy.html`)에 수집 항목·목적·보관을 명시했는지 확인할 것.
  앱 안에 끄는 스위치가 없으므로 그 문구가 유일한 고지 수단이다.

## 마스터 모드

설정 ▸ 지원 ▸ **버전 행을 7번 탭**하면 켜진다(`dev.masterMode`). 켜지면:

- **접수된 피드백 (개발자)** — LeeoKit 인박스
- **사용 통계 (개발자)** — `LeeoUsageStatsView`

같은 방법으로 다시 7번 탭하면 꺼진다. 사용자에게 노출되는 UI가 아니다.

## LeeoKit 판올림

3.7.1 로 올리면서 계약(`LeeoAppSpec`)이 `legal`·`monetization` 선언을 강제하게 됐다.
`DontGoMartSpec` 은 `.free` + 개인정보·지원 링크로 선언했고, 옛 커피 권한 조회용
`LeeoPaywallConfig` 는 Spec 이 아니라 `SupporterManager` 안에서 만든다 —
무료 모델인데 페이월을 선언하면 Preflight 가 모순으로 잡는다.

계약이 어긋나면 `DontGoMartTests.specIsReleasable()` 이 실패한다. 다음에 LeeoKit 을
올릴 때 이 테스트부터 보면 된다.

⚠️ 이벤트 쓰로틀은 여전히 앱(`AppUsage`)이 건다. LeeoKit 리포터는 스냅샷만
12시간으로 제한하고 이벤트는 부르는 대로 보낸다.
