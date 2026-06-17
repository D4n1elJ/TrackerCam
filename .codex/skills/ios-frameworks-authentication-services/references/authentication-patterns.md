# Authentication Patterns

## Sign in with Apple

### SwiftUI (iOS 14+)

```swift
import AuthenticationServices

SignInWithAppleButton(.signIn) { request in
    request.requestedScopes = [.fullName, .email]
} onCompletion: { result in
    switch result {
    case .success(let auth):
        guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
        let userID = credential.user                    // Stable identifier
        let identityToken = credential.identityToken    // JWT for server verification
        let authCode = credential.authorizationCode     // Exchange for refresh token
        let fullName = credential.fullName              // Only on FIRST sign-in
        let email = credential.email                    // Only on FIRST sign-in
        // Send to server immediately — name/email won't be provided again
    case .failure(let error):
        if (error as? ASAuthorizationError)?.code == .canceled { return }
        // Handle error
    }
}
.signInWithAppleButtonStyle(.black)  // .black, .white, .whiteOutline
```

### UIKit / Programmatic

```swift
let provider = ASAuthorizationAppleIDProvider()
let request = provider.createRequest()
request.requestedScopes = [.fullName, .email]

let controller = ASAuthorizationController(authorizationRequests: [request])
controller.delegate = self
controller.presentationContextProvider = self
controller.performRequests()

// Delegate
func authorizationController(controller: ASAuthorizationController,
                              didCompleteWithAuthorization authorization: ASAuthorization) {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
    // Process credential
}
```

### Check Credential State

```swift
// Call on every app launch
let provider = ASAuthorizationAppleIDProvider()
provider.getCredentialState(forUserID: savedUserID) { state, error in
    switch state {
    case .authorized: break      // Still valid
    case .revoked: signOut()     // User revoked in Settings
    case .notFound: signOut()    // No credential found
    case .transferred: break     // App transferred to new team
    @unknown default: break
    }
}
```

## Passkeys

```swift
let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
    relyingPartyIdentifier: "example.com"
)

// Registration
let registrationRequest = provider.createCredentialRegistrationRequest(
    challenge: serverChallenge,
    name: "user@example.com",
    userID: Data(userId.utf8)
)

// Authentication
let assertionRequest = provider.createCredentialAssertionRequest(
    challenge: serverChallenge
)

let controller = ASAuthorizationController(authorizationRequests: [assertionRequest])
controller.delegate = self
controller.presentationContextProvider = self
controller.performRequests()
```

## AutoFill Credential Requests

```swift
// Trigger AutoFill suggestion (iOS 16+)
let controller = ASAuthorizationController(authorizationRequests: [
    ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "example.com")
        .createCredentialAssertionRequest(challenge: challenge),
    ASAuthorizationAppleIDProvider().createRequest()
])
controller.performAutoFillAssistedRequests()  // Shows in keyboard AutoFill bar
```

## OAuth with ASWebAuthenticationSession

```swift
let session = ASWebAuthenticationSession(
    url: oauthURL,
    callbackURLScheme: "myapp"
) { callbackURL, error in
    guard let url = callbackURL,
          let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
              .queryItems?.first(where: { $0.name == "code" })?.value
    else { return }
    // Exchange code for tokens
}
session.presentationContextProvider = self
session.prefersEphemeralWebBrowserSession = true  // No shared cookies
session.start()
```

## Best Practices

- Store `credential.user` (stable ID) in your backend immediately
- Store name/email on first sign-in — Apple won't provide them again
- Check credential state on every launch
- Use `.prefersEphemeralWebBrowserSession` for OAuth to avoid session leaks
- Sign in with Apple button must follow Apple's HIG sizing guidelines
- Handle `.canceled` error silently — user dismissed intentionally
