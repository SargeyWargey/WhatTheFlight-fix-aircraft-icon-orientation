//
//  WhatTheFlightWidgets.swift
//  WhatTheFlightWidgets
//
//  Home Screen / Lock Screen widgets and the Sky Watch Live Activity. Model, catalog and
//  feed code is shared with the app (see the target's file membership in the project).
//

import WidgetKit
import SwiftUI

@main
struct WhatTheFlightWidgets: WidgetBundle {
    var body: some Widget {
        NearestFlightWidget()
        NextOverheadWidget()
        SkyWatchLiveActivity()
        FlightFollowLiveActivity()
    }
}
