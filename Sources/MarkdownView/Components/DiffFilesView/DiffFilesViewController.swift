import Foundation

#if canImport(UIKit)
    import UIKit

    /// Where the lines requested by a context expansion sit relative to the
    /// hunk that is being grown.
    public enum DiffContextDirection: Hashable, Sendable {
        /// Lines directly above a hunk.
        case up
        /// Lines directly below a hunk.
        case down
        /// The whole gap between two hunks, revealed by a single tap.
        case all
    }

    /// A request for the pre-image lines hidden between (or around) two hunks.
    public struct DiffContextRequest: Hashable, Sendable {
        /// Path of the file the section renders, as shown in its header.
        public let filePath: String
        /// 1-based, inclusive line numbers in the *old* file.
        public let oldLineRange: ClosedRange<Int>
        public let direction: DiffContextDirection

        public init(
            filePath: String,
            oldLineRange: ClosedRange<Int>,
            direction: DiffContextDirection
        ) {
            self.filePath = filePath
            self.oldLineRange = oldLineRange
            self.direction = direction
        }
    }

    /// Renders a unified patch as a collection view with one **section per
    /// file**: the file's header pins to the top while its hunks scroll, and
    /// the gaps the patch omits become expander rows that pull in more of the
    /// original file on tap.
    ///
    /// ```swift
    /// let controller = DiffFilesViewController(patch: patch, language: "swift")
    /// controller.fileLineCountProvider = { path in sources[path]?.count }
    /// controller.contextProvider = { request in
    ///     try await api.lines(of: request.filePath, in: request.oldLineRange)
    /// }
    /// ```
    ///
    /// Expanders only appear once a `contextProvider` is set, and the expander
    /// below the last hunk additionally needs `fileLineCountProvider` — without
    /// the file's length there is no way to know whether more lines follow.
    public final class DiffFilesViewController: UIViewController {
        /// Theme used for every hunk. Block headers are always suppressed
        /// inside sections, since the section header names the file.
        public var theme: MarkdownTheme = .default {
            didSet {
                collectionView.backgroundColor = DiffFilesViewConfiguration.backgroundColor(theme: theme)
                collectionView.collectionViewLayout.invalidateLayout()
                reloadEverything()
            }
        }

        /// Lines revealed by one tap on an expander arrow.
        public var expansionChunkSize: Int = DiffPatchDocument.defaultExpansionChunkSize {
            didSet { applySnapshot(animated: false) }
        }

        /// Supplies the hidden pre-image lines for an expander. Expanders are
        /// hidden while this is `nil`.
        public var contextProvider: (@MainActor (DiffContextRequest) async throws -> [String])? {
            didSet { applySnapshot(animated: false) }
        }

        /// Total line count of a file's pre-image, keyed by the path shown in
        /// the section header. Enables the expander below the last hunk.
        public var fileLineCountProvider: (@MainActor (String) -> Int?)? {
            didSet { applySnapshot(animated: false) }
        }

        /// Called when `contextProvider` throws, so hosts can surface the error.
        public var expansionFailureHandler: ((DiffContextRequest, any Error) -> Void)?

        /// Called when a file's section header is tapped to collapse or expand
        /// the file.
        public var fileCollapseHandler: ((String, Bool) -> Void)?

        public private(set) var patch: String = ""

        private var document = DiffPatchDocument(files: [], language: nil)
        private var collapsedFileIDs: Set<Int> = []
        private var loadingExpansions: Set<ExpansionKey> = []

        private struct ExpansionKey: Hashable {
            let expander: DiffExpander
            let direction: DiffExpander.Direction
        }

        private lazy var collectionView: UICollectionView = .init(
            frame: .zero,
            collectionViewLayout: makeLayout()
        )
        private var dataSource: UICollectionViewDiffableDataSource<Int, DiffFileItem>!

        public init(patch: String, language: String? = nil, theme: MarkdownTheme = .default) {
            self.theme = theme
            super.init(nibName: nil, bundle: nil)
            setPatch(patch, language: language)
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Replaces the rendered patch, resetting collapse and expansion state.
        public func setPatch(_ patch: String, language: String? = nil) {
            self.patch = patch
            document = DiffPatchDocument(patch: patch, language: language)
                ?? .init(files: [], language: language)
            collapsedFileIDs = []
            loadingExpansions = []
            guard isViewLoaded else { return }
            applySnapshot(animated: false)
        }

        /// Paths of the rendered files, in patch order.
        public var filePaths: [String] {
            document.files.map(\.displayPath)
        }

        override public func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = DiffFilesViewConfiguration.backgroundColor(theme: theme)
            configureCollectionView()
            configureDataSource()
            applySnapshot(animated: false)
        }

        /// Scrolls the file with the given path to the top of the viewport.
        public func scrollToFile(at path: String, animated: Bool = true) {
            guard let index = document.files.firstIndex(where: { $0.displayPath == path }),
                  dataSource.snapshot().numberOfItems(inSection: document.files[index].id) > 0
            else { return }
            collectionView.scrollToItem(
                at: IndexPath(item: 0, section: index),
                at: .top,
                animated: animated
            )
        }

        // MARK: - Setup

        private func configureCollectionView() {
            collectionView.backgroundColor = DiffFilesViewConfiguration.backgroundColor(theme: theme)
            collectionView.alwaysBounceVertical = true
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(collectionView)
            NSLayoutConstraint.activate([
                collectionView.topAnchor.constraint(equalTo: view.topAnchor),
                collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        private func makeLayout() -> UICollectionViewLayout {
            let configuration = UICollectionViewCompositionalLayoutConfiguration()
            configuration.interSectionSpacing = DiffFilesViewConfiguration.sectionSpacing

            return UICollectionViewCompositionalLayout(
                sectionProvider: { [weak self] _, _ in
                    let theme = self?.theme ?? .default
                    let itemSize = NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .estimated(DiffFilesViewConfiguration.estimatedItemHeight(theme: theme))
                    )
                    let item = NSCollectionLayoutItem(layoutSize: itemSize)
                    let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
                    let section = NSCollectionLayoutSection(group: group)

                    let header = NSCollectionLayoutBoundarySupplementaryItem(
                        layoutSize: .init(
                            widthDimension: .fractionalWidth(1),
                            heightDimension: .absolute(DiffFilesViewConfiguration.headerHeight(theme: theme))
                        ),
                        elementKind: UICollectionView.elementKindSectionHeader,
                        alignment: .top
                    )
                    // Sticky file headers: the header of the file being scrolled
                    // stays put until the next file pushes it off.
                    header.pinToVisibleBounds = true
                    header.zIndex = 2
                    section.boundarySupplementaryItems = [header]
                    return section
                },
                configuration: configuration
            )
        }

        private func configureDataSource() {
            let hunkRegistration = UICollectionView.CellRegistration<DiffHunkCell, DiffFileItem> {
                [weak self] cell, _, item in
                guard let self,
                      case let .hunk(fileID, hunkID) = item,
                      let file = document.file(withID: fileID),
                      let hunkIndex = file.hunks.firstIndex(where: { $0.id == hunkID })
                else { return }
                cell.configure(
                    renderBlock: file.renderBlock(forHunkAt: hunkIndex),
                    theme: theme
                )
            }

            let expanderRegistration = UICollectionView.CellRegistration<DiffExpanderCell, DiffFileItem> {
                [weak self] cell, _, item in
                guard let self, case let .expander(expander) = item else { return }
                cell.configure(
                    expander: expander,
                    theme: theme,
                    loadingDirections: loadingDirections(for: expander)
                ) { [weak self] direction in
                    self?.expandContext(for: expander, direction: direction)
                }
            }

            dataSource = .init(collectionView: collectionView) { collectionView, indexPath, item in
                switch item {
                case .hunk:
                    collectionView.dequeueConfiguredReusableCell(
                        using: hunkRegistration,
                        for: indexPath,
                        item: item
                    )
                case .expander:
                    collectionView.dequeueConfiguredReusableCell(
                        using: expanderRegistration,
                        for: indexPath,
                        item: item
                    )
                }
            }

            let headerRegistration = UICollectionView.SupplementaryRegistration<DiffFileHeaderView>(
                elementKind: UICollectionView.elementKindSectionHeader
            ) { [weak self] header, _, indexPath in
                guard let self, document.files.indices.contains(indexPath.section) else { return }
                let file = document.files[indexPath.section]
                header.configure(
                    file: file,
                    theme: theme,
                    isCollapsed: collapsedFileIDs.contains(file.id)
                ) { [weak self] in
                    self?.toggleCollapse(fileID: file.id)
                }
            }

            dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
                collectionView.dequeueConfiguredReusableSupplementary(
                    using: headerRegistration,
                    for: indexPath
                )
            }
        }

        // MARK: - Snapshots

        private func applySnapshot(animated: Bool, reconfiguringFileWithID fileID: Int? = nil) {
            guard isViewLoaded, dataSource != nil else { return }

            var snapshot = NSDiffableDataSourceSnapshot<Int, DiffFileItem>()
            snapshot.appendSections(document.files.map(\.id))
            for file in document.files {
                guard !collapsedFileIDs.contains(file.id) else { continue }
                snapshot.appendItems(items(for: file), toSection: file.id)
            }

            if let fileID {
                let hunkItems = snapshot.itemIdentifiers(inSection: fileID).filter {
                    if case .hunk = $0 { return true }
                    return false
                }
                snapshot.reconfigureItems(hunkItems)
            }
            dataSource.apply(snapshot, animatingDifferences: animated)
        }

        private func reloadEverything() {
            guard isViewLoaded, dataSource != nil else { return }
            var snapshot = dataSource.snapshot()
            snapshot.reloadSections(snapshot.sectionIdentifiers)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        private func items(for file: DiffFilePatch) -> [DiffFileItem] {
            let hunkItems = file.hunks.map { DiffFileItem.hunk(fileID: file.id, hunkID: $0.id) }
            guard contextProvider != nil else { return hunkItems }
            return document.items(
                forFileWithID: file.id,
                chunkSize: expansionChunkSize,
                totalOldLineCount: fileLineCountProvider?(file.displayPath)
            )
        }

        private func reconfigure(item: DiffFileItem) {
            var snapshot = dataSource.snapshot()
            guard snapshot.indexOfItem(item) != nil else { return }
            snapshot.reconfigureItems([item])
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        private func toggleCollapse(fileID: Int) {
            let isCollapsed = collapsedFileIDs.contains(fileID)
            if isCollapsed {
                collapsedFileIDs.remove(fileID)
            } else {
                collapsedFileIDs.insert(fileID)
            }
            applySnapshot(animated: true)
            if let file = document.file(withID: fileID) {
                fileCollapseHandler?(file.displayPath, !isCollapsed)
            }
        }

        // MARK: - Context expansion

        private func loadingDirections(for expander: DiffExpander) -> Set<DiffExpander.Direction> {
            Set(
                loadingExpansions
                    .filter { $0.expander == expander }
                    .map(\.direction)
            )
        }

        private func expandContext(for expander: DiffExpander, direction: DiffExpander.Direction) {
            guard let provider = contextProvider,
                  let file = document.file(withID: expander.fileID)
            else { return }

            let key = ExpansionKey(expander: expander, direction: direction)
            guard !loadingExpansions.contains(key) else { return }
            loadingExpansions.insert(key)
            reconfigure(item: .expander(expander))

            let range = expander.requestedRange(for: direction, chunkSize: expansionChunkSize)
            let request = DiffContextRequest(
                filePath: file.displayPath,
                oldLineRange: range,
                direction: expander.coversEntireGap ? .all : DiffContextDirection(direction)
            )

            Task { [weak self] in
                do {
                    let lines = try await provider(request)
                    guard let self else { return }
                    loadingExpansions.remove(key)
                    document.insertContext(
                        lines: lines,
                        forOldLineRange: range,
                        fileID: expander.fileID,
                        direction: direction,
                        expander: expander
                    )
                    applySnapshot(animated: false, reconfiguringFileWithID: expander.fileID)
                } catch {
                    guard let self else { return }
                    loadingExpansions.remove(key)
                    reconfigure(item: .expander(expander))
                    expansionFailureHandler?(request, error)
                }
            }
        }
    }

    private extension DiffContextDirection {
        init(_ direction: DiffExpander.Direction) {
            switch direction {
            case .up: self = .up
            case .down: self = .down
            case .both: self = .all
            }
        }
    }
#endif
