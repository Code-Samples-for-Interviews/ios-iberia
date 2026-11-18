# Album Search

A small iOS app for finding albums in the iTunes catalog. Search by artist or album name, browse the results and open an album to see its artist, genre, track count and release date.

The aim is straightforward: meet the requirements with code that another developer can understand, test and change. Each layer has a clear job. Every abstraction has a concrete use.

## Run the app

- Xcode 16.4 or later, with Swift 6 support and an iOS simulator runtime.
- iOS 18 or later on iPhone or iPad.
- No API key, account or third-party dependencies are needed for development.

Open `AlbumSearch.xcodeproj`, select the **AlbumSearch** scheme and an iOS simulator, then run. On a physical device, select your development team and a unique bundle identifier under Signing & Capabilities first.

Try searching for `Queen` or `Adele`. The interface, source code and documentation are in English. Dates use the device's regional format.

## Public API

The app uses Apple's [iTunes Search API](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/). It needs no authentication, supports text searches and returns enough metadata for the detail screen in one request.

Example: [search for Queen albums](https://itunes.apple.com/search?term=queen&entity=album&media=music&country=es&limit=30).

We request up to 30 albums from the Spanish store. This is a fixed catalog choice, independent of the interface language. The API may include singles and EPs in album searches. There is no pagination or second detail request: the selected result already contains the detail fields. Missing optional fields are shown explicitly as unavailable. Artwork and audio are outside this exercise's scope.

Apple documents an approximate limit of 20 calls per minute, subject to change. Debounce and caching reduce traffic, but are not a rate limiter. An unavailable or rate-limited API produces the same recoverable error state as other request failures.

## Architecture

One application target is the composition root. One local Swift package contains three modules:

```text
AlbumSearch/App                Creates and connects the dependencies
Packages/AlbumSearchKit/
  Sources/
    Domain/                    Album, AlbumRepository, SearchAlbums
    Data/                      HTTP client, API mapping, repository and cache
    Presentation/              SwiftUI views and SearchViewModel
  Tests/
    DomainTests/               Swift Testing
    DataTests/                 Swift Testing
    PresentationTests/         XCTest
```

Dependencies point toward Domain:

```text
Presentation ──→ Domain ←── Data
                     ↑
           App wires the implementations
```

**This is a small Clean Architecture implementation with MVVM.** Domain has no UI or networking dependencies. Presentation imports Domain, never Data. Data implements the repository contract declared in Domain. Swift Package Manager enforces these boundaries.

The data flow is `View → ViewModel → SearchAlbums → AlbumRepository → HTTPClient`. Results return through the same path. Native `NavigationStack` handles navigation; two screens do not need a coordinator.

`SearchViewModel` is `@MainActor` and observable. It exposes a single state enum: idle, loading, loaded or failed. The views render that state. Networking and cache state belong to the repository actor, away from the main actor. Values crossing isolation boundaries are `Sendable`; there are no detached tasks or unchecked concurrency annotations.

### How SOLID is applied

| Principle | Concrete decision |
| --- | --- |
| Single responsibility | Views describe UI; the model manages search state; the use case normalizes input; the repository owns retrieval and caching; the HTTP client handles transport. |
| Open/closed | A different repository or HTTP transport can be injected without changing the consumer. |
| Liskov substitution | Mocks and the live repository implement the same async contract, including errors and cancellation. The use case checks cancellation defensively. |
| Interface segregation | Two small protocols expose only the operations their consumers need. |
| Dependency inversion | The use case depends on `AlbumRepository`, not iTunes. Dependencies arrive through initializers. |

There is no DI container, generic networking framework or protocol for every type. `SearchAlbums` is a concrete, stateless use case; its repository is the substitution point needed by the tests.

## Search and cancellation

1. Editing the query immediately clears previous results and changes the request identifier.
2. SwiftUI's `.task(id:)` cancels the previous task and starts the new one. The task also follows the view's lifetime.
3. A cancellable 300 ms debounce avoids a request for every keystroke.
4. The use case trims leading/trailing whitespace and lowercases the query. Blank input never reaches the repository.
5. Cancellation propagates through the awaited calls to `URLSession.data(for:)`.
6. Before publishing, the model checks cancellation and the request identifier. An older result or error cannot replace the current state, even if a dependency ignores cancellation or SwiftUI has not cancelled the old task yet.

Cancellation is a normal outcome and never displays an error. A genuine failure offers an explicit retry with the same query. We keep no separate `Task` property: SwiftUI owns the task, and the model exposes an async operation that tests can call directly. See Apple's [task lifecycle documentation](https://developer.apple.com/documentation/swiftui/view/task(id:priority:_:)).

## Cache policy

`ITunesAlbumRepository` is an actor with an in-memory dictionary keyed by the normalized query. This actor owns the entire cache operation, so callers cannot race on dictionary state.

- Successful results, including empty lists, live for **180 seconds after retrieval**.
- A valid entry returns immediately without calling the HTTP client.
- At expiry, the entry is removed; the next request uses the network and stores the new result.
- A monotonic `ContinuousClock` avoids expiry changes when the device's wall clock changes. Tests inject its current instant and advance it without sleeping.
- Errors and cancelled requests are not cached. Expired data is not used as an offline fallback.
- The cache holds at most 50 queries and evicts the entry with the earliest expiry when full. Expired entries are pruned on access and after network retrieval.
- The HTTP session has no URL cache, so a repository cache miss is not silently served by a second cache layer.

The cache lasts for the process lifetime. Concurrent misses for the same query may make separate requests: actors protect state but do not deduplicate work across `await`. This single search flow does not need shared in-flight tasks.

## Tests

Run all tests in Xcode with **Product → Test** on the **AlbumSearch** scheme. The Xcode test target compiles the same test files used by the package; no duplicate test implementation is maintained.

For a fast local check without a simulator:

```sh
swift test --package-path Packages/AlbumSearchKit
```

This command needs macOS 15 or later. It exercises Domain, Data and the presentation model. The iOS-only SwiftUI files are compiled when building the app; package tests alone do not validate the screens.

For the full iOS check, replace `SIMULATOR_ID` with an available device from `xcrun simctl list devices available`:

```sh
xcodebuild test \
  -project AlbumSearch.xcodeproj \
  -scheme AlbumSearch \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  CODE_SIGNING_ALLOWED=NO
```

| Layer / framework | Behaviors covered |
| --- | --- |
| Domain / Swift Testing | Blank queries, normalization, returned results, propagated errors and cancellation. |
| Data / Swift Testing | Cache hits, exact expiry, replacement, query separation, capacity, URL encoding, DTO mapping, optional fields, errors and cancelled responses. |
| Presentation / XCTest | Loading/results, immediate clearing, out-of-order successes and errors, cancellation, empty input and retry. |

Tests use local doubles rather than the public API. Controlled continuations make response ordering deterministic. There are no network dependencies or wall-clock waits in the tests. Swift Testing provides concise assertions and parameterized inputs; XCTest covers the main-actor presentation model using the established framework.

Local validation on 18 November 2026: all 22 tests passed both through Swift Package Manager and on an iOS 27.2 simulator with Xcode 27.2. A Release archive for iOS was also built without signing. Live search, detail navigation and both screens at the largest accessibility text size were checked in the simulator. These checks do not replace the device checklist below or a signed TestFlight upload.

## Network and privacy boundaries

Requests use HTTPS with the system's default certificate validation. `URLComponents` encodes user input, and the repository validates HTTP status before decoding. The app includes no analytics or query logging, stores search results only in memory, and requires no user credentials. Raw server errors are not exposed in the interface.

## Accessibility

Accessibility is part of the implementation. Every file that declares UI ends with an **Accessibility summary** describing its behavior and how a teammate can check it.

- Native search, list, navigation and buttons provide system accessibility behavior.
- VoiceOver reads album title and artist together. Detail fields combine each label with its value; the album title is a heading.
- Completion and failure announcements do not deliberately move focus away from the search field.
- Semantic fonts, wrapping text and vertical detail fields support all Dynamic Type sizes without truncation or fixed row heights.
- System colors support light/dark mode and Increase Contrast. Information never depends on color, artwork or animation.

Before a release, perform these manual checks on a device:

1. With VoiceOver enabled, find the search field, search, hear completion, open a result, read every detail field and return. Check the headings rotor and error/retry flow.
2. Set the largest accessibility text size. Search for an album with a long title, scroll both screens and verify every value remains readable. Repeat in landscape and on iPad.
3. Repeat in dark mode, with Increase Contrast and Bold Text. Check focus visibility with an external keyboard.
4. With Voice Control and Switch Control, reach the search control, select a result and activate Back and retry.
5. Use Accessibility Inspector to audit labels, contrast and target sizes. Inspect loading, empty, results and error states.

Unit tests validate state behavior, not spoken output, focus order or every assistive technology. The checklist is a release requirement; it is not a claim that a full device accessibility audit has already been completed.

## CI and TestFlight

`.github/workflows/ci.yml` has two jobs:

- **test** builds the app and runs both test frameworks on pull requests, pushes to `main`, version tags and manual runs. It keeps the `.xcresult` bundle as an artifact.
- **deliver** depends on passing tests, signs a Release archive and uploads it to App Store Connect for TestFlight. It runs on `v*` tags or a manual run on `main` with `deliver` enabled. Normal branch pushes and pull requests do not upload builds.

The runner is `macos-26` with Xcode 26.2 and an iOS 26.2 simulator, selected explicitly from the [GitHub runner image toolset](https://github.com/actions/runner-images/blob/main/images/macos/toolsets/toolset-26.json). Runner images change; update the Xcode path and simulator destination together when upgrading CI. This does not change the app's iOS 18 deployment target.

### Configure delivery once

Create the matching App ID and app record in App Store Connect, an Apple Distribution certificate with its private key exported as a password-protected `.p12`, and an App Store Connect provisioning profile for that certificate and bundle ID. Create a team App Store Connect API key with the App Manager role and access to the app. Accept any pending agreements in the Apple account.

Create a GitHub environment named **testflight** with these values:

| Type | Name | Value |
| --- | --- | --- |
| Variable | `APPLE_TEAM_ID` | Apple Developer team identifier. |
| Variable | `APP_BUNDLE_ID` | Registered bundle identifier matching the app record and profile. |
| Secret | `DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded `.p12`, including its private key. |
| Secret | `DISTRIBUTION_CERTIFICATE_PASSWORD` | Export password for the `.p12`. |
| Secret | `PROVISIONING_PROFILE_BASE64` | Base64-encoded App Store Connect provisioning profile. |
| Secret | `ASC_KEY_ID` | App Store Connect API key identifier. |
| Secret | `ASC_ISSUER_ID` | API key issuer identifier. |
| Secret | `ASC_PRIVATE_KEY_BASE64` | Base64-encoded `.p8` private key. |

On macOS, `base64 -i path/to/file | pbcopy` copies an encoded file for the corresponding secret. Never commit signing files or credentials. The runner imports the certificate into a temporary keychain and removes it, the provisioning profile and decoded credentials on exit. Manual signing keeps delivery independent of a developer's local Xcode account; the script only runs on GitHub Actions.

Use version tags such as `v1.0.0`; the tag sets the marketing version. Manual delivery uses the version in the project. The build number is `GITHUB_RUN_NUMBER.GITHUB_RUN_ATTEMPT`, so reruns get a new build number. Make **test** a required branch check and restrict the `testflight` environment to your release branches/tags.

Uploading does not publish to the App Store or automatically distribute to external testers. Apple still processes the build; testing groups and any beta review are managed in App Store Connect.

**Delivery is prepared but has not been exercised with a real Apple account.** Signing credentials and the GitHub environment must be configured before the first upload. No GitHub-hosted run is claimed until the repository is pushed and the workflow executes.

## Working on this code

Start with `SearchAlbums`, then `ITunesAlbumRepository`, then `SearchViewModel` and the two views. Read the tests alongside the implementation: they show the expected behavior at each boundary.

Swift Package Manager discovers new source and test files automatically. When adding a test file, also add it to the Xcode **AlbumSearchTests** target so the simulator and CI run it.

When adding a change, keep it in the layer that owns the responsibility, cover the behavior that could regress and update this README if a decision changes. Include the relevant accessibility checks in the pull request. For pairing or onboarding, the out-of-order response test is a useful example: it demonstrates why cancellation and guarding the current request solve related but different problems.

There is room to grow when a real requirement calls for it: pagination, persistent storage, richer errors or request coalescing. For this exercise, two screens, two protocols and one cache are enough.
