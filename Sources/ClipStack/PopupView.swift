import AppKit
import ClipStackCore
import SwiftUI

/// The popup contents: a native macOS list of clipboard entries, newest first,
/// with pinned items lifted to their own section on top.
struct PopupView: View {
    @Bindable var model: PopupModel

    /// Every hardcoded point size below is a baseline multiplied through this,
    /// so one setting moves the frame and the type together.
    private var panelSize: PanelSize { model.panelSize }

    var body: some View {
        VStack(spacing: 0) {
            header

            if !model.hasAccessibility {
                accessibilityBanner
            }

            if let message = model.entitlement.bannerMessage {
                licenseBanner(message)
            }

            // No point offering filters over an empty history.
            if !model.store.items.isEmpty {
                searchPill
                categoryChips
            }

            Divider()

            if model.store.items.isEmpty {
                emptyState
            } else if model.visibleItems.isEmpty {
                noMatchesState
            } else {
                list
            }
        }
    }

    // MARK: - Filters

    /// Read-only by design: the panel owns key handling, so typing goes straight
    /// into the query and every existing shortcut keeps working. The pill is
    /// always visible because type-to-search is invisible otherwise.
    private var searchPill: some View {
        HStack(spacing: panelSize.scaled(6)) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: panelSize.scaled(11)))
                .foregroundStyle(.secondary)

            if model.searchQuery.isEmpty {
                Text("Type to search")
                    .font(.system(size: panelSize.scaled(12)))
                    .foregroundStyle(.tertiary)
            } else {
                Text(model.searchQuery)
                    .font(.system(size: panelSize.scaled(12)))
                    .lineLimit(1)
                    // The tail is what you just typed, so drop characters off the front.
                    .truncationMode(.head)
            }

            Spacer(minLength: 0)

            if !model.searchQuery.isEmpty {
                Button {
                    model.searchQuery = ""
                    model.resetSelection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: panelSize.scaled(11)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, panelSize.scaled(8))
        .padding(.vertical, panelSize.scaled(5))
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, panelSize.scaled(12))
        .padding(.bottom, panelSize.scaled(7))
    }

    private var categoryChips: some View {
        HStack(spacing: panelSize.scaled(4)) {
            ForEach(ItemCategory.allCases, id: \.self) { chip($0) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, panelSize.scaled(12))
        .padding(.bottom, panelSize.scaled(8))
    }

    private func chip(_ category: ItemCategory) -> some View {
        let isActive = model.category == category
        return Button {
            model.select(category: category)
        } label: {
            Text(category.title)
                .font(.system(size: panelSize.scaled(11), weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.white : Color.secondary)
                .padding(.horizontal, panelSize.scaled(8))
                .padding(.vertical, panelSize.scaled(3))
                .background(
                    Capsule().fill(isActive ? Color.accentColor : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help("Show \(category.title.lowercased())")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: panelSize.scaled(6)) {
            Text("Clipboard")
                .font(.system(size: panelSize.scaled(13), weight: .semibold))

            Spacer()

            if !model.store.items.isEmpty {
                Button("Clear") {
                    model.store.clearUnpinned()
                    model.resetSelection()
                }
                .buttonStyle(.accessoryBar)
                .font(.system(size: panelSize.scaled(11)))
                .help("Remove everything except pinned items")
            }
        }
        .padding(.horizontal, panelSize.scaled(12))
        .padding(.vertical, panelSize.scaled(9))
    }

    private var accessibilityBanner: some View {
        HStack(spacing: panelSize.scaled(6)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Pasting needs Accessibility. Selecting still copies.")
                .font(.system(size: panelSize.scaled(11)))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Enable…") { Permissions.openAccessibilitySettings() }
                .buttonStyle(.accessoryBar)
                .font(.system(size: panelSize.scaled(11)))
        }
        .padding(.horizontal, panelSize.scaled(12))
        .padding(.bottom, panelSize.scaled(8))
    }

    /// Only ever shown when there is something to act on — never for a healthy licence.
    private func licenseBanner(_ message: String) -> some View {
        HStack(spacing: panelSize.scaled(6)) {
            Image(systemName: model.entitlement.capturesClipboard
                  ? "clock.badge.exclamationmark"
                  : "exclamationmark.triangle.fill")
                .foregroundStyle(model.entitlement.capturesClipboard ? .orange : .red)
            Text(message)
                .font(.system(size: panelSize.scaled(11)))
                .foregroundStyle(.secondary)
            Spacer()
            Button(model.entitlement.isPaid ? "Fix…" : "Activate…") { model.onActivate() }
                .buttonStyle(.accessoryBar)
                .font(.system(size: panelSize.scaled(11)))
        }
        .padding(.horizontal, panelSize.scaled(12))
        .padding(.bottom, panelSize.scaled(8))
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: panelSize.scaled(2), pinnedViews: [.sectionHeaders]) {
                    if !model.pinnedItems.isEmpty {
                        Section {
                            ForEach(model.pinnedItems) { row($0) }
                        } header: {
                            sectionHeader("Pinned")
                        }
                    }

                    if !model.recentItems.isEmpty {
                        Section {
                            ForEach(model.recentItems) { row($0) }
                        } header: {
                            // Only worth a header when there is a Pinned section
                            // above it to distinguish from.
                            if !model.pinnedItems.isEmpty {
                                sectionHeader("Recent")
                            }
                        }
                    }
                }
                .padding(.horizontal, panelSize.scaled(6))
                .padding(.vertical, panelSize.scaled(6))
            }
            .onChange(of: model.selectedID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: panelSize.scaled(10), weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, panelSize.scaled(8))
            .padding(.top, panelSize.scaled(6))
            .padding(.bottom, panelSize.scaled(3))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
    }

    private func row(_ item: ClipboardItem) -> some View {
        ItemRow(
            item: item,
            panelSize: panelSize,
            isSelected: model.selectedID == item.id,
            onActivate: { model.onPaste(item) },
            onHover: { model.selectedID = item.id },
            onTogglePin: { model.store.togglePin(id: item.id) },
            onDelete: {
                model.selectedID = item.id
                model.deleteSelected()
            }
        )
        .id(item.id)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: panelSize.scaled(8)) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: panelSize.scaled(30), weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing copied yet")
                .font(.system(size: panelSize.scaled(13), weight: .medium))
            Text("Copy something and it will show up here.")
                .font(.system(size: panelSize.scaled(11)))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, panelSize.scaled(24))
    }

    /// The history has items, the filter just hid all of them — a different
    /// situation from having copied nothing, and it needs a way out.
    private var noMatchesState: some View {
        VStack(spacing: panelSize.scaled(8)) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: panelSize.scaled(30), weight: .light))
                .foregroundStyle(.tertiary)
            Text("No matches")
                .font(.system(size: panelSize.scaled(13), weight: .medium))
            Text(model.searchQuery.isEmpty
                 ? "Nothing in this category yet."
                 : "Nothing here matches “\(model.searchQuery)”.")
                .font(.system(size: panelSize.scaled(11)))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Clear filters") { model.clearFilters() }
                .buttonStyle(.accessoryBar)
                .font(.system(size: panelSize.scaled(11)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, panelSize.scaled(24))
    }
}

