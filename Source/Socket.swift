//
//  Socket.swift
//  Pods
//
//  Created by Simon Manning on 23/06/2016.
//
//

import Foundation
import Starscream

public final class Socket {
    // MARK: - Convenience aliases
    public typealias Payload = [String: Any]
    public typealias StateChangeHandler = ((_ old: ConnectionState, _ new: ConnectionState) -> Void)
    
    // MARK: - Properties
    
    fileprivate var socket: WebSocket
    public var enableLogging = true
    
    public var onConnect: (() -> ())?
    public var onDisconnect: ((Error?) -> ())?
    public var onResponse: ((Response) -> ())?
    public var onStateChange: StateChangeHandler?
    
    fileprivate(set) public var channels: [String: Channel] = [:]
    
    /// Interval in seconds at which a Heartbeat event will be sent.
    public var heartbeatInterval: TimeInterval = 30
    fileprivate static let HeartbeatPrefix = "hb-"
    fileprivate var heartbeatQueue: DispatchQueue
    
    fileprivate var awaitingResponses = [Ref: Push]()
    
    /// Current socket connection state.
    internal(set) open var state: ConnectionState = .initial {
        didSet { onStateChange?(oldValue, state) }
    }
    
    public var isConnected: Bool {
        return socket.isConnected
    }
    
    // MARK: - Initialisation
    
    public init(url: URL, params: [String: String]? = nil) {
        heartbeatQueue = DispatchQueue(label: "com.ecksd.birdsong.hbqueue")
        socket = WebSocket(url: url.appendQueryItems(params))
        socket.delegate = self
    }
    
    public convenience init(url: String, params: [String: String]? = nil) {
        if let parsedURL = URL(string: url) {
            self.init(url: parsedURL, params: params)
        }
        else {
            print("[Birdsong] Invalid URL in init. Defaulting to localhost URL.")
            self.init()
        }
    }
    
    public convenience init(prot: String = "http", host: String = "localhost", port: Int = 4000,
                            path: String = "socket", transport: String = "websocket",
                            params: [String: String]? = nil, selfSignedSSL: Bool = false) {
        let url = "\(prot)://\(host):\(port)/\(path)/\(transport)"
        self.init(url: url, params: params)
    }
    
    // MARK: - Connection
    
    public func connect() {
        guard !socket.isConnected else { return }
        
        log("Connecting to: \(socket.currentURL)")
        state = .connecting
        socket.connect()
    }
    
    public func disconnect() {
        guard socket.isConnected else { return }
        
        log("Disconnecting from: \(socket.currentURL)")
        state = .disconnecting
        socket.disconnect()
    }
    
    // MARK: - Channels
    
    public func channel(_ topic: String, payload: Payload = [:]) -> Channel {
        let channel = Channel(socket: self, topic: topic, parameters: payload)
        channels[topic] = channel
        return channel
    }
    
    public func remove(_ channel: Channel) {
        channel.leave()?.receive("ok") { [weak self] _, _ in
            self?.channels.removeValue(forKey: channel.topic)
        }
    }
    
    // MARK: - Heartbeat
    
    func sendHeartbeat() {
        guard socket.isConnected else { return }
        
        let ref = Ref(prefix: Socket.HeartbeatPrefix)
        _ = send(Push(Event.Heartbeat, topic: "phoenix", payload: [:], ref: ref))
        queueHeartbeat()
    }
    
    func queueHeartbeat() {
        heartbeatQueue.asyncAfter(deadline: .now() + heartbeatInterval) {
            self.sendHeartbeat()
        }
    }
    
    // MARK: - Sending data
    
    func send(_ event: String, topic: String, payload: Payload) -> Push {
        let push = Push(event, topic: topic, payload: payload)
        return send(push)
    }
    
    func send(_ message: Push) -> Push {
        if !socket.isConnected {
            message.handleNotConnected()
            return message
        }

        do {
            let data = try message.toJson()
            log("Sending: \(message.debugDescription)")
            
            awaitingResponses[message.ref] = message
            socket.write(data: data, completion: nil)
            
        } catch let error as NSError {
            log("Failed to send message: \(error)")
            message.handleParseError()
        }
        
        return message
    }
    
    @discardableResult
    open func handleMessage(_ text: String) -> Response {
        guard let data = text.data(using: .utf8),
            let response = Response(data: data) else {
                fatalError("Couldn't parse response: \(text)")
        }
        
        let ref = response.ref
        defer {
            awaitingResponses.removeValue(forKey: ref)
        }
        
        log("Received message: \(response.payload)")
        
        if let push = awaitingResponses[ref] {
            push.handleResponse(response)
        }
        
        channels[response.topic]?.received(response)
        onResponse?(response)
        
        return response
    }
}

// MARK: - Event constants

public extension Socket {
    
    open struct Event {
        public static let Heartbeat = "heartbeat"
        public static let Join = "phx_join"
        public static let Leave = "phx_leave"
        public static let Reply = "phx_reply"
        public static let Error = "phx_error"
        public static let Close = "phx_close"
    }
    
    open enum ConnectionState: String {
        case initial
        case connecting
        case connected
        case disconnecting
        case disconnected
    }
}

// MARK: - WebSocketDelegate

extension Socket: WebSocketDelegate {
    public func websocketDidConnect(socket: WebSocketClient) {
        log("Connected to: \(self.socket.currentURL)")
        state = .connected
        
        onConnect?()
        queueHeartbeat()
    }

    public func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        log("Disconnected from: \(self.socket.currentURL)")
        state = .disconnected
        
        onDisconnect?(error)

        // Reset state.
        awaitingResponses.removeAll()
        channels.removeAll()
    }

    public func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        handleMessage(text)
    }

    public func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        log("Received data: \(data)")
    }
}

// MARK: - Logging

extension Socket {
    fileprivate func log(_ message: String) {
        guard enableLogging else { return }
        
        print("[Birdsong] \(message)")
    }
}

// MARK: - Private URL helpers

fileprivate extension URL {
    
    func appendQueryItems(_ params: [String: String]?) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
            let items = params?.flatMap({ URLQueryItem(name: $0, value: $1) }) else {
                return self
        }
        components.queryItems?.append(contentsOf: items)
        
        guard let url = components.url else { fatalError("Problem with the URL") }
        
        return url
    }
}
