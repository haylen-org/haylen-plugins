import Combine
import Foundation
import Network

// Finds the services of one type on the local network with `NWBrowser` for the list of the picker, and resolves the one the person picks into the address and the port the app connects to, through a connection of `NWConnection` that it closes once the path to the service is known. The system shows its local network prompt the first time the browser starts.
@MainActor
final class LocalNetworkBrowser: ObservableObject {
    // A service of the list, by the name that people see, which the network keeps unique for each type.
    struct Service: Identifiable, Hashable, Sendable {
        let name: String
        let endpoint: NWEndpoint

        var id: String { name }
    }

    // What the screen answers: the service, its address and its port, and every address that the path to it took.
    struct Picked: Encodable, Sendable {
        let name: String
        let type: String
        let host: String
        let port: Int
        let addresses: [String]
    }

    struct Failure: Error, Sendable {
        let message: String
        let code: String
    }

    let type: String

    @Published private(set) var services: [Service] = []
    @Published private(set) var problem: String?
    @Published private(set) var resolving: String?

    private var browser: NWBrowser?
    private var connection: NWConnection?

    init(type: String) {
        self.type = type
    }

    func start() {
        let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                self?.update(results)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                self?.browserChanged(state)
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
    }

    // Connects to the service until the path to it is known, then answers its address and port and stops the search. A UDP service is ready without an answer of the peer, once its name resolved.
    func resolve(_ service: Service, completion: @escaping @MainActor (Result<Picked, Failure>) -> Void) {
        connection?.cancel()
        resolving = service.name
        problem = nil

        let parameters: NWParameters = type.hasSuffix("._udp") ? .udp : .tcp
        let connection = NWConnection(to: service.endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                self?.connectionChanged(state, service: service, completion: completion)
            }
        }
        self.connection = connection
        connection.start(queue: .main)
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var found: [String: Service] = [:]
        for result in results {
            if case .service(let name, _, _, _) = result.endpoint {
                found[name] = Service(name: name, endpoint: result.endpoint)
            }
        }
        services = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // A browser waits while the system does not let the app reach the local network, such as before the person answers the prompt or after the person refused it, and the list says so.
    private func browserChanged(_ state: NWBrowser.State) {
        switch state {
        case .failed(let error):
            problem = "The search for services failed: \(error.localizedDescription)"
        case .waiting(let error):
            problem = "The search for services waits: \(error.localizedDescription)"
        case .ready:
            problem = nil
        default:
            break
        }
    }

    private func connectionChanged(_ state: NWConnection.State, service: Service, completion: @escaping @MainActor (Result<Picked, Failure>) -> Void) {
        guard let connection, resolving == service.name else {
            return
        }

        switch state {
        case .ready:
            let endpoint = connection.currentPath?.remoteEndpoint
            connection.cancel()
            self.connection = nil
            resolving = nil
            guard case .hostPort(let host, let port) = endpoint else {
                completion(.failure(Failure(message: "The path to the service \"\(service.name)\" names no address.", code: "unreachable")))
                return
            }
            let address = Self.text(of: host)
            stop()
            completion(.success(Picked(name: service.name, type: type, host: address, port: Int(port.rawValue), addresses: [address])))
        case .waiting(let error), .failed(let error):
            connection.cancel()
            self.connection = nil
            resolving = nil
            problem = "The service \"\(service.name)\" does not answer: \(error.localizedDescription)"
        default:
            break
        }
    }

    // The text of the address, as the module `socket` of the app takes it, without the interface that the description of an address of `Network` adds after a `%`.
    private static func text(of host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address):
            return address.rawValue.map { String($0) }.joined(separator: ".")
        case .ipv6(let address):
            var buffer = [UInt8](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            _ = address.rawValue.withUnsafeBytes { bytes in
                buffer.withUnsafeMutableBufferPointer { text in
                    inet_ntop(AF_INET6, bytes.baseAddress, UnsafeMutableRawPointer(text.baseAddress!).assumingMemoryBound(to: CChar.self), socklen_t(text.count))
                }
            }
            return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        case .name(let name, _):
            return name
        @unknown default:
            return "\(host)"
        }
    }
}
