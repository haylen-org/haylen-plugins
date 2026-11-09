import Foundation
import dnssd

// A service of the app that DNS-SD advertises on the local network, by its type, the name that people see and the port where the app listens, while the app owns the socket itself. The registration answers on the main queue with the name that the network took, which differs from the name asked for when another service of the network holds it, and stops with `stop`.
@MainActor
final class LocalNetworkAdvertisement {
    struct Advertised: Encodable, Sendable {
        let name: String
        let type: String
        let port: Int
    }

    private let type: String
    private let name: String
    private let port: Int
    private var reference: DNSServiceRef?
    private var answer: CheckedContinuation<Advertised, any Error>?

    init(type: String, name: String, port: Int) {
        self.type = type
        self.name = name
        self.port = port
    }

    // Registers the service and returns once the network took a name for it. Throws a `HaylenFailure` with the code `failed` when the system refuses the registration.
    func start() async throws -> Advertised {
        try await withCheckedThrowingContinuation { continuation in
            answer = continuation
            let context = Unmanaged.passUnretained(self).toOpaque()
            var created: DNSServiceRef?
            let error = DNSServiceRegister(&created, 0, 0, name, type, nil, nil, UInt16(port).bigEndian, 0, nil, { _, _, error, name, _, _, context in
                guard let context else {
                    return
                }
                let advertisement = Unmanaged<LocalNetworkAdvertisement>.fromOpaque(context).takeUnretainedValue()
                let taken = name.map { String(cString: $0) }
                MainActor.assumeIsolated {
                    advertisement.registered(error, name: taken)
                }
            }, context)

            guard error == kDNSServiceErr_NoError, let created else {
                registered(error, name: nil)
                return
            }
            DNSServiceSetDispatchQueue(created, .main)
            reference = created
        }
    }

    // Ends the advertisement, after which no answer of the registration arrives.
    func stop() {
        if let reference {
            DNSServiceRefDeallocate(reference)
        }
        reference = nil
        answer?.resume(throwing: HaylenFailure("The app stopped the advertisement of \"\(name)\" before the network took it.", code: "cancelled"))
        answer = nil
    }

    private func registered(_ error: DNSServiceErrorType, name taken: String?) {
        guard let answer else {
            return
        }
        self.answer = nil

        guard error == kDNSServiceErr_NoError, let taken else {
            stop()
            answer.resume(throwing: HaylenFailure("The system did not advertise the service \"\(name)\" of the type \"\(type)\", with the error \(error) of DNS-SD.", code: "failed"))
            return
        }
        answer.resume(returning: Advertised(name: taken, type: type, port: port))
    }
}
