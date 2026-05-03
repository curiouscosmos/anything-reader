//
//  FreeBooksView.swift
//  Anything Reader
//
//  Free books catalog screen backed by the locally downloaded SQLite database.
//

import SwiftUI

struct FreeBooksView: View {
    @StateObject private var store = FreeBooksCatalogStore.shared
    @Binding var searchText: String
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedHTMLBook: FreeBook?

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                header
                filterBar

                if store.isDownloadingDatabase {
                    downloadProgressCard
                } else if !store.isDatabaseDownloaded {
                    downloadPromptCard
                } else if store.isLoadingBooks {
                    loadingCard
                } else if store.books.isEmpty {
                    emptyCatalogCard
                } else {
                    booksGrid
                }

                if let errorMessage = store.errorMessage {
                    errorCard(errorMessage)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .task {
                await store.loadCatalogIfNeeded()
                await store.setSearchText(searchText)
            }
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: 300_000_000)
                    } catch {
                        return
                    }

                    guard !Task.isCancelled else { return }
                    await store.setSearchText(newValue)
                }
            }
            .navigationDestination(item: $selectedHTMLBook) { book in
                FreeBookHTMLViewerView(book: book)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Free Books")
                .font(.largeTitle.weight(.bold))

            Text("Browse the downloaded catalog of free books and use the search bar above to find titles, authors, categories, or shelves.")
                .font(.headline)
                .foregroundStyle(.secondary)

            if store.isDatabaseDownloaded, store.totalBooksCount > store.books.count {
                Text("Showing \(store.books.count) of \(store.totalBooksCount) books. Load more to continue browsing.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 16) {
            filterMenu(
                title: "Language",
                selectedTitle: store.selectedLanguageFilter.displayName,
                menuIdentifier: "free-books-language-filter-menu"
            ) {
                ForEach(FreeBookLanguageFilter.allCases) { filter in
                    Button {
                        Task {
                            await store.setLanguageFilter(filter)
                        }
                    } label: {
                        if store.selectedLanguageFilter == filter {
                            Label(filter.displayName, systemImage: "checkmark")
                        } else {
                            Text(filter.displayName)
                        }
                    }
                }
            }

            filterMenu(
                title: "Category",
                selectedTitle: store.selectedCategoryFilter.displayName,
                menuIdentifier: "free-books-category-filter-menu"
            ) {
                Button {
                    Task {
                        await store.setCategoryFilter(.all)
                    }
                } label: {
                    if store.selectedCategoryFilter == .all {
                        Label(FreeBookCategoryFilter.all.displayName, systemImage: "checkmark")
                    } else {
                        Text(FreeBookCategoryFilter.all.displayName)
                    }
                }

                ForEach(FreeBookCategoryFilter.menuSections, id: \.self) { section in
                    Section(section) {
                        ForEach(FreeBookCategoryFilter.filters(in: section)) { filter in
                            Button {
                                Task {
                                    await store.setCategoryFilter(filter)
                                }
                            } label: {
                                if store.selectedCategoryFilter == filter {
                                    Label(filter.displayName, systemImage: "checkmark")
                                } else {
                                    Text(filter.displayName)
                                }
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                Task {
                    await store.resyncCatalog()
                }
            } label: {
                Label("Resync Database", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(store.isDownloadingDatabase || store.isLoadingBooks || store.isLoadingMoreBooks)
            .accessibilityIdentifier("free-books-resync-database-button")
        }
    }

    private func filterMenu<Content: View>(
        title: String,
        selectedTitle: String,
        menuIdentifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text("\(title):")
                .font(.headline)
                .foregroundStyle(.secondary)

            Menu(content: content) {
                Label(selectedTitle, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .accessibilityIdentifier(menuIdentifier)
        }
    }

    private var booksGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(store.books) { book in
                    FreeBookCardView(
                        book: book,
                        onView: {
                            selectedHTMLBook = book
                        }
                    )
                }
            }

            if store.isLoadingMoreBooks {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading more books...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else if store.books.count < store.totalBooksCount {
                Button {
                    Task {
                        await store.loadNextPage()
                    }
                } label: {
                    Label("Load More Books", systemImage: "arrow.down.circle")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
                .accessibilityIdentifier("free-books-load-more-button")
            }

            if store.totalBooksCount > 0 {
                Text("Showing \(store.books.count) of \(store.totalBooksCount) books.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 40)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var downloadPromptCard: some View {
        infoCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Catalog not downloaded", systemImage: "square.and.arrow.down")
                    .font(.headline)

                Text("Download the books database to start browsing free books.")
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await store.downloadCatalog()
                    }
                } label: {
                    Label("Download Books Database", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("free-books-download-database-button")
            }
        }
    }

    private var downloadProgressCard: some View {
        infoCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Downloading catalog", systemImage: "arrow.down.circle.fill")
                    .font(.headline)

                ProgressView()
                    .controlSize(.large)

                Text("The SQLite database is being downloaded and validated locally.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loadingCard: some View {
        infoCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Loading books", systemImage: "books.vertical.fill")
                    .font(.headline)

                ProgressView()
                    .controlSize(.large)

                Text("Reading the downloaded catalog.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyCatalogCard: some View {
        infoCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("No books found", systemImage: "books.vertical")
                    .font(.headline)

                Text("The catalog downloaded successfully, but the books table did not return any rows.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        infoCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Free books error", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)

                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
