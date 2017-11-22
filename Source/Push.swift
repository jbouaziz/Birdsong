//
//  Message.swift
//  Pods
//
//  Created by Simon Manning on 23/06/2016.
//
//

import Foundation

public enum PushError: Swift.Error {
    
    /// Invalid payload
    case invalidPayload
    
    /// Not connected
    case notConnected
}

extension PushError: LocalizedError {
    
    var localizedDescription: String {
        switch self {
        case .invalidPayload:
            return "Invalid payload request."
        case .notConnected:
            return "Not connected to socket."
        }
    }
}

public class Push {
    
    public typealias PushHandler = (Push, Socket.Payload) -> ()
    public typealias AlwaysHandler = (Push) -> ()
    
    /// Topic
    public let topic: String
    
    /// Event
    public let event: String
    
    /// Payload
    public let payload: Socket.Payload
    
    /// Unique ref
    let ref: Ref
    
    /// Unique join ref
    let joinRef: Ref

    /// Last received status.
    var receivedStatus: String?
    
    /// Last received response.
    var receivedResponse: Socket.Payload?
    
    /// Last error that occured.
    public var lastError: PushError?

    /// Map of status and callbacks.
    fileprivate var callbacks: [String: [PushHandler]] = [:]
    
    /// Array of callbacks.
    fileprivate var alwaysCallbacks: [AlwaysHandler] = []

    /// Create a new instance of this class using the parameters.
    ///
    /// - Parameters:
    ///   - event: Event
    ///   - topic: Topic
    ///   - payload: Payload
    ///   - ref: Unique ref, defaults to a `UUID` string.
    init(_ event: String, topic: String, payload: Socket.Payload, ref: Ref = Ref(), joinRef: Ref = Ref()) {
        (self.topic, self.event, self.payload, self.ref, self.joinRef) = (topic, event, payload, ref, joinRef)
    }
}

// MARK: - Callback registration
public extension Push {
    
    /// Register a callback to be called when a specific status occurs.
    ///
    /// - Parameters:
    ///   - status: Status to watch.
    ///   - callback: Called when that status occurs.
    /// - Returns: Itself
    @discardableResult
    public func receive(_ status: String, callback: @escaping (PushHandler)) -> Self {
        if receivedStatus == status,
            let receivedResponse = receivedResponse {
            callback(self, receivedResponse)
        }
        else {
            if (callbacks[status] == nil) {
                callbacks[status] = [callback]
            }
            else {
                callbacks[status]?.append(callback)
            }
        }
        
        return self
    }
    
    /// Register a callback to always me called when an event occurs on this instance.
    ///
    /// - Parameter callback: Callback to be called.
    /// - Returns: Itself
    @discardableResult
    public func always(_ callback: @escaping (AlwaysHandler)) -> Self {
        alwaysCallbacks.append(callback)
        return self
    }
}

// MARK: - Response handling
internal extension Push {
    
    func handleResponse(_ response: Response) {
        receivedStatus = response.payload["status"] as? String
        receivedResponse = response.payload
        lastError = nil
        
        fireCallbacksAndCleanup()
    }
    
    func handleParseError() {
        receivedStatus = "error"
        receivedResponse = ["reason": "Invalid payload request." as AnyObject]
        
        lastError = .invalidPayload
        
        fireCallbacksAndCleanup()
    }
    
    func handleNotConnected() {
        receivedStatus = "error"
        receivedResponse = ["reason": "Not connected to socket." as AnyObject]
        
        lastError = .notConnected
        
        fireCallbacksAndCleanup()
    }
    
    func fireCallbacksAndCleanup() {
        defer {
            callbacks.removeAll()
            alwaysCallbacks.removeAll()
        }
        
        guard let status = receivedStatus else {
            return
        }
        
        alwaysCallbacks.forEach({$0(self)})
        
        if let matchingCallbacks = callbacks[status],
            let receivedResponse = receivedResponse {
            matchingCallbacks.forEach({$0(self, receivedResponse)})
        }
    }
}

// MARK: - JSON Handling
extension Push {
    
    internal var jsonMap: [Any] {
        // The order is very specific to Phoenix and GraphQL and shouldn't be changed
        return [
            joinRef.string,
            ref.string,
            topic,
            event,
            payload,
        ]
    }
    
    func toJson() throws -> Data {
        return try JSONSerialization.data(withJSONObject: jsonMap,
                                          options: [])
    }
}

extension Push: CustomStringConvertible, CustomDebugStringConvertible {
    
    public var description: String {
        return jsonMap.description
    }
    
    public var debugDescription: String {
        return jsonMap.debugDescription
    }
}

public struct Ref: Hashable {
    
    private let _uuidString: String
    let prefix: String?
    var string: String {
        return (prefix ?? "") + _uuidString
    }
    
    init(prefix: String? = nil, value: String = UUID().uuidString.lowercased()) {
        self.prefix = prefix
        self._uuidString = value
    }
    
    public var hashValue: Int {
        return string.hashValue
    }
    
    public static func ==(lhs: Ref, rhs: Ref) -> Bool {
        return lhs.string == rhs.string
    }
}
