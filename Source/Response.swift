//
//  Response.swift
//  Pods
//
//  Created by Simon Manning on 23/06/2016.
//
//

import Foundation

open class Response {
    public let ref: Ref
    public let topic: String
    public let event: String
    public let payload: Socket.Payload

    init?(data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [Any],
                json.count == 5 else { return nil }
            
            ref = Ref(value: (json[1] as? String ?? ""))
            
            guard let topic = json[2] as? String,
                let event = json[3] as? String,
                let payload = json[4] as? Socket.Payload else {
                    return nil
            }
            self.topic = topic
            self.event = event
            self.payload = payload
            
        } catch {
            return nil
        }
    }
}
