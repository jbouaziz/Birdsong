//
//  Channel.swift
//  Pods
//
//  Created by Simon Manning on 24/06/2016.
//
//

import Foundation

open class Channel {
    
    public typealias ChannelResponseHandler = ((Channel, Response) -> ())
    public typealias ChannelPresenceHandler = ((Channel, Presence) -> ())
    
    // MARK: - Properties

    /// Topic
    open let topic: String
    
    /// Params sent when joining the channel.
    open let params: Socket.Payload
    
    /// Socket instance used to send an event.
    open weak var socket: Socket?
    
    /// Current channel state.
    internal(set) open var state: State = .closed

    /// Presence object.
    internal(set) open var presence: Presence = Presence()

    /// Dictionary of callbacks called when event occurs.
    /// `key` is the event name and `value` the associated callback.
    open var callbacks: [String: ChannelResponseHandler] = [:]
    
    /// Array of callbacks called when the presence state changes.
    open var presenceStateCallback: ChannelPresenceHandler?

    /// Instanciate a new Channel instance.
    ///
    /// - Parameters:
    ///   - socket: Socket to use to send messages.
    ///   - topic: Assigned topic.
    ///   - parameters: Parameters sent along with the `join` request.
    public init(socket: Socket, topic: String, parameters: Socket.Payload = [:]) {
        self.socket = socket
        self.topic = topic
        self.params = parameters

        // Register presence handling.
		on("presence_state") { (channel, response) in
			channel.presence.sync(response)
			channel.presenceStateCallback?(channel, channel.presence)
		}
		on("presence_diff") { (channel, response) in
			channel.presence.sync(response)
		}
    }
}

// MARK: - Control
public extension Channel {
    
    /// Join a channel by sending a Phoenix join event.
    ///
    /// - Returns: Associated push sent.
    @discardableResult
    open func join(force: Bool = false) -> Push? {
//        if state == .joined && !force {
//            return nil
//        }
        state = .joining
        
        return send(Socket.Event.Join, payload: params)?.receive("ok") { push, response in
            self.state = .joined
        }
    }
    
    /// Leave a channel by sending a Phoenix leave event.
    ///
    /// - Returns: Associated push sent.
    @discardableResult
    open func leave() -> Push? {
        state = .leaving
        
        return send(Socket.Event.Leave, payload: [:])?.receive("ok") {[weak self] push, response in
            guard let `self` = self else { return }
            self.callbacks.removeAll()
            self.presence.onJoin = nil
            self.presence.onLeave = nil
            self.presence.onStateChange = nil
            self.state = .closed
        }
    }
    
    /// Join a channel if it hasn't yet.
    ///
    /// - Parameter callback: Called upon completion.
    func joinIfNeeded(_ callback: @escaping ((_ error: PushError?, _ channel: Channel) -> Void)) {
        if state == .joined {
            callback(nil, self)
        } else {
            join()?.always() { (push) in
                callback(push.lastError, self)
            }
        }
    }
    
    /// Send an event using this channel.
    ///
    /// - Parameters:
    ///   - event: Event to send
    ///   - payload: Payload to tag along
    /// - Returns: Associated push sent.
    @discardableResult
    open func send(_ event: String, payload: Socket.Payload) -> Push? {
        let message = Push(event, topic: topic, payload: payload)
        return socket?.send(message)
    }
}

// MARK: - Callbacks
public extension Channel {
    
    /// Called when a certain event occurs on this channel.
    ///
    /// - Parameters:
    ///   - event: Event to watch.
    ///   - callback: Called when this event occurs.
    /// - Returns: Itself
    @discardableResult
    open func on(_ event: String, callback: @escaping (ChannelResponseHandler)) -> Self {
        callbacks[event] = callback
        return self
    }
    
    /// Called when the presence has been updated for this channel.
    ///
    /// - Parameter callback: Called when this event occurs.
    /// - Returns: Itself
    @discardableResult
    open func onPresenceUpdate(_ callback: @escaping (ChannelPresenceHandler)) -> Self {
        presenceStateCallback = callback
        return self
    }
}

// MARK: - Raw events
internal extension Channel {
    
    func received(_ response: Response) {
        callbacks[response.event]?(self, response)
    }
}

// MARK: - States
extension Channel {
    
    /// Enum describing the current Channel's state.
    public enum State: String {
        
        /// Closed
        case closed = "closed"
        
        /// An error occured
        case errored = "errored"
        
        /// Successfully joined
        case joined = "joined"
        
        /// Currently joining
        case joining = "joining"
        
        /// Currently leaving
        case leaving = "leaving"
    }
}

