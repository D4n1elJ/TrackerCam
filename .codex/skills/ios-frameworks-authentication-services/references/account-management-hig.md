# Account Management (HIG)

## Core Rule

Make account creation effortless, sign-in invisible, and deletion straightforward. People abandon apps that make authentication painful.

## Account Creation

### Delay as Long as Possible
- Let people use the app before requiring an account
- Show value first, then ask for sign-up when they need to save/sync/share
- Guest mode for browsing, account for personalisation

### Minimize Required Fields
- Name + email/phone OR Sign in with Apple — that's it for most apps
- Never require: birthday, gender, phone (unless core to the feature)
- Use AutoFill: `.textContentType(.emailAddress)`, `.textContentType(.name)`

### Sign in with Apple First
- Required by App Store if you offer any third-party sign-in
- Place at the top of sign-in options
- Use the standard `SignInWithAppleButton` (required sizing/style)

## Sign-In Flow

### Credential AutoFill
```swift
TextField("Email", text: $email)
    .textContentType(.emailAddress)
    .keyboardType(.emailAddress)

SecureField("Password", text: $password)
    .textContentType(.password)
```

### Biometric Auth for Returning Users
- Use Face ID / Touch ID for returning users instead of password re-entry
- Fall back to password if biometric fails
- Don't require biometric — always offer an alternative

### Remember Me
- Keep users signed in by default
- Use Keychain for credential storage
- Only sign out for explicit user action or security events

## Account Deletion (App Store Requirement)

Apps that support account creation MUST offer account deletion.

### Requirements
- Must be discoverable (Settings → Account → Delete Account)
- Must delete the account and associated data from your servers
- Must allow the user to cancel/confirm before deleting
- Should explain what will be lost
- Should offer data export before deletion

### Pattern

```swift
Button("Delete Account", role: .destructive) {
    showDeleteConfirmation = true
}
.confirmationDialog("Delete Account?", isPresented: $showDeleteConfirmation) {
    Button("Delete Account", role: .destructive) {
        Task { await deleteAccount() }
    }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("This will permanently delete your account and all associated data. This cannot be undone.")
}
```

## Password Rules

If accepting passwords (prefer Sign in with Apple / passkeys instead):
- Minimum 8 characters, no maximum
- Don't restrict special characters
- Don't require specific character classes ("must include uppercase")
- Use `SecureField` with `.textContentType(.newPassword)` for AutoFill strong password generation
- Never store passwords — use server-side hashing

## What NOT to Do

- Don't require sign-in before showing any content
- Don't show a sign-in wall on first launch
- Don't hide account deletion — App Store Review will reject you
- Don't force password changes on a schedule
- Don't use CAPTCHA if avoidable — it's hostile UX
- Don't send a verification email that blocks app usage — let them use the app, verify later
