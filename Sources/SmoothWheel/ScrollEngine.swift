import AppKit
import ApplicationServices
import Combine
import ScrollCore

final class ScrollEngine: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var running = false
    @Published private(set) var problem: String?
    private let preferences: Preferences
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var animationTimer: Timer?
    private var permissionTimer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var vertical = ScrollAxis()
    private var horizontal = ScrollAxis()
    private var lastTick = 0.0
    private var eventLocation = CGPoint.zero
    private var eventFlags: CGEventFlags = []
    private var targetWindow: Int64 = 0
    private var cachedWindow: Int64 = -1
    private var cachedBundleID: String?
    private let marker: Int64 = 0x53574_4845454C
    private let eventSource = CGEventSource(stateID: .privateState)

    init(preferences: Preferences) {
        self.preferences = preferences
        preferences.$enabled.dropFirst().sink { [weak self] enabled in
            // @Published emits before assignment; defer reading the preferences.
            DispatchQueue.main.async { enabled ? self?.start() : self?.stop() }
        }.store(in: &subscriptions)
        preferences.objectWillChange.sink { [weak self] _ in
            self?.cancelMotion()
        }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil,
                                                         queue: .main) { [weak self] _ in
                self?.cancelMotion()
                self?.cachedWindow = -1
            })
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshPermission()
        }
        refreshPermission()
    }

    var statusText: String {
        if !accessibilityGranted { return "Нужен доступ к Универсальному доступу" }
        if !preferences.enabled { return "Сглаживание на паузе" }
        if let problem { return problem }
        return running ? "Сглаживание работает" : "Подключение…"
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacyPane("Privacy_Accessibility")
    }

    func requestInputAccess() {
        _ = CGRequestListenEventAccess()
        openPrivacyPane("Privacy_ListenEvent")
    }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    func retry() {
        stop()
        refreshPermission()
    }

    private func refreshPermission() {
        let trusted = AXIsProcessTrusted()
        if accessibilityGranted != trusted {
            accessibilityGranted = trusted
            problem = nil
        }
        if !trusted {
            stop()
        } else if preferences.enabled && eventTap == nil && problem == nil {
            start()
        }
    }

    private func start() {
        guard preferences.enabled, AXIsProcessTrusted(), eventTap == nil else { return }
        problem = nil
        guard CGPreflightPostEventAccess() else {
            problem = "macOS пока не разрешает отправку событий. Проверьте доступ и повторите."
            return
        }
        let mask = (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<ScrollEngine>.fromOpaque(context).takeUnretainedValue()
                return engine.handle(type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            problem = "Не удалось подключить прокрутку. Проверьте системные разрешения."
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            problem = "Не удалось создать обработчик событий."
            return
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        running = true
    }

    func stop() {
        cancelMotion()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        if running { running = false }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelMotion()
            if let tap = eventTap, preferences.enabled, AXIsProcessTrusted() {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else {
            cancelMotion()
            return Unmanaged.passUnretained(event)
        }
        // Our own output must never be intercepted a second time.
        guard event.getIntegerValueField(.eventSourceUserData) != marker else {
            return Unmanaged.passUnretained(event)
        }
        guard preferences.enabled, running else { return Unmanaged.passUnretained(event) }

        // Pixel/gesture events already have native smoothing (trackpads, some
        // high-resolution mice). A continuous flag does not identify a device.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
              event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0,
              event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0,
              event.getIntegerValueField(.scrollWheelEventDeltaAxis3) == 0,
              event.flags.intersection([.maskControl, .maskCommand, .maskAlternate]).isEmpty
        else {
            cancelMotion()
            return Unmanaged.passUnretained(event)
        }

        let window = event.getIntegerValueField(.mouseEventWindowUnderMousePointer)
        if isExcluded(window: window) {
            cancelMotion()
            return Unmanaged.passUnretained(event)
        }
        var y = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        var x = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        guard x != 0 || y != 0 else { return Unmanaged.passUnretained(event) }

        // Some drivers leave Shift+wheel on the vertical axis.
        if event.flags.contains(.maskShift) && x == 0 { x = y; y = 0 }
        if animationTimer != nil && (window != targetWindow || event.flags != eventFlags) {
            cancelMotion()
        }
        eventLocation = event.location
        eventFlags = event.flags
        targetWindow = window
        let scale = preferences.distance * (preferences.reversed ? -1 : 1)
        vertical.add(y * scale)
        horizontal.add(x * scale)
        beginAnimation()
        return nil
    }

    private func isExcluded(window: Int64) -> Bool {
        guard !preferences.exclusions.isEmpty else { return false }
        // Resolve the app under the pointer, including inactive windows.
        if window != cachedWindow || window == 0 {
            cachedWindow = window
            cachedBundleID = nil
            if window > 0,
               let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window))
                    as? [[String: Any]],
               let pid = windows.first?[kCGWindowOwnerPID as String] as? Int32 {
                cachedBundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            }
            if cachedBundleID == nil {
                cachedBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            }
        }
        return preferences.exclusions.contains { $0.id == cachedBundleID }
    }

    private func beginAnimation() {
        guard animationTimer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / 120, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.001
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastTick
        lastTick = now
        // Do not replay a backlog after sleep, a blocked run loop, or moving
        // the pointer to another scroll view. Clicking also cancels the tail.
        guard elapsed > 0, elapsed < 0.15, running,
              let pointer = CGEvent(source: nil)?.location,
              hypot(pointer.x - eventLocation.x, pointer.y - eventLocation.y) < 3
        else { cancelMotion(); return }

        let y = vertical.advance(seconds: elapsed, settlingTime: preferences.duration)
        let x = horizontal.advance(seconds: elapsed, settlingTime: preferences.duration)
        if y != 0 || x != 0 {
            guard let output = CGEvent(scrollWheelEvent2Source: eventSource, units: .pixel,
                                       wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0) else {
                cancelMotion()
                return
            }
            output.location = eventLocation
            output.flags = eventFlags
            output.setIntegerValueField(.eventSourceUserData, value: marker)
            output.post(tap: .cgSessionEventTap)
        }
        if !vertical.isMoving && !horizontal.isMoving {
            // Keep each axis's fractional carry across consecutive gestures.
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func cancelMotion() {
        animationTimer?.invalidate()
        animationTimer = nil
        vertical.reset()
        horizontal.reset()
    }
}
