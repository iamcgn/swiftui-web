# TimelineView

Apple docs: [TimelineView](https://developer.apple.com/documentation/swiftui/timelineview),
[TimelineSchedule](https://developer.apple.com/documentation/swiftui/timelineschedule).

## API surface

| API | Notes |
|---|---|
| `TimelineView(_:content:)`, `TimelineViewDefaultContext` (`date`, `cadence`) | implemented |
| `.periodic(from:by:)`, `.everyMinute`, `.explicit(_:)`, `.animation`, `.animation(minimumInterval:paused:)` | implemented (`TimelineScheduleMode.lowFrequency` is accepted but not distinguished) |
| Custom `TimelineSchedule` conformances (`entries(from:mode:)`) | implemented (the runtime reads the first entries after the current date) |
| `Timer`, `Timer.publish`, `RunLoop` scheduling | not available on wasm: Foundation timers never fire there; use `TimelineView` or `.task` with `Task.sleep` |

## Behaviour

`TimelineNode` renders the content closure for its current date and asks the schedule for the
next date after it. Periodic, every-minute and explicit schedules wake through a main-actor
`Task` sleeping until that date (the JS event loop drives `Task.sleep` on wasm), which sets the
date, invalidates the node, and — after the re-render — schedules the following wake; the host
flushes each invalidation into a frame, so wakes chain (headless callers must lay out between
wakes). The animation schedule subscribes the node to the runtime's per-frame advance
(`advanceFrameSubscribers`, called from `advanceAnimations` every host frame), re-rendering with
the frame's date, throttled by `minimumInterval` and stopped by `paused`; unmounting cancels the
wake or the subscription.

## Measured (macOS 26.2, `timeline/basic`, 2026-09-03)

| Property | Value | Probe |
|---|---|---|
| First render | the content for the schedule's first date ("Ticks: 0" 47.5 × 16; the animation schedule's cadence is `.live`) | `periodic`, `animation` |
| Browser ticks | 4 periodic ticks in 2.2 s at a 0.5 s period; the counter text re-lays out each time | `Playwright/timeline-probe.mjs` |

## Verification (2026-09-03)

Tier A: `timeline/basic` exact (the golden holds the first render; a 0.5 s period keeps Tier B's
capture before the first tick). Tier B 1/1 in Chromium and WebKit, Firefox off by the "Live"
width (the known hinting class). `TimelineTests` cover periodic wakes and cancellation on unmount,
the animation schedule following frames, and the schedules' entries. wasm js tests pass.

## Not yet covered

`lowFrequency` mode, `Timer`-based APIs, date formatting for `Text(date, style:)`, timeline
content that reads the environment's calendar or time zone, pausing when the page is hidden.