// MARK: - Row

private struct ItemRow: View {
    let item: ClipboardItem
    let panelSize: PanelSize
    let isSelected: Bool
    let onActivate: () -> Void
    let onHover: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: panelSize.scaled(8)) {
            icon

            VStack(alignment: .leading, spacing: panelSize.scaled(3)) {
                content
                Text(item.createdAt, format: .relative(presentation: .named))
                    .font(.system(size: panelSize.scaled(10)))
                    .foregroundStyle(isSelected ? .white.opacity(0.75) : Color.secondary)
            }

            Spacer(minLength: 0)

            trailingControls
        }
        .padding(.horizontal, panelSize.scaled(8))
        .padding(.vertical, panelSize.scaled(7))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { hovering in
            isHovering = hovering
            if hovering { onHover() }
        }
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
            Button("Delete", action: onDelete)
        }
    }

    private var background: Color {
        if isSelected { return Color.accentColor }
        if isHovering { return Color.primary.opacity(0.07) }
        return .clear
    }

    @ViewBuilder
    private var icon: some View {
        switch item.type {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: panelSize.scaled(11)))
                .foregroundStyle(isSelected ? .white.opacity(0.8) : Color.secondary)
                .frame(width: panelSize.scaled(16), height: panelSize.scaled(16))
        case .image:
            thumbnail
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = item.thumbnailData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: panelSize.scaled(40), height: panelSize.scaled(40))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: "photo")
                .font(.system(size: panelSize.scaled(11)))
                .foregroundStyle(isSelected ? .white.opacity(0.8) : Color.secondary)
                .frame(width: panelSize.scaled(16), height: panelSize.scaled(16))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .text:
            Text(item.textValue ?? "")
                .font(.system(size: panelSize.scaled(12)))
                .lineLimit(3)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .multilineTextAlignment(.leading)
        case .image:
            Text(item.previewText)
                .font(.system(size: panelSize.scaled(12)))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
    }

    private var trailingControls: some View {
        HStack(spacing: panelSize.scaled(2)) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: panelSize.scaled(9)))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : Color.secondary)
                    .rotationEffect(.degrees(45))
            }

            Menu {
                Button(item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
                Button("Delete", action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: panelSize.scaled(11), weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .frame(width: panelSize.scaled(18), height: panelSize.scaled(18))
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: panelSize.scaled(18))
            // Kept in the layout at all times so rows do not reflow on hover.
            .opacity(isHovering || isSelected ? 1 : 0)
        }
        .padding(.top, panelSize.scaled(1))
    }
}
