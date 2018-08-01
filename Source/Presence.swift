//
//  Presence.swift
//  Pods
//
//  Created by Simon Manning on 6/07/2016.
//
//

import Foundation

public final class Presence {
    // MARK: - Convenience typealiases

    public typealias PresenceState = [String: [Meta]]
    public typealias Diff = [String: [String: Any]]
    public typealias Meta = [String: Any]

    // MARK: - Properties

    fileprivate(set) public var state: PresenceState

    // MARK: - Callbacks

    public var onJoin: ((_ id: String, _ meta: Meta) -> ())?
    public var onLeave: ((_ id: String, _ meta: Meta) -> ())?
    public var onStateChange: ((_ state: PresenceState) -> ())?

    // MARK: - Initialisation

    init(state: PresenceState = Presence.PresenceState()) {
        self.state = state
    }

    // MARK: - Syncing
    
    public func sync(_ diff: Response) {
        
        diff.payload.forEach { id, entry in
            
            if diff.event == "presence_state" {
                // Initial state event
                if let entry = entry as? [String: Any],
                    var metas = entry["metas"] as? [Meta] {
                    
                    // Because of how the socket returns metas in the wrong place,
                    // get everything outside of the metas inside the metas instead.
                    //
                    // They're doing that because this data is coming off directly from the DB
                    // and can't be inserted inside the first `metas` object.
                    let toMove = entry.filter { $0.key != "metas" }
                    metas.append(toMove)
                    
                    state[id] = metas
                }
            }
                
            else if diff.event == "presence_diff", let stateDiff = entry as? Diff {
                
                let diffStateKey = id // ids can be [`joins`, `leaves`]
                
                // Leaves
                if diffStateKey == "leaves" {
                    state.removeValue(forKey: id)
                }
                stateDiff.forEach { id, entry in
                    
                    if var metas = entry["metas"] as? [Meta] {
                        
                        // Because of how the socket returns metas in the wrong place,
                        // get everything outside of the metas inside the metas instead.
                        //
                        // They're doing that because this data is coming off directly from the DB
                        // and can't be inserted inside the first `metas` object.
                        let toMove = entry.filter { $0.key != "metas" }
                        metas.append(toMove)
                        
                        // Based on the required sync, call the appropriate callback
                        if diffStateKey == "leaves" {
                            // Leaves
                            metas.forEach { onLeave?(id, $0) }
                            
                        } else if diffStateKey == "joins" {
                            // Joins
                            state[id] = metas
                            
                            metas.forEach { onJoin?(id, $0) }
                        }
                    }
                }
            }
        }
        
        onStateChange?(state)
    }

    // MARK: - Presence access convenience

    public func metas(id: String) -> [Meta]? {
        return state[id]
    }

    public func firstMeta(id: String) -> Meta? {
        return state[id]?.first
    }

    public func firstMetas() -> [String: Meta] {
        var result = [String: Meta]()
        state.forEach { id, metas in
            result[id] = metas.first
        }

        return result
    }

    public func firstMetaValue<T>(id: String, key: String) -> T? {
        guard let meta = state[id]?.first, let value = meta[key] as? T else {
            return nil
        }

        return value
    }

    public func firstMetaValues<T>(key: String) -> [T] {
        var result = [T]()
        state.forEach { id, metas in
            if let meta = metas.first, let value = meta[key] as? T {
                result.append(value)
            }
        }

        return result
    }
}
