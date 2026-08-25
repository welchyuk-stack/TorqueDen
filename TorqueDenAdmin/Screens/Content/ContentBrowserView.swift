import SwiftUI

struct ContentBrowserView: View {
    @StateObject private var viewModel = ContentBrowserViewModel()
    @State private var confirmDelete: ContentItem?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .task { await viewModel.load() }
        .confirmationDialog(
            "Delete this item?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = confirmDelete {
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.delete(item)
                        confirmDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { confirmDelete = nil }
            }
        } message: {
            if let item = confirmDelete {
                Text("By @\(item.username): \(item.preview.prefix(80))\n\nThis cannot be undone.")
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundColor(.ember)
            Text("Content")
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            Picker("Type", selection: $viewModel.selectedType) {
                ForEach(ContentType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .onChange(of: viewModel.selectedType) { _, _ in
                Task { await viewModel.load() }
            }
            Button {
                Task { await viewModel.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            ContentUnavailableView(
                "Could Not Load",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if viewModel.items.isEmpty {
            ContentUnavailableView(
                "No \(viewModel.selectedType.label)",
                systemImage: "tray",
                description: Text("Nothing here yet.")
            )
        } else {
            List {
                ForEach(viewModel.items) { item in
                    ContentItemRow(item: item) {
                        confirmDelete = item
                    }
                }
                if viewModel.hasMore {
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMore {
                            ProgressView()
                        } else {
                            Button("Load more") {
                                Task { await viewModel.loadMore() }
                            }
                            .buttonStyle(.borderless)
                        }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Row

private struct ContentItemRow: View {
    let item: ContentItem
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview.isEmpty ? "(no content)" : item.preview)
                    .lineLimit(2)
                    .font(.body)
                HStack(spacing: 8) {
                    Text("@\(item.username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(item.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
