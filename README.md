# ECOM 아이폰 앱 (파일럿)

[ecom](https://ecom-terminal.pages.dev/) 화면을 그대로 띄우는 아이폰 앱과 홈 화면 · 잠금 화면 시세 위젯.

- 위젯: 코스피 · 코스닥 · 원·달러 · S&P 500 · 나스닥 · 오늘 경보 · 주의
- 위젯을 누르면 앱이 열리고, 신호 줄을 누르면 그 알림의 화면으로 간다

## 받기

[최신 빌드](../../releases/tag/latest)의 `Ecom.ipa` — 서명이 없는 파일이라 폰에 넣을 때 Apple ID 로 서명한다.

## 만드는 법

Mac 없이 GitHub 의 클라우드 Mac 이 만든다(`.github/workflows/build.yml`). `main` 에 올리면 10분 안에 새 `Ecom.ipa` 가 릴리스에 올라간다.

## 알아 둘 것

- 무료 Apple ID 로 서명하면 7일마다 다시 서명해야 한다.
- 폰 알림은 지금처럼 홈 화면 웹앱이 맡는다. 앱 안 화면에서는 웹 알림이 오지 않는다.
