// Copyright © 2015 Abhishek Banthia

import Cocoa
import SwiftUI

struct AboutUsConstants {
    static let GitHubURL = "https://github.com/abhishekbanthia/Clocker/?ref=ClockerApp"
    static let PayPalURL = "https://paypal.me/abhishekbanthia1712"
    static let TwitterLink = "https://twitter.com/clocker_support/?ref=ClockerApp"
    static let TwitterFollowIntentLink = "https://twitter.com/intent/follow?screen_name=clocker_support"
    static let AppStoreLink = "macappstore://itunes.apple.com/us/app/clocker/id1056643111?action=write-review"
    static let AppStoreUpdateLink = "macappstore://itunes.apple.com/us/app/clocker/id1056643111"
    static let CrowdInLocalizationLink = "https://crwd.in/clocker"
    static let FAQsLink = "https://abhishekbanthia.com/clocker/faq"
}

class AboutViewController: ParentViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingView = NSHostingView(rootView: AboutView())
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
