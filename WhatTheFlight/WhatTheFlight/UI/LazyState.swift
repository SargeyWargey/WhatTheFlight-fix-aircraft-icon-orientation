//
//  LazyState.swift
//  WhatTheFlight
//
//  `@State private var camera = SkyCamera()` runs `SkyCamera()` every time the parent
//  re-creates the view (for a sheet over the radar, every tick and every compass update),
//  and SwiftUI throws all but the first away. `@StateObject` avoided that by taking an
//  autoclosure; `@State` doesn't. `@LazyState` brings it back for view-owned objects whose
//  initialisers open sessions, sensors or files: the object is made once, the first time
//  the view's body reads it, and kept for as long as the view keeps its identity.
//
//  Observation is unchanged: reading the object's properties in `body` tracks them as usual.
//

import SwiftUI

@propertyWrapper
struct LazyState<Object: AnyObject>: DynamicProperty {
    @State private var box = Box()
    private let make: () -> Object

    init(wrappedValue: @autoclosure @escaping () -> Object) {
        make = wrappedValue
    }

    /// Read it from `body`, `task` or an action, not from the view's `init` (SwiftUI hasn't
    /// attached the state yet there).
    var wrappedValue: Object { box.object(make) }

    private final class Box {
        private var object: Object?

        func object(_ make: () -> Object) -> Object {
            if let object { return object }
            let made = make()
            object = made
            return made
        }
    }
}
