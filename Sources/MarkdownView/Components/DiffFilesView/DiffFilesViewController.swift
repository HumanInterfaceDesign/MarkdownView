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

        /// Live line-selection updates: the display path of the file being
        /// selected in, and the selection (`nil` when it clears). A selection
        /// spans one hunk; selecting in another hunk clears the previous one.
        /// Line selection is enabled while either selection handler is set.
        public var lineSelectionHandler: ((String, LineSelectionInfo?) -> Void)? {
            didSet { reloadEverything() }
        }

        /// Fires once the selection gesture settles (tap completes, drag ends),
        /// with the same arguments as `lineSelectionHandler`.
        public var lineSelectionEndedHandler: ((String, LineSelectionInfo?) -> Void)? {
            didSet { reloadEverything() }
        }

        /// Files whose changed-line count (additions + deletions) exceeds this
        /// start collapsed — GitHub's "large diffs are not rendered by
        /// default". `nil` (the default) renders every file expanded. Applied
        /// by `setPatch`; the user's explicit header toggles are remembered by
        /// path and win over the threshold on later `setPatch` calls, so
        /// progressive loads don't re-collapse a file the user opened.
        public var largeFileCollapseThreshold: Int?

        public private(set) var patch: String = ""

        private var document = DiffPatchDocument(files: [], language: nil)
        /// Bumped by `setPatch`. In-flight expansions capture the generation
        /// they were started under and drop their result if the document was
        /// replaced in the meantime — file IDs restart at 0 for every patch, so
        /// a stale completion would otherwise splice old-patch lines into the
        /// new document.
        private var documentGeneration = 0
        private var collapsedFileIDs: Set<Int> = []
        /// Explicit header toggles, remembered by display path so they survive
        /// `setPatch` (progressive loads reparse the growing patch repeatedly,
        /// and file IDs restart at 0 each time).
        private var userCollapsedPaths: Set<String> = []
        private var userExpandedPaths: Set<String> = []
        private var loadingExpansions: Set<ExpansionKey> = []
        /// The hunk cell owning the active line selection. `DiffView` clears
        /// exclusively within one view; across hunk cells it's enforced here.
        private weak var selectionCell: DiffHunkCell?

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
            documentGeneration += 1
            collapsedFileIDs = Set(document.files.compactMap { file in
                if userCollapsedPaths.contains(file.displayPath) { return file.id }
                if userExpandedPaths.contains(file.displayPath) { return nil }
                if let threshold = largeFileCollapseThreshold,
                   file.additions + file.deletions > threshold
                {
                    return file.id
                }
                return nil
            })
            loadingExpansions = []
            selectionCell = nil
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

            return DiffFilesCollapseLayout(
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
                    theme: theme,
                    selectionEnabled: isLineSelectionEnabled
                )
                cell.onSelectionChanged = { [weak self] cell, info in
                    self?.hunkSelectionChanged(cell, fileID: fileID, info: info)
                }
                cell.onSelectionEnded = { [weak self] cell, info in
                    self?.hunkSelectionEnded(cell, fileID: fileID, info: info)
                }
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
            if animated {
                // Diffable's default apply animation is a flat fade at stock
                // timing — on a large diff that dims the whole section and
                // feels sluggish. The batch update inherits this spring
                // instead: fast, front-loaded travel. Critically damped
                // (damping 1) on purpose — any overshoot sends the sliding
                // sections past their targets, and with pinned headers and
                // transparent cells that crossing draws headers over their
                // neighbours mid-flight.
                UIView.animate(
                    withDuration: 0.45,
                    delay: 0,
                    usingSpringWithDamping: 1.0,
                    initialSpringVelocity: 0.4,
                    options: [.beginFromCurrentState, .allowUserInteraction]
                ) {
                    self.dataSource.apply(snapshot, animatingDifferences: true)
                }
            } else {
                dataSource.apply(snapshot, animatingDifferences: false)
            }
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
            if let path = document.file(withID: fileID)?.displayPath {
                if isCollapsed {
                    userExpandedPaths.insert(path)
                    userCollapsedPaths.remove(path)
                } else {
                    userCollapsedPaths.insert(path)
                    userExpandedPaths.remove(path)
                }
            }
            applySnapshot(animated: true)
            // Headers are supplementary views, so no item update reaches them;
            // reconfigure the visible one so its chevron follows the state.
            reconfigureHeader(fileID: fileID)
            if let file = document.file(withID: fileID) {
                fileCollapseHandler?(file.displayPath, !isCollapsed)
            }
        }

        private func reconfigureHeader(fileID: Int) {
            guard let section = document.files.firstIndex(where: { $0.id == fileID }),
                  let header = collectionView.supplementaryView(
                      forElementKind: UICollectionView.elementKindSectionHeader,
                      at: IndexPath(item: 0, section: section)
                  ) as? DiffFileHeaderView
            else { return }
            header.configure(
                file: document.files[section],
                theme: theme,
                isCollapsed: collapsedFileIDs.contains(fileID)
            ) { [weak self] in
                self?.toggleCollapse(fileID: fileID)
            }
        }

        // MARK: - Line selection

        private var isLineSelectionEnabled: Bool {
            lineSelectionHandler != nil || lineSelectionEndedHandler != nil
        }

        private func hunkSelectionChanged(_ cell: DiffHunkCell, fileID: Int, info: LineSelectionInfo?) {
            guard let path = document.file(withID: fileID)?.displayPath else { return }
            if info != nil {
                if let previous = selectionCell, previous !== cell {
                    previous.clearSelection()
                }
                selectionCell = cell
                lineSelectionHandler?(path, info)
                return
            }
            // Only a clear from the active cell counts — a reused or
            // reconfigured other cell must not cancel the live selection.
            guard selectionCell == nil || selectionCell === cell else { return }
            selectionCell = nil
            lineSelectionHandler?(path, nil)
        }

        private func hunkSelectionEnded(_ cell: DiffHunkCell, fileID: Int, info: LineSelectionInfo?) {
            guard let path = document.file(withID: fileID)?.displayPath else { return }
            if info != nil {
                selectionCell = cell
                lineSelectionEndedHandler?(path, info)
                return
            }
            guard selectionCell == nil || selectionCell === cell else { return }
            selectionCell = nil
            lineSelectionEndedHandler?(path, nil)
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

            let generation = documentGeneration
            Task { [weak self] in
                do {
                    let lines = try await provider(request)
                    // The document was replaced while the request was in
                    // flight; its file IDs restart at 0, so the expander's
                    // references would resolve against the wrong patch.
                    guard let self, generation == documentGeneration else { return }
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
                    guard let self, generation == documentGeneration else { return }
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

    /// Collapse/expand motion for the sectioned diff: appearing and
    /// disappearing cells travel towards their sticky header while they fade,
    /// so a toggled section reads as folding into (and unfolding out of) its
    /// header. The default attributes dissolve cells in place, which dims a
    /// large section wholesale — that reads as a rendering glitch, not motion.
    private final class DiffFilesCollapseLayout: UICollectionViewCompositionalLayout {
        private static let foldTravel: CGFloat = 32

        override func initialLayoutAttributesForAppearingItem(
            at itemIndexPath: IndexPath
        ) -> UICollectionViewLayoutAttributes? {
            guard let attributes = super.initialLayoutAttributesForAppearingItem(at: itemIndexPath)?
                .copy() as? UICollectionViewLayoutAttributes else { return nil }
            attributes.alpha = 0
            attributes.transform = CGAffineTransform(translationX: 0, y: -Self.foldTravel)
            return attributes
        }

        override func finalLayoutAttributesForDisappearingItem(
            at itemIndexPath: IndexPath
        ) -> UICollectionViewLayoutAttributes? {
            guard let attributes = super.finalLayoutAttributesForDisappearingItem(at: itemIndexPath)?
                .copy() as? UICollectionViewLayoutAttributes else { return nil }
            attributes.alpha = 0
            attributes.transform = CGAffineTransform(translationX: 0, y: -Self.foldTravel)
            return attributes
        }
    }
#endif
