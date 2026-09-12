import Foundation
import Darwin

final class PingService: NSObject, ProbeServiceProtocol {
    func ping(_ request: Data, withReply reply: @escaping @Sendable (Data) -> Void) {
        reply(ProbeCodec.respond(to: request))
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        #if HOST_PROBE
        let expected = ProbeIdentity.hostClientRequirement()
        #else
        let expected = ProbeIdentity.requirement(identifier: ProbeIdentity.client)
        #endif
        guard connection.effectiveUserIdentifier == geteuid(),
              let requirement = expected else { return false }
        // serviceListener does not support listener-wide requirements; enforce
        // it on each accepted connection BEFORE resume/message delivery.
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: ProbeServiceProtocol.self)
        connection.exportedObject = PingService()
        connection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
#if HOST_PROBE
let listener = NSXPCListener(machServiceName: ProbeIdentity.machService)
guard let requirement = ProbeIdentity.hostClientRequirement() else { exit(3) }
listener.setConnectionCodeSigningRequirement(requirement)
listener.delegate = delegate
listener.resume()
dispatchMain()
#else
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
#endif