# DTF: mobile app / loginV2
Read when the change touches `pages/loginV2`, or a reviewer asks to test in the mobile app.

**Any `pages/loginV2` change: also verify in the mobile app.** The app's login IS Nova web in a WebView, so a reviewer's "test in web and mobile" is one more Phase 4.75 run, not an afterthought — Android dev client + raw CDP, memory `reference_mobile_app_webview_verification`.

- Repeat the visual check in the mobile app's WebView (Android dev client + raw CDP, memory `reference_mobile_app_webview_verification`).
