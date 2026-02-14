// Copyright © 2015 Abhishek Banthia

import SwiftUI
import CoreLoggerKit

struct AboutView: View {
    private let versionString: String = {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") ?? "Clocker"
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "N/A"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "N/A"
        return "\(appName) \(shortVersion) (\(buildVersion))"
    }()

    var body: some View {
        VStack(spacing: 15) {
            Text(versionString)
                .font(.custom("Avenir-Light", size: 28))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("ClockerVersion")

            Image("ClockerIcon-512")
                .resizable()
                .frame(width: 100, height: 100)

            Text("Feedback is always welcome:".localized())
                .font(.custom("Avenir-Light", size: 15))

            linkButton(
                title: "Help localize Clocker in your language by clicking here!",
                underlineRange: 42..<56,
                font: .custom("Avenir-Light", size: 15),
                accessibilityID: "ClockerOpenSourceText"
            ) {
                openURL(AboutUsConstants.CrowdInLocalizationLink, logEvent: "Opened Localization Link",
                        metadata: ["Language": Locale.preferredLanguages.first ?? ""])
            }

            linkButton(
                title: "You can support Clocker by leaving a review on the App Store! :)",
                underlineRange: 27..<60,
                font: .custom("Avenir-Heavy", size: 15),
                accessibilityID: "ClockerSupportText"
            ) {
                openURL(AboutUsConstants.AppStoreLink, logEvent: "Open App Store to Review",
                        metadata: ["Country": Locale.autoupdatingCurrent.region?.identifier ?? ""])
            }

            linkButton(
                title: "1. @clocker_support on Twitter for quick comments",
                underlineRange: 3..<19,
                font: .custom("Avenir-Light", size: 15)
            ) {
                openURL(AboutUsConstants.TwitterLink, logEvent: "Opened Twitter",
                        metadata: ["Country": Locale.autoupdatingCurrent.region?.identifier ?? ""])
            }

            linkButton(
                title: "2. For Private Feedback",
                underlineRange: 7..<22,
                font: .custom("Avenir-Light", size: 15),
                accessibilityID: "ClockerPrivateFeedback"
            ) {
                openURL("https://github.com/nickhumbir/clocker/issues", logEvent: "Report Issue Opened",
                        metadata: ["Country": Locale.autoupdatingCurrent.region?.identifier ?? ""])
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func linkButton(
        title: String,
        underlineRange: Range<Int>,
        font: Font,
        accessibilityID: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            buildAttributedText(title, underlineRange: underlineRange, font: font)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .ifLet(accessibilityID) { view, id in
            view.accessibilityIdentifier(id)
        }
    }

    private func buildAttributedText(_ text: String, underlineRange: Range<Int>, font: Font) -> Text {
        let startIndex = text.index(text.startIndex, offsetBy: underlineRange.lowerBound)
        let endIndex = text.index(text.startIndex, offsetBy: min(underlineRange.upperBound, text.count))

        let before = String(text[text.startIndex..<startIndex])
        let underlined = String(text[startIndex..<endIndex])
        let after = String(text[endIndex..<text.endIndex])

        return Text(before).font(font) +
               Text(underlined).font(font).underline() +
               Text(after).font(font)
    }

    private func openURL(_ urlString: String, logEvent: String, metadata: [String: Any]) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
        Logger.log(object: metadata, for: logEvent as NSString)
    }
}

private extension View {
    @ViewBuilder
    func ifLet<T>(_ value: T?, transform: (Self, T) -> some View) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}
