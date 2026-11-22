import SwiftUI

/// A parent row that is itself selectable (it carries `tag`) and expands to its children, on the system
/// `DisclosureGroup` inside a sidebar `List`. Expansion is remembered per window (`@SceneStorage`, key
/// `storageKey`), expanded by default. With no children it is a plain row with no disclosure arrow.
/// Figma part: Sidebar (11:1768), disclosure row.
public struct SidebarDisclosureRow<Tag: Hashable, Children: View>: View {
    let title: String
    let systemImage: String
    let tag: Tag
    let hasChildren: Bool
    @ViewBuilder let children: () -> Children
    @SceneStorage private var isExpanded: Bool

    public init(_ title: String, systemImage: String, tag: Tag, storageKey: String, hasChildren: Bool,
                @ViewBuilder children: @escaping () -> Children) {
        self.title = title
        self.systemImage = systemImage
        self.tag = tag
        self.hasChildren = hasChildren
        self.children = children
        _isExpanded = SceneStorage(wrappedValue: true, storageKey)
    }

    public var body: some View {
        if hasChildren {
            DisclosureGroup(isExpanded: $isExpanded) {
                children()
            } label: {
                SidebarRow(title, systemImage: systemImage).tag(tag)
            }
        } else {
            SidebarRow(title, systemImage: systemImage).tag(tag)
        }
    }
}
