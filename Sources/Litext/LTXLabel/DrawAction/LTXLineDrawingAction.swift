//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation

/// Nonisolated so `LTXTextLayout` can run drawing actions from background
/// tile renders; handlers must stick to Core Graphics work on the passed
/// context (all in-tree handlers draw bullets/quote bars and do).
public nonisolated class LTXLineDrawingAction: NSObject {
    public typealias ActionHandler = (CGContext, CTLine, CGPoint) -> Void

    public var action: ActionHandler

    public init(action: @escaping ActionHandler) {
        self.action = action
        super.init()
    }
}
