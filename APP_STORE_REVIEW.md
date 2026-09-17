# GrunnY App Store 제출 전 검토

검토일: 2026-09-18. 판정: **코드 보완 후, 실기기·배포 검증 대기**.

## 보완 결과 (같은 날)

- 공개 정책·지원 페이지 게시: https://grunny-support.wapples150.chatgpt.site
- 앱 첫 화면 정보 버튼에 개인정보처리방침, 웹 링크, 이메일 문의, 데이터 출처 연결.
- UserDefaults 사유 CA92.1을 선언한 PrivacyInfo.xcprivacy 추가.
- 기록 목록·개별/전체 삭제와 GPS 기록 삭제 추가.
- 마지막 회전을 지나면 같은 회전 안내를 유지하지 않도록 수정하고 GPS 갱신 중단 시 안내 만료 처리.
- 미션 판정에 따라 완료 제목 구분.
- 기본 주기 120초·빨간불 50% 가정을 결과 화면에 명시. 실제 신호 운영계획 자동 연결은 완료한 것이 아니다.
- 회귀 검사: 구간 페이스/미션, 길 안내/신선도, 기록 저장·삭제 통과.
- Release 빌드와 서명된 Archive 생성 성공. macOS 코드 서명 검증 통과. 빌드 및 Archive 안의 privacy manifest와 로컬 정책 파일 포함 확인.

아래는 수정 전 발견 사항과 출시 전 점검 근거다. 제출용 문구와 남은 항목은 APP_STORE_SUBMISSION.md를 참고한다.

코드와 Release 빌드를 검토했다. 심사 통과를 보장하는 인증이나 전체 실기기 QA가 아니다. 사용자는 개인정보처리방침 URL, 지원 URL, 앱 소개가 아직 없다고 확인했다. 이번 검토에서는 제품 코드를 수정하지 않았다.

## 1. 제출 전에 반드시 준비할 항목

### P1 — 개인정보처리방침 및 지원 페이지 없음

앱 내 정책·문의 링크가 없고 App Store Connect에 사용할 URL도 미준비다. 공개적으로 접근 가능한 정책 페이지와 지원 페이지를 만들고, 앱에서도 쉽게 열 수 있도록 연결해야 한다. 정책에는 위치 사용, 기기에 저장하는 러닝 기록, 지도 서비스에 전달하는 정보, 보관·삭제 방법과 연락처를 실제 동작에 맞게 기재한다. 운영자·연락처·URL은 임의로 만들지 않는다.

