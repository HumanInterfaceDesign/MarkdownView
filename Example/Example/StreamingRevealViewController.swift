//
//  StreamingRevealViewController.swift
//  Example
//
//  Demonstrates `MarkdownTextView.streamingReveal`: characters fade in (left→right
//  as they arrive) while a response streams, then settle to fully opaque. Tap
//  "Replay" to stream the sample again.
//

import MarkdownParser
import MarkdownView
import UIKit

final class StreamingRevealViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let markdownView = MarkdownTextView()
    private let parser = MarkdownParser()

    /// Selectable sweep speeds (characters/sec), surfaced via the segmented control.
    private let speeds: [(title: String, value: CGFloat)] = [
        ("Fast", 120),
        ("Default", 80),
        ("Slow", 45),
    ]
    private lazy var speedControl = UISegmentedControl(
        items: speeds.map(\.title)
    )

    /// Characters appended per tick — deliberately bursty (a chunk at a time) to
    /// mimic real markdown streaming, where whole blocks arrive at once. The
    /// reveal still sweeps them left→right at the chosen speed.
    private let charactersPerTick = 14
    private let tickInterval: TimeInterval = 0.12

    private var streamTimer: Timer?
    private var revealedCount = 0

    private let sampleMarkdown = """
    Hey! Here's a quick overview of what I can help you with:

    **Building & Coding**
    - **Full-stack apps** — Next.js, React, APIs, databases
    - **Authentication** — email/password and OAuth flows
    - **UI components** — accessible, themeable, animated

    **Design**
    - Landing pages, dashboards, and mobile-first layouts
    - Design systems and component libraries

    **Integrations**
    - Payments, storage, queues, and third-party APIs
    - Webhooks and OAuth handshakes

    Just describe what you want to build or fix, and I'll get started. \
    What are you working on?
    """

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Streaming Reveal"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Replay",
            image: UIImage(systemName: "arrow.clockwise"),
            primaryAction: UIAction { [weak self] _ in self?.startStreaming() }
        )

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        speedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        view.addSubview(speedControl)
        scrollView.addSubview(markdownView)

        // Changing the duration re-streams so the effect is immediately visible.
        speedControl.selectedSegmentIndex = 1
        speedControl.addAction(UIAction { [weak self] _ in self?.startStreaming() }, for: .valueChanged)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: speedControl.topAnchor, constant: -12),

            speedControl.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            speedControl.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            speedControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            markdownView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            markdownView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            markdownView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            markdownView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            markdownView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if revealedCount == 0 {
            startStreaming()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopTimer()
    }

    // MARK: - Streaming simulation

    private func startStreaming() {
        stopTimer()
        revealedCount = 0
        // Cancel any in-flight fade from a previous run, then arm the reveal so
        // every appended chunk fades in as it lands.
        markdownView.cancelStreamingReveal()
        markdownView.streamingRevealCharactersPerSecond = speeds[speedControl.selectedSegmentIndex].value
        markdownView.streamingReveal = true
        render(prefixLength: 0)

        streamTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.advance()
        }
    }

    private func advance() {
        let total = sampleMarkdown.count
        revealedCount = min(total, revealedCount + charactersPerTick)
        render(prefixLength: revealedCount)

        if revealedCount >= total {
            stopTimer()
            // Stream finished — stop stamping new text; the last fade settles.
            markdownView.streamingReveal = false
        }
    }

    private func render(prefixLength: Int) {
        let endIndex = sampleMarkdown.index(sampleMarkdown.startIndex, offsetBy: prefixLength)
        let prefix = String(sampleMarkdown[sampleMarkdown.startIndex ..< endIndex])
        let result = parser.parse(prefix)
        let content = MarkdownTextView.PreprocessedContent(parserResult: result, theme: markdownView.theme)
        markdownView.setMarkdown(content)

        // Keep the newest text in view, like a chat transcript.
        view.layoutIfNeeded()
        let bottom = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        scrollView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
    }

    private func stopTimer() {
        streamTimer?.invalidate()
        streamTimer = nil
    }
}
