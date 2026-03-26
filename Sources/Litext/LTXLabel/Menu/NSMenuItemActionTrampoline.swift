//
//  NSMenuItemActionTrampoline.swift
//  Litext
//

#if canImport(AppKit)
    import AppKit

    final class NSMenuItemActionTrampoline: NSObject {
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
            super.init()
        }

        @objc func performAction(_ sender: Any?) {
            action()
        }
    }

    extension NSMenu {
        func addItem(withTitle title: String, image: NSImage? = nil, handler: @escaping () -> Void) {
            let trampoline = NSMenuItemActionTrampoline(action: handler)
            let item = NSMenuItem(
                title: title,
                action: #selector(NSMenuItemActionTrampoline.performAction(_:)),
                keyEquivalent: ""
            )
            item.target = trampoline
            item.representedObject = trampoline
            item.image = image
            addItem(item)
        }
    }
#endif
