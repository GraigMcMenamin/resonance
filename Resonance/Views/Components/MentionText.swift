//
//  MentionText.swift
//  Resonance
//

import SwiftUI

/// Renders text with `@username` tokens displayed in purple and tappable.
/// When a mention is tapped, `onMentionTap` is called with the username (without the @ prefix).
struct MentionText: View {
    let content: String
    var onMentionTap: ((String) -> Void)? = nil

    var body: some View {
        Text(attributedContent)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "resonance", url.host == "user" else { return .systemAction }
                onMentionTap?(url.lastPathComponent)
                return .handled
            })
    }

    private var attributedContent: AttributedString {
        var result = AttributedString()
        guard let regex = try? NSRegularExpression(pattern: #"@(\w+)"#) else {
            return AttributedString(content)
        }
        let nsContent = content as NSString
        let matches = regex.matches(
            in: content,
            range: NSRange(location: 0, length: nsContent.length)
        )
        var cursor = 0

        for match in matches {
            let matchStart = match.range.location
            // Append plain text before this mention
            if matchStart > cursor {
                let plain = nsContent.substring(with: NSRange(location: cursor, length: matchStart - cursor))
                result.append(AttributedString(plain))
            }
            // Append styled @mention with tappable link
            let mentionStr = nsContent.substring(with: match.range)
            let usernameStr = nsContent.substring(with: match.range(at: 1))
            var segment = AttributedString(mentionStr)
            segment.foregroundColor = Color(red: 0.6, green: 0.4, blue: 0.8)
            if let url = URL(string: "resonance://user/\(usernameStr)") {
                segment.link = url
            }
            result.append(segment)
            cursor = match.range.location + match.range.length
        }

        // Append any remaining plain text
        if cursor < nsContent.length {
            let remaining = nsContent.substring(with: NSRange(location: cursor, length: nsContent.length - cursor))
            result.append(AttributedString(remaining))
        }

        return result
    }
}
