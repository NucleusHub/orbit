import NucleusUI
import SwiftUI

/// Search across every folder you can see (the web's SearchBar, 300 ms debounce).
struct SearchPage: View {
    @Environment(FilesStore.self) private var files
    @Environment(Navigator.self) private var navigator
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searching = false
    @State private var problem: String?
    @State private var selection: Set<String>?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            NucleusBackground()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    GlassCircleButton("chevron.left") { dismiss() }
                        .accessibilityLabel("Back")
                    NucleusSearchBar(text: $query, focused: $focused, prompt: "Search files and folders")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                results
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focused = true }
        .onDisappear { files.clearSearch() }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { files.clearSearch(); problem = nil; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            do {
                try await files.search(q)
                problem = nil
            } catch {
                if !Task.isCancelled { problem = error.orbitMessage }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if let problem {
            Spacer()
            NucleusEmptyState("exclamationmark.triangle", title: "Search failed", message: LocalizedStringKey(problem))
            Spacer()
        } else if let listing = files.searchResults, !query.isEmpty {
            if listing.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    NucleusEmptyState("magnifyingglass", title: "No results", message: "Nothing matches “\(query)”.")
                    Button("Clear") { query = "" }.buttonStyle(NucleusSecondaryButtonStyle()).fixedSize()
                }
                Spacer()
                Spacer()
            } else {
                ScrollView {
                    ItemsView(listing: listing, actions: ItemActions(files: files, navigator: navigator, folderID: nil),
                              mode: preferences.viewMode, selection: $selection)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        } else if searching {
            Spacer()
            ProgressView()
            Spacer()
        } else {
            Spacer()
            NucleusEmptyState("magnifyingglass", title: "Search Orbit", message: "Find files and folders by name, in every folder you can see.")
            Spacer()
            Spacer()
        }
    }
}
