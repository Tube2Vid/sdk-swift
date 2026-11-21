# Changelog

## 0.2.0 (2026-11-21)

- The anonymous browser flow now uses an Atlas captcha: `JobSubmitInput.captchaToken` replaces `pow` and `turnstileToken`, and a failed check comes back with code `captcha_failed`.
- Removed `getPowChallenge()`, `PowChallenge` and `ProofOfWork`: the API no longer serves `GET /v1/challenges/pow`. Calls with an API key are unchanged.

## 0.1.0 - 2026-11-21

- First release: typed client for the Tube2Vid API v1 (jobs, polling, downloads, platforms, status, usage, API keys, billing checkout).