공식 요구 사항: [App Review 안내](https://developer.apple.com/app-store/review/), [심사 지침 1.5 및 5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/).

### P1 — Required Reason API 선언 누락

`GrunnY/ContentView.swift:7`부터 `@AppStorage`로 설정을 저장하지만 소스와 최종 Release 앱 번들 모두 `PrivacyInfo.xcprivacy`가 없다. UserDefaults 사용 사유를 선언해야 한다. 앱 자체 설정에만 사용하는 현재 용도에는 CA92.1을 검토하여 적용하고, 최종 Archive 안에 실제 포함됐는지 확인한다. 다른 required-reason API도 함께 확인한다.

공식 요구 사항: [UserDefaults 문서](https://developer.apple.com/documentation/Foundation/UserDefaults), [필수 사유 API 선언](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).

## 2. 핵심 기능 및 설명의 일치 여부

### P1 — 일반 사용자 흐름에서 신호 운영계획 수집이 연결되지 않음

`ContentView.swift:12–14`의 신호 행은 빈 배열, 운영계획은 nil, 도구 화면 표시 상태는 false로 시작한다. 도구 시트를 여는 true 대입 경로가 없다. `RouteSignalAssessment.swift:113`의 fallback은 수집한 주기가 없으면 120초를 사용한다. 따라서 현재 정상 앱 흐름의 주기 기반 추정은 기본 주기에 의존한다.

실제 운영계획을 앱 흐름에 연결하거나, 현행 기능을 기본 주기에 근거한 예상치로 명확히 설명해야 한다. 이 추정치를 실시간 신호 예측, 실제 절약 시간, 보장된 최적 코스로 소개하면 안 된다. 추정 기능 자체가 금지라는 뜻은 아니다. 코드의 기능과 설명이 일치하지 않는 것이 위험이다.

관련 기준: [정확한 메타데이터 및 기능 설명, 2.3](https://developer.apple.com/app-store/review/guidelines/).

### P1 — 최종 회전 이후에도 마지막 회전 안내가 남을 수 있음

`RunGuidance.swift:131–148`은 다음 안내가 없으면 마지막 안내를 다시 선택한다. 마지막 안내가 좌회전이고 그 뒤 긴 구간이 남으면 이미 지난 좌회전을 계속 표시할 수 있다. 또 다음 안내 선택에 `progress + 8`을 사용하므로 회전 지점 이전에 다음 지시로 넘어갈 수 있다. 최종 구간 유지 안내와 회전 통과 판정을 분리하고 합성 경로 및 실제 보행 경로에서 검증해야 한다. 이번 검토는 코드 경로 분석이며 현장 재현은 하지 않았다.

### P2 — GPS 갱신이 끊기면 이전 안내가 계속 보일 가능성

`LocationManager.swift:162–175`에서는 유효한 GPS 지점을 받을 때만 안내를 갱신한다. 위치가 더 이상 오지 않거나 계속 필터링되면 `RunGuidance.update` 안의 신선도 검사도 실행되지 않는다. 마지막 안내를 오래 유지하지 않도록 별도 신선도 확인과 위치 확인 중 상태 전환이 필요하다.

### P2 — 기록 저장 후 다시 보기·삭제 경로 없음

`RunRecord.swift:19–24`는 GPS 좌표가 포함된 JSON을 로컬에 저장한다. 앱에서 저장 기록을 다시 읽거나 삭제하는 흐름은 찾지 못했다. 저장 안내에 맞는 최소 기록 확인·삭제 기능 또는 보관 방침이 필요하다. 계정이 없는 앱이므로 계정 삭제 의무를 이 문제에 그대로 적용하는 것은 아니다.

추가로 `GrunnYDesign.swift:263`은 미션 실패·수동 종료에도 성공처럼 읽히는 제목을 고정 표시한다. 실제 완료 판정에 맞게 문구를 구분하는 편이 정확하다.

## 3. 완료한 검증과 남은 제출 검증

- Release / generic iOS device / 코드 서명 제외 빌드 성공. 로그: `/tmp/GrunnY-release-audit.log`.
- 최종 빌드 앱에서 privacy manifest 부재 확인.
- 서명된 Archive, Organizer Validate, App Store Connect 업로드 검증은 하지 않았다. 빌드 성공과 업로드·심사 통과는 별개다.
- 실기기 실행·설치·현장 러닝은 이번 검토에서 하지 않았다.
- 프로젝트는 iPhone과 iPad 모두 대상으로 한다. iPad와 선언된 화면 방향도 확인하거나 지원 범위를 의도에 맞게 조정해야 한다.

제출 직전에는 새 설치 상태에서 다음 흐름을 실기기로 확인한다.

1. 위치 허용·거부·정확한 위치 해제 각각에서 검색과 오류 복구가 가능한지.
2. 서울 출발지 검색 → 코스 1개/2개/대체 코스 → 선택 → 3·2·1 → 러닝 중 화면이 유지되는지.
3. 네트워크 단절·경로 미제공 때 무한 로딩이나 빈 결과에 갇히지 않는지.
4. 화면 잠금 중 GPS 기록·방향 음성, 음악 재생 중 음성, 1km 구간 안내가 작동하는지.
5. 경로 이탈 30초 간격 총 3회, 안내 종료 후에도 기록 유지, 복귀 안내 조건이 맞는지.
6. 순환 코스 시작 직후 자동 종료되지 않고 실제 도착에서만 종료되는지. 목표 거리만 달성했을 때 계속 기록하는지.
7. 수동 종료·자동 종료·저장 실패 복구·완료 후 첫 화면 복귀가 정상인지.

공식 완성도 기준: [심사 지침 2.1](https://developer.apple.com/app-store/review/guidelines/).

## 4. App Store Connect 준비

- 개인정보처리방침 URL과 실제 문의 가능한 지원 URL.
- 실제 배포 앱으로 촬영한 스크린샷과 기능에 맞는 소개.
- App Privacy 응답: 위치와 운동 기록의 실제 전송·보관 구조를 확인한 뒤 작성한다. 로컬 저장만으로 곧바로 Apple의 ‘수집’에 해당한다고 단정하지 않는다. [공식 개인정보 표기 안내](https://developer.apple.com/app-store/app-privacy-details/).
- 심사 메모: 서울 지역 서비스임을 설명하고, GPS가 서울 밖이어도 출발지를 검색해 코스를 확인할 수 있는 절차와 검증한 검색 예시를 제공한다. 미검증 예시를 작성하지 않는다.
- 배경 위치·음성 사용 목적을 심사 메모에 설명한다. 러닝 중 위치 기록과 음성 안내는 실제 기능에 부합하므로 백그라운드 모드 자체를 무조건 삭제할 필요는 없다.
- 외부 횡단보도·신호 데이터의 배포 조건과 출처 표시를 확인한다. 이번 검토로 데이터 이용 권리 전체가 검증된 것은 아니다.

## 권장 처리 순서

1. 정책·지원 페이지 및 앱 진입점, privacy manifest 준비.
2. 안내 상태 문제 수정, 신호 추정 설명과 실제 연결 상태 일치.
3. 실기기 전체 흐름 확인 및 저장 기록 처리 정리.
4. 서명 Archive → Validate → TestFlight 확인 → 메타데이터 최종 대조 → 제출.

심사 결과나 처리 시간은 보장할 수 없다. 현재 확인된 누락을 그대로 두고 급히 제출하는 것은 권하지 않는다.

배포 결과: Xcode 자동 프로파일 갱신 후 App Store 배포용 IPA 내보내기 성공. 보관 위치: `build/AppStore/GrunnY.ipa`, `build/AppStore/GrunnY.xcarchive`. 심사 제출·App Store Connect 최종 Validate는 미실행.
