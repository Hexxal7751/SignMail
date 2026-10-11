# SignMail — MVP

## MVP goal
Send one correctly S/MIME-signed email from an Android device using a user-provided certificate and a supported SMTP account, with an independently verifiable signature.

## Must-have
- Guided account setup with automatic discovery where possible and manual IMAP/SMTP fallback
- Secure credential storage and TLS-only transport
- Import PKCS#12 (`.p12` / `.pfx`) using Android document picker
- Validate certificate expiry, email identity, key usage, and private-key presence
- Compose plain-text email and send via SMTP
- CMS/S/MIME signature creation using a maintained cryptographic implementation
- Fail closed if signing is required and unavailable
- Independent signature verification tests
- Clear states: unsigned, signed, signing failed, certificate expired/untrusted

## Later
- IMAP inbox and folders, HTML mail, attachments, multiple accounts, OAuth2 provider flows, push/IDLE sync, app lock, encrypted mail, and iOS support.

## Acceptance criteria
1. A test email is accepted by a real SMTP provider over TLS.
2. A recipient can validate its S/MIME signature with an independent client/tool.
3. Any signing failure prevents transmission when signing is required.
4. PKCS#12 password and private key are never sent to a remote SignMail service or written to logs.
5. Invalid, expired, mismatched and unsupported certificates produce actionable errors.
