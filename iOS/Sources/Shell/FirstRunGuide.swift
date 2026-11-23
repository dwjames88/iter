import SwiftUI
import IterUI

/// What the first-run guide says: three short pages, Find, Trips, Go. Plain data so a test can check it stays short.
enum FirstRunPage: Int, CaseIterable, Identifiable {
    case find, trips, go

    var id: Int { rawValue }

    var symbol: String {
        switch self {
        case .find: "magnifyingglass"
        case .trips: "car.side"
        case .go: "location.north.line"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .find: "Find Places to Shoot"
        case .trips: "Plan a Trip"
        case .go: "Go and Shoot"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .find: "Search for a place or ask for spots. Each one shows its light score for the day, from the weather and the sun."
        case .trips: "Add places to a trip and Iter lays out the days, the drives and the best time at each stop."
        case .go: "On the day, Go follows the plan: where to be, when to leave, and when the light turns."
        }
    }
}

/// The iPhone's first-run guide: one sheet, shown once. It only explains. Location is asked at launch as always and nothing here
/// waits on, repeats or gates that. "Continue" pages through; the last page's "Get Started" closes it.
struct FirstRunGuide: View {
    let onDone: () -> Void
    @State private var page: FirstRunPage = .find

    private var isLast: Bool { page == FirstRunPage.allCases.last }

    var body: some View {
        VStack(spacing: IterSpace.lg) {
            TabView(selection: $page) {
                ForEach(FirstRunPage.allCases) { item in
                    VStack(spacing: IterSpace.lg) {
                        Spacer(minLength: 0)
                        Image(systemName: item.symbol)
                            .font(.system(size: 56, weight: .regular))
                            .foregroundStyle(IterColor.accentText)
                            .accessibilityHidden(true)
                        Text(item.title)
                            .font(IterFont.titleSection)
                            .foregroundStyle(IterColor.textPrimary)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text(item.message)
                            .font(IterFont.body)
                            .foregroundStyle(IterColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, IterSpace.xl)
                    .tag(item)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // The system's page dots are white-on-light here, so the guide draws its own in the accent.
            HStack(spacing: IterSpace.sm) {
                ForEach(FirstRunPage.allCases) { item in
                    Circle()
                        .fill(item == page ? IterColor.accent : IterColor.textTertiary.color.opacity(0.35))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Page \(page.rawValue + 1) of \(FirstRunPage.allCases.count)", comment: "First-run guide: page indicator"))

            Button {
                if isLast { onDone() } else { withAnimation { page = FirstRunPage(rawValue: page.rawValue + 1) ?? page } }
            } label: {
                Text(isLast ? "Get Started" : "Continue", comment: "First-run guide button")
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, IterSpace.xl)
            .padding(.bottom, IterSpace.lg)
        }
        .background(IterColor.backgroundWindow)
    }
}
