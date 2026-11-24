import AppKit
import IOKit.pwr_mgt

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
    var state: State {
        lock.lock(); defer { lock.unlock() }
        if let (s, until) = override, Date() < until { return s }
        if _state == .awake && _locked { return .locked }
        return _state
    }
    func set(_ s: State) { lock.lock(); _state = s; lock.unlock() }
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
        // Backstop in case a notification is missed.
        lockTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.setLocked(Self.screenIsLocked()) }
        let nc = NSWorkspace.shared.notificationCenter
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
        DispatchQueue.main.asyncAfter(deadline: .now() + Presence.announceDelay) { IOAllowPowerChange(me.rootPort, arg) }
    case msgSystemWillPowerOn, msgSystemHasPoweredOn:
        me.set(.awake)
    default:
        break
    }
}
