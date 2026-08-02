import SwiftUI

enum Theme {
    enum Panel {
        static let width: CGFloat = 360
        static let height: CGFloat = 460
        static let cornerRadius: CGFloat = 14
        static let menuBarGap: CGFloat = 6
    }

    enum Space {
        static let tight: CGFloat = 6
        static let regular: CGFloat = 10
        static let roomy: CGFloat = 16
    }

    enum Colour {
        static let active = Color.green
        static let card = Color.primary.opacity(0.055)
        static let border = Color.primary.opacity(0.08)
    }
}

struct CaffeineCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        self.content
            .padding(Theme.Space.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colour.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).stroke(Theme.Colour.border)
            }
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = Theme.Colour.active
    var showsDot = true

    var body: some View {
        HStack(spacing: 5) {
            if self.showsDot {
                Circle()
                    .fill(self.color)
                    .frame(width: 7, height: 7)
            }
            Text(self.text)
                .foregroundStyle(self.showsDot ? Color.primary : Color.secondary)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.08)))
    }
}
