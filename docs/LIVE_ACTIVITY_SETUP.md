# Live Activity Setup

The active-workout Live Activity ships across two places:

- **Main app target (`SuggestMeSome`)** — owns `WorkoutLiveActivityAttributes`
  (the `ActivityAttributes` + `ContentState` contract) and
  `WorkoutLiveActivityController` (the ActivityKit lifecycle wrapper).
  Already landed on `main`. All ActivityKit calls are guarded behind
  `#if canImport(ActivityKit) && !os(macOS)` so the code compiles every
  configuration; the controller just no-ops until a Widget Extension
  target renders the activity.
- **Widget Extension target (`SuggestMeSomeLiveActivity`)** — renders the
  lock-screen + Dynamic Island presentations. Source files already in
  the `SuggestMeSomeLiveActivity/` folder at the repo root. **The Xcode
  target itself still needs to be added manually** — direct project.pbxproj
  edits carry too much risk.

## Adding the Widget Extension target in Xcode

1. Open `SuggestMeSome.xcodeproj`.
2. Select the project root, then **File → New → Target…**.
3. Pick **Widget Extension** under iOS → Application Extension.
4. Set:
   - Product name: `SuggestMeSomeLiveActivity`
   - Include Live Activity: **on**
   - Include Configuration Intent: **off** (no user-configurable settings)
5. Finish. Xcode generates starter files; **delete them** — the real
   sources already live in `SuggestMeSomeLiveActivity/` at the repo root.
6. In the new target's General tab, add the existing folder to the
   target's source files (drag-and-drop `SuggestMeSomeLiveActivity/*.swift`
   into the target). If the project uses file-system-synchronized groups,
   just drag the folder into the target group.
7. Add `SuggestMeSome/Services/LiveActivity/WorkoutLiveActivityAttributes.swift`
   to the widget target's membership too (it's shared — the main app
   starts the activity, the widget reads the attributes). Target
   Membership pane, check the widget target box.
8. Open the main app target's **Info.plist** and add:

   ```
   <key>NSSupportsLiveActivities</key>
   <true/>
   ```
9. Build and run on a device (Dynamic Island layouts don't render on the
   simulator reliably). Start a workout, lock the screen, and the
   activity should appear.

## Deep-link handling

The widget's `.widgetURL(...)` points at `suggestmesome://workout/<sessionID>`.
`AppRouteCoordinator` already handles workout deep-links; add a case to
`AppDeepLinkRoute` if you want the activity tap to route to a specific
sub-surface of `WorkoutView` (e.g. resume the active session).

## Testing

`Feature20LiveActivityTests` already covers:

- `ContentState.fromSession(...)` factory under strength / bodyweight /
  cardio / paused / fully-logged sessions
- `initialGlyph` diacritic handling and empty-input safety
- Next-set target formatting
- Codable round-trip
- `ActiveWorkoutSessionStore` lifecycle bridge (start / update / end /
  identity swap)

What the tests don't cover (requires a device or the widget preview
canvas): the lock-screen layout, compact / expanded / minimal Dynamic
Island presentations, or the `.widgetURL` deep-link resolution.
