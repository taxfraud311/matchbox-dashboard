import Foundation
import Network

struct HTTPRequest {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data
    var isLoopback: Bool
}

struct HTTPResponse {
    var status: Int = 200
    var headers: [String: String] = [:]
    var body: Data = Data()

    static func json(_ obj: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.fragmentsAllowed])) ?? Data("null".utf8)
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8",
                                                      "Cache-Control": "no-store"], body: data)
    }
    static func text(_ s: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "text/plain; charset=utf-8"], body: Data(s.utf8))
    }
    static func redirect(_ to: String) -> HTTPResponse {
        HTTPResponse(status: 302, headers: ["Location": to], body: Data())
    }
}

/// A deliberately small HTTP/1.1 server: one request per connection, Connection: close.
///
/// Connections are read and written on a serial queue that never blocks, and requests are answered on a separate
/// worker queue, so slow requests (thumbnails, detail sheets) can't hold up the tablet's once-a-second metrics poll.
/// The listener restarts itself if the network stack fails it (Wi-Fi changes, sleep/wake).
final class HTTPServer {
    typealias Handler = (HTTPRequest) -> HTTPResponse
    /// Answers a request later without holding a thread (returns false to leave it to the normal handler).
    typealias AsyncHandler = (HTTPRequest, @escaping (HTTPResponse) -> Void) -> Bool

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "plinth.http.io", qos: .userInitiated)
    private let work = DispatchQueue(label: "plinth.http.work", qos: .userInitiated, attributes: .concurrent)
    /// The metrics poll gets a lane of its own.
    private let fast = DispatchQueue(label: "plinth.http.fast", qos: .userInteractive)
    private let handler: Handler
    var asyncHandler: AsyncHandler?
    private(set) var port: UInt16 = 0
    private(set) var lastError: String?
    var onStateChange: (() -> Void)?
    private var config: (UInt16, Bool, String)?
    private var restartPending = false
    private(set) var restarts = 0

    init(handler: @escaping Handler) { self.handler = handler }

    /// Starts again with the same settings (after a failure, or when the Mac wakes).
    func restart(after delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let c = self.config else { return }
            self.restartPending = false
            self.restarts += 1
            self.start(port: c.0, localOnly: c.1, bonjourName: c.2)
        }
    }

    var isReady: Bool { if case .ready = listener?.state { return true }; return false }

    func start(port: UInt16, localOnly: Bool, bonjourName: String) {
        stop()
        self.port = port
        config = (port, localOnly, bonjourName)
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            if localOnly {
                params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
            }
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            if !localOnly {
                l.service = NWListener.Service(name: bonjourName, type: "_plinth._tcp")
            }
            l.newConnectionHandler = { [weak self] c in self?.handle(c) }
            l.stateUpdateHandler = { [weak self, weak l] st in
                guard let self, let l, l === self.listener else { return }
                switch st {
                case .failed(let e):
                    self.lastError = "\(e)"; self.onStateChange?()
                    DispatchQueue.main.async { if !self.restartPending { self.restartPending = true; self.restart(after: 2) } }
                case .waiting(let e):
                    // Usually the port is briefly unavailable after a network change; try again shortly.
                    self.lastError = "\(e)"; self.onStateChange?()
                    DispatchQueue.main.async { if !self.restartPending { self.restartPending = true; self.restart(after: 5) } }
                case .ready: self.lastError = nil; self.onStateChange?()
                default: break
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            lastError = error.localizedDescription
            onStateChange?()
        }
    }

    func stop() { listener?.cancel(); listener = nil }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        // A client that connects and never finishes its request (or a dropped Wi-Fi link) is cut off after 20 s,
        // so stale connections can't pile up over days.
        queue.asyncAfter(deadline: .now() + 20) { if conn.state != .cancelled { conn.cancel() } }
        var buffer = Data()
        func receive() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
                guard let self else { conn.cancel(); return }
                if let data { buffer.append(data) }
                if buffer.count > 2_000_000 { conn.cancel(); return }
                if let req = HTTPServer.parse(buffer, endpoint: conn.endpoint) {
                    let head = req.method == "HEAD"
                    let reply: (HTTPResponse) -> Void = { resp in self.queue.async { self.send(resp, on: conn, head: head) } }
                    if let a = self.asyncHandler, a(req, reply) { return }
                    (req.path == "/api/metrics" ? self.fast : self.work).async { reply(self.handler(req)) }
                } else if done || err != nil {
                    conn.cancel()
                } else {
                    receive()
                }
            }
        }
        receive()
    }

    private func send(_ r: HTTPResponse, on conn: NWConnection, head: Bool) {
        let reason = [200: "OK", 204: "No Content", 302: "Found", 304: "Not Modified", 400: "Bad Request",
                      403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 500: "Internal Server Error"][r.status] ?? "OK"
        var h = "HTTP/1.1 \(r.status) \(reason)\r\n"
        var headers = r.headers
        headers["Content-Length"] = String(r.body.count)
        headers["Connection"] = "close"
        if headers["Cache-Control"] == nil { headers["Cache-Control"] = "no-cache" }
        for (k, v) in headers { h += "\(k): \(v)\r\n" }
        h += "\r\n"
        var out = Data(h.utf8)
        if !head { out.append(r.body) }
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    static func parse(_ data: Data, endpoint: NWEndpoint) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for l in lines {
            if let i = l.firstIndex(of: ":") {
                headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let len = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        if data.count - bodyStart < len { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + len))

        let target = String(first[1])
        let comps = URLComponents(string: "http://x" + target)
        var q: [String: String] = [:]
        for item in comps?.queryItems ?? [] { q[item.name] = item.value ?? "" }

        var loop = false
        if case let .hostPort(host, _) = endpoint {
            switch host {
            case .ipv4(let a): loop = a.isLoopback
            case .ipv6(let a): loop = a.isLoopback || a.asIPv4?.isLoopback == true
            case .name(let n, _): loop = n == "localhost"
            @unknown default: loop = false
            }
        }
        return HTTPRequest(method: String(first[0]), path: comps?.percentEncodedPath.removingPercentEncoding ?? "/",
                           query: q, headers: headers, body: body, isLoopback: loop)
    }
}

enum MIME {
    static func type(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "woff2": return "font/woff2"
        case "apk": return "application/vnd.android.package-archive"
        case "ico": return "image/x-icon"
        default: return "application/octet-stream"
        }
    }
}
