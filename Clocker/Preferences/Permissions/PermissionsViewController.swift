// Copyright © 2015 Abhishek Banthia

import Cocoa
import SwiftUI

class PermissionsViewController: ParentViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingView = NSHostingView(rootView: PermissionsView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

extension NSView {
    func applyShadow() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = Themer.shared().textBackgroundColor().cgColor
    }
}

extension NSButton {
    func setBackgroundColor(color: NSColor) {
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }
}
