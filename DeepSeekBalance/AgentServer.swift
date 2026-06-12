import Foundation
import Network

// MARK: - 本地 HTTP 服务，供电脑端 Agent 连接读取数据

@available(iOS 17.0, *)
class AgentServer: NSObject {
    static let shared = AgentServer()

    private var listener: NWListener?
    private var port: UInt16 = 8080
    private(set) var isRunning = false
    var onStatusChange: ((Bool, String) -> Void)?

    var latestBalance: String = "0"
    var latestCurrency: String = "CNY"
    var latestMonthlyUsage: String = "0"
    var latestMonthlyCost: String = "0"
    var latestUsageJSON: String = "{}"

    var serverURL: String {
        guard isRunning else { return "" }
        // Try to get the device's local IP
        return "http://\(getIPAddress() ?? "localhost"):\(port)"
    }

    func start() {
        guard !isRunning else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.onStatusChange?(true, self?.serverURL ?? "")
                    case .failed(let error):
                        self?.isRunning = false
                        self?.onStatusChange?(false, "服务启动失败: \(error)")
                        // Try next port
                        self?.port += 1
                        self?.start()
                    case .cancelled:
                        self?.isRunning = false
                        self?.onStatusChange?(false, "服务已停止")
                    default:
                        break
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: .global())
        } catch {
            DispatchQueue.main.async {
                self.isRunning = false
                self.onStatusChange?(false, "服务启动失败: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        DispatchQueue.main.async {
            self.onStatusChange?(false, "服务已停止")
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        receiveRequest(connection)
    }

    private func receiveRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, let request = String(data: data, encoding: .utf8) {
                let response = self.handleHTTPRequest(request)
                connection.send(content: response, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } else if let error = error {
                print("[AgentServer] Receive error: \(error)")
                connection.cancel()
            } else if isComplete {
                connection.cancel()
            } else {
                self.receiveRequest(connection)
            }
        }
    }

    private func handleHTTPRequest(_ request: String) -> Data {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            return httpResponse(status: 400, body: "Bad Request")
        }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            return httpResponse(status: 400, body: "Bad Request")
        }

        let method = parts[0]
        let path = parts[1]

        if method == "GET" {
            switch path {
            case "/", "/status":
                return jsonResponse([
                    "status": "running",
                    "balance": latestBalance,
                    "currency": latestCurrency,
                    "monthlyUsage": latestMonthlyUsage,
                    "monthlyCost": latestMonthlyCost,
                    "endpoints": ["/balance", "/usage", "/cost", "/summary"]
                ])

            case "/balance":
                return jsonResponse([
                    "balance": latestBalance,
                    "currency": latestCurrency
                ])

            case "/usage":
                return jsonResponse([
                    "monthlyUsage": latestMonthlyUsage,
                    "monthlyCost": latestMonthlyCost
                ])

            case "/summary":
                return jsonResponse([
                    "balance": latestBalance,
                    "currency": latestCurrency,
                    "monthlyUsage": latestMonthlyUsage,
                    "monthlyCost": latestMonthlyCost
                ])

            case "/raw":
                // Return full cached JSON data
                if let data = latestUsageJSON.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    return jsonResponse(json)
                }
                return httpResponse(status: 404, body: "No data")

            default:
                return httpResponse(status: 404, body: "Not Found: \(path)")
            }
        }

        return httpResponse(status: 405, body: "Method Not Allowed")
    }

    private func httpResponse(status: Int, body: String) -> Data {
        let statusText = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Error")
        return "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: text/plain; charset=utf-8\r\nAccess-Control-Allow-Origin: *\r\n\r\n\(body)".data(using: .utf8) ?? Data()
    }

    private func jsonResponse(_ body: Any) -> Data {
        let json = (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .withoutEscapingSlashes]))
            ?? "{}".data(using: .utf8)!
        let bodyStr = String(data: json, encoding: .utf8) ?? "{}"
        return "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nAccess-Control-Allow-Origin: *\r\n\r\n\(bodyStr)".data(using: .utf8) ?? Data()
    }

    private func getIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }

        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" { // Wi-Fi
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}
