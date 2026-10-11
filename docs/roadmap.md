# SignMail — Roadmap

## Phase 0 — UI prototype
- [x] Welcome screen
- [x] Account setup flow (UI only)
- [x] Certificate onboarding (UI only)
- [x] Inbox, certificate vault, settings and compose previews
- [ ] Accessibility pass and responsive layout review

## Phase 1 — Reproducible builds
- [ ] Generate the native Android project with current Flutter stable
- [ ] Run `flutter pub get`, `flutter analyze`, and tests
- [ ] Configure GitHub repository and Android CI build
- [ ] Pin/record SDK and dependency versions after compatibility testing

## Phase 2 — Email transport
- [ ] Select and test IMAP/SMTP/MIME library
- [ ] Secure account credential storage
- [ ] Manual IMAP/SMTP configuration and connection diagnostics
- [ ] Send unsigned messages only in explicit development/test mode

## Phase 3 — Certificate lifecycle
- [ ] Document picker for PKCS#12
- [ ] Password handling without logging/persistence
- [ ] Certificate/key parsing and identity checks
- [ ] Android Keystore protection strategy and threat review

## Phase 4 — S/MIME
- [ ] Implement CMS signing via maintained library
- [ ] Produce interoperable S/MIME MIME format
- [ ] Unit tests for malformed/expired/mismatched certificates
- [ ] Verify generated messages independently
- [ ] Fail-closed signing policy

## Phase 5 — Inbox and usability
- [ ] IMAP folder list and message list/detail
- [ ] MIME parsing and safe HTML rendering
- [ ] Attachments and pagination
- [ ] Signature verification display

## Phase 6 — Release hardening
- [ ] OAuth2 flows where required by providers
- [ ] Network/security tests and dependency audit
- [ ] Accessibility, localisation and battery behavior
- [ ] Privacy policy and clear data-flow documentation
