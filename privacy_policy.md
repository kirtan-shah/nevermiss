# NeverMiss Privacy Policy

NeverMiss is an open-source macOS menu bar app that shows reminders for your upcoming meetings. This policy describes what the app accesses, what leaves your device, and what it does not.

## Summary

- **NeverMiss has no backend server. We do not run any service that collects your data.**
- Calendar data you view in the app stays on your device.
- The app makes outbound network requests to exactly three parties: **Google** (only if you connect a Google Calendar account), **GitHub** (to check for app updates), and **Sparkle's update framework**
- There are no analytics, no tracking, no advertising SDKs, and no third-party SDKs other than Sparkle (for updates).

## What the app accesses on your device

### macOS Calendar (EventKit)
If you connect the macOS Calendar app, NeverMiss requests **read-only** access through Apple's EventKit API. This data is read directly from macOS on your device and stays on your device.

### Google (only if you connect a Google account)
If you choose to connect a Google Calendar account, the app performs an OAuth 2.0 sign-in directly with Google and then calls Google's APIs on your behalf. Authentication tokens are securely stored on your device in macOS Keychain.
The following permission scopes are requested: `https://www.googleapis.com/auth/calendar.readonly` (read-only access to your calendars) and `https://www.googleapis.com/auth/userinfo.email` (your account email, used to label the connected account in the app).

### App updates (Sparkle + GitHub)
NeverMiss uses [Sparkle](https://sparkle-project.org/) to check for new versions.
Sparkle's update check currently includes an **anonymous system profile** appended as query parameters. This profile reports:

- macOS version
- CPU type and number of CPUs
- Preferred language
- App version and bundle identifier

You can disable update checks entirely in **Settings → General → "Automatically check for updates"**. When automatic checks are off, Sparkle only contacts the update server when you manually choose "Check for Updates…".

## Data we do not collect

Because there is no NeverMiss backend, the developer does not receive, store, or have the ability to access:

- Your calendar events
- Your email address or Google account details
- Your IP address
- Device identifiers
- Usage analytics

## Children

NeverMiss is a general-audience productivity app and is not directed at children under 13. It does not knowingly collect information from anyone.

## Changes to this policy

If this policy changes, the updated version will be published in the NeverMiss repository with a new "Last updated" date.

## Contact

NeverMiss is maintained by Kirtan Shah (maker.codes).

- Questions or concerns: [open an issue on GitHub](https://github.com/kirtan-shah/NeverMiss/issues)
- Email: _kirtan@maker.codes_

NeverMiss is open source under the AGPL-3.0 license. You can review the full source at https://github.com/kirtan-shah/NeverMiss to verify every claim in this policy.

_Last updated: 2026-04-13_
