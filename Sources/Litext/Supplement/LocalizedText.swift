//
//  LocalizedText.swift
//  Litext
//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation

//
// Make sure to add following key to Info.plist
//
// **Localized resources can be mixed** -> true
//

private let localizationBundle: Bundle = {
    #if SWIFT_PACKAGE
    return .module
    #else
    return .main
    #endif
}()

public enum LocalizedText {
    public static let copy = NSLocalizedString("Copy", bundle: localizationBundle, comment: "Copy menu item")
    public static let selectAll = NSLocalizedString("Select All", bundle: localizationBundle, comment: "Select all menu item")
    public static let share = NSLocalizedString("Share", bundle: localizationBundle, comment: "Share menu item")
    public static let search = NSLocalizedString("Search", bundle: localizationBundle, comment: "Search index menu item")
    public static let openLink = NSLocalizedString("Open Link", bundle: localizationBundle, comment: "Open link menu item")
    public static let copyLink = NSLocalizedString("Copy Link", bundle: localizationBundle, comment: "Copy link menu item")
}
