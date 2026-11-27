import AppKit
import IOKit.pwr_mgt
import Darwin

/// Tells the tablet whether the Mac is awake, about to sleep, or logged out, so it can switch to its
/// full-screen standby layout *before* the Mac disappears.
final class Presence {
    static let shared = Presence()

    enum State: String { case awake, locked, sleeping, loggedOut, quitting }

    private let lock = NSLock()
    private var _state: State = .awake
    /// The screen lock is tracked on its own, because it outlasts sleep: lock → sleep → wake is still locked.
    private var _locked = false
    private var override: (State, Date)?
    private var stateSince = Date()
    var state: State {
        lock.lock(); defer { lock.unlock() }
        if let (s, until) = override, Date() < until { return s }
        if _state == .awake && _locked { return .locked }
        return _state
    }
    func set(_ s: State) {
        lock.lock(); if _state != s { stateSince = Date() }; _state = s; lock.unlock()
        if s == .sleeping { setIdle(sleeping: true) } else if s == .awake { setIdle(sleeping: false) }
    }

    /// "The Mac is idle" for the tablet's screen-saver option: the screen saver is running, the displays are asleep,
    /// or the Mac is going to sleep. The lock screen on its own doesn't count.
    private var _saver = false, _displaysAsleep = false, _sleeping = false
    private var engineSeen = false
    private var lastIdle = false
    var screenSaverRunning: Bool { lock.lock(); defer { lock.unlock() }; return _saver }
    var macIdle: Bool { lock.lock(); defer { lock.unlock() }; return _saver || _displaysAsleep || _sleeping }
    var onIdleChange: ((Bool) -> Void)?
    private func setIdle(saver: Bool? = nil, displays: Bool? = nil, sleeping: Bool? = nil) {
        lock.lock()
        if let saver { _saver = saver }; if let displays { _displaysAsleep = displays }; if let sleeping { _sleeping = sleeping }
        let now = _saver || _displaysAsleep || _sleeping, changed = now != lastIdle
        lastIdle = now
        lock.unlock()
        if changed { onIdleChange?(now) }
    }
    private func setSaver(_ on: Bool) { setIdle(saver: on) }

    /// Looks for the screen saver process directly. NSWorkspace doesn't list it on every macOS version.
    static func screenSaverEngineRunning() -> Bool {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(n) + 32)
        let got = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var name = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(max(0, got)) where pid > 0 {
            if proc_name(pid, &name, UInt32(name.count)) > 0, String(cString: name) == "ScreenSaverEngine" { return true }
        }
        return false
    }
    func setLocked(_ l: Bool) { lock.lock(); _locked = l; lock.unlock() }

    /// Asks the window server directly, which also catches a lock that happened before Plinth started.
    static func screenIsLocked() -> Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }
    private var lockTimer: Timer?

    /// For testing the tablet's standby layout without actually sleeping the Mac.
    func simulate(_ s: State, seconds: TimeInterval) { lock.lock(); override = (s, Date().addingTimeInterval(seconds)); lock.unlock() }

    fileprivate var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    /// How long to hold off system sleep so the tablet's next 1-second poll sees "sleeping".
    static let announceDelay: TimeInterval = 1.6

    func start() {
        // System sleep/wake via IOKit, which lets us briefly delay sleep to announce it.
        rootPort = IORegisterForSystemPower(Unmanaged.passUnretained(self).toOpaque(), &notifyPort, powerCallback, &notifier)
        if rootPort != 0, let p = notifyPort {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(p).takeUnretainedValue(), .commonModes)
        }
        // Screen lock (Control-Command-Q, Lock Screen, lid/hot corner, screen saver with password).
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.setLocked(true) }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.setLocked(false) }
        setLocked(Self.screenIsLocked())
        dnc.addObserver(forName: .init("com.apple.screensaver.didstart"), object: nil, queue: .main) { [weak self] _ in self?.setSaver(true) }
        dnc.addObserver(forName: .init("com.apple.screensaver.didstop"), object: nil, queue: .main) { [weak self] _ in self?.engineSeen = false; self?.setSaver(false) }
        setSaver(Self.screenSaverEngineRunning())
        let nc = NSWorkspace.shared.notificationCenter
        // Backstop in case a notification is missed.
        lockTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.setLocked(Self.screenIsLocked())
            // The process check only ever confirms what it can see: it turns the flag on, and turns it off only
            // after it has seen the engine running, so a missed lookup can't cancel the didstart notification.
            if Self.screenSaverEngineRunning() { self.engineSeen = true; self.setSaver(true) }
            else if self.engineSeen { self.engineSeen = false; self.setSaver(false) }
            self.unstick()
        }
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.setIdle(displays: true) }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.setIdle(displays: false) }
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.set(.sleeping) }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.set(.awake); self?.setLocked(Self.screenIsLocked())
            FeedService.shared.refreshAll(); MediaFeeds.shared.refreshAll(); ExtraFeeds.shared.refreshAll(); MoreFeeds.shared.refreshAll()
        }
        // Logging out, restarting or shutting down.
        nc.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in self?.set(.loggedOut) }
        // Fast user switching: this session goes to the background but Plinth keeps running.
        nc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.set(.loggedOut) }
        nc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.set(.awake) }
    }

    /// If this process is still running well after announcing sleep or logout, that didn't happen (a cancelled
    /// logout, an app that blocked the restart, a wake whose notification never arrived). Without this the tablet
    /// could say "Mac is asleep" or "logged out" for good.
    private func unstick() {
        lock.lock()
        let s = _state, age = Date().timeIntervalSince(stateSince)
        lock.unlock()
        if (s == .sleeping && age > 90) || (s == .loggedOut && age > 120 && !Self.sessionInBackground()) || (s == .quitting && age > 30) {
            NSLog("Presence: still running \(Int(age)) s after \(s.rawValue); back to awake")
            set(.awake); setLocked(Self.screenIsLocked())
        }
    }

    /// Fast user switching: another user has the screen.
    static func sessionInBackground() -> Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["kCGSSessionOnConsoleKey"] as? NSNumber)?.boolValue == false
    }
}

// iokit_common_msg(x) = 0xE0000000 | x — these are C macros Swift can't import.
private let msgCanSystemSleep: UInt32 = 0xE000_0270
private let msgSystemWillSleep: UInt32 = 0xE000_0280
private let msgSystemHasPoweredOn: UInt32 = 0xE000_0300
private let msgSystemWillPowerOn: UInt32 = 0xE000_0320

private func powerCallback(refcon: UnsafeMutableRawPointer?, service: io_service_t, messageType: UInt32, messageArgument: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let me = Unmanaged<Presence>.fromOpaque(refcon).takeUnretainedValue()
    let arg = Int(bitPattern: messageArgument)
    switch messageType {
    case msgCanSystemSleep:
        IOAllowPowerChange(me.rootPort, arg)
    case msgSystemWillSleep:
        me.set(.sleeping)
        // Off the main thread, so a busy main thread can't hold up (or lose) the go-ahead to sleep.
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + Presence.announceDelay) { IOAllowPowerChange(me.rootPort, arg) }
    case msgSystemWillPowerOn, msgSystemHasPoweredOn:
        me.set(.awake)
    default:
        break
    }
}
