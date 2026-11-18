// Combine's timed operators as Apple declares them, generic over a `Scheduler` and taking its
// stride (`.debounce(for: .milliseconds(300), scheduler: RunLoop.main)`, the Composable
// Architecture's `delay(for: dueTime, scheduler: scheduler)`): the waiting is the scheduler's,
// so a test scheduler that a test advances decides when the values arrive. The `Double` forms
// in Operators.swift keep taking seconds; a plain number literal still picks them.
import WebFoundation

extension Publisher {
    /// Delivers every value, and the completion, `interval` later by `scheduler`'s clock.
    public func delay<S: Scheduler>(for interval: S.SchedulerTimeType.Stride, tolerance: S.SchedulerTimeType.Stride? = nil,
                                    scheduler: S, options: S.SchedulerOptions? = nil) -> _Pipe<Output, Failure> {
        let wait = _SchedulerWait(scheduler, interval, tolerance, options)
        return _Pipe { receive, complete in
            let live = _State(true)
            let upstream = self._subscribeOnMain({ value in
                nonisolated(unsafe) let value = value
                wait.after { if live.value { receive(value) } }
            }, { completion in
                nonisolated(unsafe) let completion = completion
                wait.after { if live.value { complete(completion) } }
            })
            return AnyCancellable { live.value = false; upstream.cancel() }
        }
    }

    /// Delivers a value once `dueTime` passes by `scheduler`'s clock with no newer one (the last
    /// value of a burst).
    public func debounce<S: Scheduler>(for dueTime: S.SchedulerTimeType.Stride, scheduler: S,
                                       options: S.SchedulerOptions? = nil) -> _Pipe<Output, Failure> {
        let wait = _SchedulerWait(scheduler, dueTime, nil, options)
        return _Pipe { receive, complete in
            let latest = _State(0)
            let upstream = self._subscribeOnMain({ value in
                latest.value += 1
                let mine = latest.value
                nonisolated(unsafe) let value = value
                wait.after { if latest.value == mine { receive(value) } }
            }, { completion in latest.value += 1; complete(completion) })
            return AnyCancellable { latest.value += 1; upstream.cancel() }
        }
    }

    /// Delivers at most one value per `interval` of `scheduler`'s clock: the first, and with
    /// `latest` the newest of the window when it closes.
    public func throttle<S: Scheduler>(for interval: S.SchedulerTimeType.Stride, scheduler: S,
                                       latest: Bool) -> _Pipe<Output, Failure> {
        let wait = _SchedulerWait(scheduler, interval, nil, nil)
        return _Pipe { receive, complete in
            let window = _State<(open: Bool, held: Output?)>((false, nil))
            let live = _State(true)
            let upstream = self._subscribeOnMain({ value in
                if window.value.open {
                    if latest { window.value.held = value }
                    return
                }
                receive(value)
                window.value = (true, nil)
                wait.after {
                    let held = window.value.held
                    window.value = (false, nil)
                    if live.value, let held { receive(held) }
                }
            }, { completion in
                // A value held for the window's close dies with the stream: nothing follows the
                // completion.
                live.value = false
                window.value = (false, nil)
                complete(completion)
            })
            return AnyCancellable { live.value = false; upstream.cancel() }
        }
    }
}

/// One scheduler, its stride and options, kept for an operator's later waits. Every action runs
/// on the main actor: on wasm each scheduler's queue is the page's one thread.
struct _SchedulerWait<S: Scheduler>: @unchecked Sendable {
    let scheduler: S
    let interval: S.SchedulerTimeType.Stride
    let tolerance: S.SchedulerTimeType.Stride?
    let options: S.SchedulerOptions?
    init(_ scheduler: S, _ interval: S.SchedulerTimeType.Stride, _ tolerance: S.SchedulerTimeType.Stride?, _ options: S.SchedulerOptions?) {
        self.scheduler = scheduler
        self.interval = interval
        self.tolerance = tolerance
        self.options = options
    }
    func after(_ action: @escaping @MainActor () -> Void) {
        scheduler.schedule(after: scheduler.now.advanced(by: interval), tolerance: tolerance ?? scheduler.minimumTolerance,
                           options: options) {
            MainActor.assumeIsolated { action() }
        }
    }
}
