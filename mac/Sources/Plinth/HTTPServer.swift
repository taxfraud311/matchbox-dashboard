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
final class HTTPServer {
    typealias Handler = (HTTPRequest) -> HTTPResponse

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "plinth.http", attributes: .concurrent)
    private let handler: Handler
    private(set) var port: UInt16 = 0
    private(set) var lastError: String?
    var onStateChange: (() -> Void)?

    init(handler: @escaping Handler) { self.handler = handler }

    func start(port: UInt16, localOnly: Bool, bonjourName: String) {
        stop()
        self.port = port
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
            l.stateUpdateHandler = { [weak self] st in
                switch st {
                case .failed(let e): self?.lastError = "\(e)"; self?.onStateChange?()
                case .ready: self?.lastError = nil; self?.onStateChange?()
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
        var buffer = Data()
        func receive() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
                guard let self else { conn.cancel(); return }
                if let data { buffer.append(data) }
                if buffer.count > 2_000_000 { conn.cancel(); return }
                if let req = HTTPServer.parse(buffer, endpoint: conn.endpoint) {
                    let resp = self.handler(req)
                    self.send(resp, on: conn, head: req.method == "HEAD")
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
