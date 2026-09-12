import Foundation
import Darwin

/// No GUI, accounts or storage: run the executable inside the signed probe
/// bundle and consume its exit status. The 5-second watchdog bounds the test.
final class ProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func finish(_ message: String, code: Int32) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        print(message)
        fflush(stdout)
        exit(code)
    }
}

let completion = ProbeCompletion()
let rejectService = CommandLine.arguments.contains("--reject-service")
#if STANDALONE_PROBE
let expectedService = ProbeIdentity.host
#else
let expectedService = ProbeIdentity.service
#endif
let identifier = rejectService ? "com.chatterbat.not-the-service" : expectedService
guard let requirement = ProbeIdentity.requirement(identifier: identifier) else {
    completion.finish("PROBE_CONFIGURATION_FAILED", code: 3)
    exit(3)
}
let nonce = UUID()
#if STANDALONE_PROBE
let connection = NSXPCConnection(machServiceName: ProbeIdentity.machService, options: [])
#else
let connection = NSXPCConnection(serviceName: ProbeIdentity.service)
#endif
connection.remoteObjectInterface = NSXPCInterface(with: ProbeServiceProtocol.self)
connection.setCodeSigningRequirement(requirement)
connection.interruptionHandler = { @Sendable [completion] in completion.finish("PROBE_CONNECTION_INTERRUPTED", code: 2) }
connection.invalidationHandler = { @Sendable [completion] in completion.finish("PROBE_CONNECTION_REJECTED_OR_INVALIDATED", code: 2) }
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable [completion] _ in
    completion.finish("PROBE_REQUEST_REJECTED", code: 2)
} as? ProbeServiceProtocol
guard let proxy, let request = try? JSONEncoder().encode(ProbePing(version: ProbeCodec.version, nonce: nonce)) else {
    completion.finish("PROBE_CONFIGURATION_FAILED", code: 3)
    exit(3)
}
DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
    completion.finish("PROBE_TIMEOUT", code: 4)
}
proxy.ping(request) { response in
    DispatchQueue.main.async {
        guard connection.effectiveUserIdentifier == geteuid(), ProbeCodec.validate(response, nonce: nonce) else {
            completion.finish("PROBE_INVALID_RESPONSE", code: 5)
            return
        }
        completion.finish("PROBE_PONG_VERIFIED", code: 0)
    }
}
dispatchMain()