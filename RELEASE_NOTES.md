# 돈꼬마트 릴리즈 노트

DeployBar 가 배포할 때 이 파일에서 '이 버전의 새로운 기능' 을 읽어 간다.
`### 앱스토어 (언어)` 절만 스토어로 나가고, `### 개발 메모` 절은 나가지 않는다.
확인: `DeployBar --reponotes 돈꼬마트 2.0.7`

## 2.0.7

### 앱스토어 (한국어)

알림이 설정한 시각에 정확히 옵니다.
전날 장보기 알림이 빠지지 않습니다.
위젯 이름과 설명이 한국어로 나옵니다.
설정에서 문의하고 리뷰를 남길 수 있어요.
개인정보 처리방침과 지원 페이지를 앱에서 엽니다.

### App Store (English)

Alerts now arrive at the exact time you set.
The day before shopping alert is no longer skipped.
The app is now fully translated into English.
Send feedback and leave a review from Settings.
Open the privacy policy and support page in the app.

### 개발 메모 (노출 안 함)

- 알림 시각 기본값 버그: `UserDefaults.integer(forKey:)` 가 미저장 키에 0 을 돌려주는데
  `?? 9` 로는 걸리지 않아, 설정 화면은 09:00 을 보여주면서 실제 알림은 00:00 에 갔다.
  `object(forKey:) != nil` 로 저장 여부를 먼저 확인하도록 수정.
- 전날 알림 토글도 같은 문제: `bool(forKey:)` 가 미저장 시 false → 화면은 켜짐인데 미발송.
- iOS 알림 64개 상한: 넘긴 분량을 OS 가 조용히 버려 '가끔 안 온다' 로 보였다.
  가까운 날짜부터 60개까지만 등록하고 나머지는 다음 실행 때 다시 채운다.
- `DontGoMartSpec.appStoreID` 선언 → 설정의 '리뷰 남기기' 가 시스템 팝업 대신
  실제 리뷰 작성 페이지로 간다.
- App Store ID 오타: `6450679498` 은 존재하지 않는 앱이었다(실제는 `6450387984`).
  ReviewManager 의 '리뷰 작성'·'앱스토어 열기' 가 그동안 죽은 링크로 갔다.
- LeeoKit 2.6.0 → 3.7.1. 계약이 `legal`·`monetization` 을 강제해 Spec 을 다시 썼다
  (`.free` + 개인정보·지원 링크). 옛 커피 권한 조회용 페이월 구성은 SupporterManager 로 옮겼다.
- 다국어: 영어가 빠져 있던 84개 문자열 번역(후원·공유·커스텀 마트·접근성 라벨),
  위젯 갤러리 이름·설명 8개 한국어 추가, 영어 13건 `needs_review` → `translated`.

## 2.0.6

### 앱스토어 (한국어)

후원하면 그 자리에서 감사 인사가 나타나요.
후원해주신 분께는 가끔 다시 인사를 전해요.
안정성을 다듬었습니다.

### App Store (English)

A thank-you appears the moment you send support.
Supporters hear from us again once in a while.
Stability improvements.

## 2.0.5

### 앱스토어 (한국어)

후원하기가 열리지 않던 문제를 고쳤어요.
나만의 마트를 고를 때 생기던 오류를 고쳤어요.

### App Store (English)

Fixed support options that would not load.
Fixed an error when choosing your own store.

## 2.0.4

### 앱스토어 (한국어)

휴무 소식을 예쁜 카드 이미지로 공유할 수 있어요.
2주 넘게 남은 휴무일도 몇 주 뒤인지 바로 보여요.
개발자를 응원할 수 있는 방법이 생겼어요.

### App Store (English)

Share closure news as a clean card image.
Closures more than two weeks out now show how far away they are.
You can now support the developer.
