# GrunnY 1.0 제출 자료

## 공개 URL

- 지원 URL: https://grunny-support.wapples150.chatgpt.site
- 개인정보처리방침 URL: https://grunny-support.wapples150.chatgpt.site/privacy.html
- 운영자: 최서진
- 문의: seojin060504@gmail.com

## 한국어 메타데이터 초안

앱 이름: GrunnY
부제: 서울 러닝 코스와 페이스 기록
키워드: 러닝,달리기,서울,코스,페이스,운동,거리,음성안내
카테고리 제안: 건강 및 피트니스
저작권: 2026 최서진

### 앱 설명

어디서 얼마나 달릴지 정하고, 나에게 맞는 서울 러닝 코스를 찾아보세요.

• 서울의 장소를 검색하거나 지도에서 출발지를 선택해요.
• 목표 거리와 페이스를 정하고 코스를 비교해요.
• 러닝 중 이동 거리, 시간과 페이스를 확인해요.
• 방향 안내와 1km 구간 페이스를 음성으로 들어요.
• 완료한 러닝 기록을 기기에 저장하고, 기록 화면에서 확인하거나 삭제해요.

신호 대기는 주변 횡단보도 자료와 주기 가정으로 계산한 예상치입니다. 주기 정보가 없는 경우 120초, 빨간불 비율은 50%로 가정합니다. 실제 신호 상태, 실제 횡단 횟수 또는 절약 시간을 보장하지 않습니다. 도로에서는 현장의 신호와 통행 상황을 확인해 주세요.

장소 검색과 경로 생성에는 인터넷 연결이 필요합니다. GPS 기반 기록·안내에는 위치 권한이 필요하며, 러닝 중에는 화면이 잠겨도 위치를 사용합니다. 지도 서비스의 보행 경로 제공 여부에 따라 코스를 찾지 못하거나 목표 거리와 다른 대체 코스가 나올 수 있습니다.

### 심사 메모 초안 (영어)

GrunnY is a running route and activity recording app focused on Seoul, South Korea. No account or login is required. Search for a Seoul location on the first screen to preview routes even when the device is outside Seoul. Choose a starting point, continue to distance/pace settings, search for a course, and select a result. A countdown precedes the running session. GPS recording requires location permission and movement along the selected route.

Background location and audio are used only to support an active running session and spoken guidance. Ending the run stops continuous location updates. Saved running records can be reviewed and deleted from the information button on the first screen. The same screen provides our privacy policy, public support link and support email.

Signal waiting times are heuristic estimates, not live traffic signal predictions. When cycle data is unavailable, a 120-second cycle and a 50% red-light ratio are assumed. The UI discloses this limitation. Nearby crossings are not a guarantee of the exact crossings traversed.

Review contact: 최서진 / seojin060504@gmail.com

## App Privacy 작성 근거

앱은 계정·광고·추적·분석 SDK 및 운영자 서버 업로드가 없다. 러닝 기록은 기기에 보관한다. Apple의 정의상 기기 내에서만 처리하는 정보는 수집 항목에 해당하지 않는다. 지도 검색·경로·주소 확인은 Apple 서비스를 사용하며 해당 서비스의 개인정보 처리와 구분해 검토한다. 선택적 이메일 문의는 사용자가 직접 보내며 회신에만 사용한다. 향후 서버·분석 도구 추가 시 응답과 정책을 갱신해야 한다.

이 문서는 App Store Connect에 응답을 제출한 결과가 아니다. 계정 화면에서 실제 질문, 선택적 지원 문의 예외 및 최종 배포 SDK를 대조해야 한다.

근거: https://developer.apple.com/app-store/app-privacy-details/
Apple 지도 안내: https://www.apple.com/legal/privacy/data/en/apple-maps/

## 아직 제출을 완료하지 않은 항목

- 실제 기기에서 새 설치·카운트다운·러닝·화면 잠금·음성·도착 종료 검증.
- 지원 기기(iPhone/iPad)와 방향별 레이아웃 및 실제 앱 스크린샷 준비.
- 서명 Archive 생성 및 코드 서명 검증 완료: `/tmp/GrunnY-AppStore.xcarchive`. App Store Connect Validate와 업로드는 아직 하지 않았다.
- App Store Connect 개인정보·연령 등급·수출 규정·심사 연락처 전화번호 등 계정별 항목 입력.
- 외부 데이터의 현행 이용 조건 최종 확인.

정책 웹페이지 게시와 Release 빌드 성공은 App Store 제출 또는 심사 승인과 다르다.

배포 결과: Xcode 자동 프로파일 갱신 후 App Store 배포용 IPA 내보내기 성공. 보관 위치: `build/AppStore/GrunnY.ipa`, `build/AppStore/GrunnY.xcarchive`. 심사 제출·App Store Connect 최종 Validate는 미실행.
