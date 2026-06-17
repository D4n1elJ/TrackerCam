---
name: ios-frameworks-authentication-services
description: Use when implementing or reviewing Sign in with Apple, passkeys, credential providers, AutoFill, or AuthenticationServices flows.
---

# Authentication Services

Review and write authentication code for correct Sign in with Apple, passkey, and credential management patterns.

## Responsibility

**Owns:** Sign in with Apple (ASAuthorizationAppleIDProvider), passkeys (ASAuthorizationPlatformPublicKeyCredentialProvider), ASAuthorizationController, credential AutoFill, security upgrades, ASWebAuthenticationSession (OAuth), enterprise SSO.

**Does NOT own:** Server-side token validation, networking layer, keychain direct access (Security framework), biometric auth (LocalAuthentication), password hashing.

## Core Principles

1. **Sign in with Apple is required** if your app offers any third-party sign-in (App Store guideline 4.8).
2. **Prefer passkeys over passwords.** Passkeys are phishing-resistant, device-synced via iCloud Keychain, and require no user memory.
3. **Handle all authorization results.** Success returns different credential types; cancellation is not an error.
4. **User info is provided once.** Apple ID name and email are only in the initial authorization. Store them server-side immediately.
5. **Check credential state on launch.** Users can revoke Apple ID sign-in from Settings at any time.
6. **Use ASWebAuthenticationSession for OAuth.** Not SFSafariViewController — it provides proper session isolation.

## References

- `references/authentication-patterns.md` — Sign in with Apple, passkeys, OAuth, credential state, AutoFill
