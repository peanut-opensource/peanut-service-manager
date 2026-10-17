import Foundation
import PeanutServiceIPC

private final class SupervisorServer: NSObject, NSXPCListenerDelegate, SupervisorXPCProtocol {
    private let listener: NSXPCListener
    private let requestQueue = DispatchQueue(label: "org.peanutopensource.PeanutServiceManager.supervisor.requests")
    private let runtime = ProcessRuntime()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    override init() {
        listener = NSXPCListener(machServiceName: SupervisorIPC.machServiceName)
        super.init()
        listener.delegate = self
    }

    func run() {
        listener.resume()
        dispatchMain()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: SupervisorXPCProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { }
        connection.resume()
        return true
    }

    func send(_ requestData: Data, reply: @escaping (Data) -> Void) {
        requestQueue.async { [weak self] in
            guard let self else { return }
            let response: SupervisorReply
            var requestID = UUID()
            do {
                let request = try self.decoder.decode(SupervisorRequest.self, from: requestData)
                requestID = request.id
                response = SupervisorReply(id: request.id, result: try self.handle(request.action))
            } catch {
                response = SupervisorReply(
                    id: requestID,
                    result: .failure(code: "request_failed", message: error.localizedDescription)
                )
            }
            guard let encoded = try? self.encoder.encode(response) else { return }
            reply(encoded)
        }
    }

    private func handle(_ action: SupervisorAction) throws -> SupervisorResult {
        switch action {
        case .start(let request):
            return .accepted(try runtime.start(request))
        case .stop(let serviceID, let force):
            return .accepted(try runtime.stop(serviceID: serviceID, force: force))
        case .list:
            return .services(runtime.snapshots())
        case .logs(let serviceID, let afterSequence):
            let result = runtime.logs(serviceID: serviceID, afterSequence: afterSequence)
            return .logs(entries: result.entries, nextSequence: result.nextSequence)
        }
    }
}

SupervisorServer().run()
