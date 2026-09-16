import AppKit
import ClipStackCore
import SwiftUI

/// The popup contents: a native macOS list of clipboard entries, newest first,
/// with pinned items lifted to their own section on top.
struct PopupView: View {
    @Bindable var model: PopupModel

    var body: some View {
        VStack(spacing: 0) {
            header

            if !model.hasAccessibility {
                accessibilityBanner
            }

            Divider()

            if model.store.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Clipboard")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if !model.store.items.isEmpty {
                Button("Clear") {
                    model.store.clearUnpinned()
                    model.resetSelection()
                }
                .buttonStyle(.accessoryBar)
                .font(.system(size: 11))
                .help("Remove everything except pinned items")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Pasting needs Accessibility. Selecting still copies.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Enable…") { Permissions.openAccessibilitySettings() }
                .buttonStyle(.accessoryBar)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
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
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
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
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
    }

    private func row(_ item: ClipboardItem) -> some View {
        ItemRow(
            item: item,
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
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing copied yet")
                .font(.system(size: 13, weight: .medium))
            Text("Copy something and it will show up here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

// MARK: - Row

private struct ItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onActivate: () -> Void
    let onHover: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon

            VStack(alignment: .leading, spacing: 3) {
                content
                Text(item.createdAt, format: .relative(presentation: .named))
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.75) : Color.secondary)
            }

            Spacer(minLength: 0)

            trailingControls
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
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
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .white.opacity(0.8) : Color.secondary)
                .frame(width: 16, height: 16)
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
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: "photo")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .white.opacity(0.8) : Color.secondary)
                .frame(width: 16, height: 16)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .text:
            Text(item.textValue ?? "")
                .font(.system(size: 12))
                .lineLimit(3)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .multilineTextAlignment(.leading)
        case .image:
            Text(item.previewText)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
    }

    private var trailingControls: some View {
        HStack(spacing: 2) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : Color.secondary)
                    .rotationEffect(.degrees(45))
            }

            Menu {
                Button(item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
                Button("Delete", action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18)
            // Kept in the layout at all times so rows do not reflow on hover.
            .opacity(isHovering || isSelected ? 1 : 0)
        }
        .padding(.top, 1)
    }
}
