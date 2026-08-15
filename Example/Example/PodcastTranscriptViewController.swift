//
//  PodcastTranscriptViewController.swift
//  Example
//

import MarkdownView
import UIKit

/// Mimics the chat "podcast mode" audio cell: an audio bubble (play button,
/// waveform, duration) with the returned transcript previewed underneath.
/// Tapping the transcript, or its "Show more" button, opens the full
/// transcript detail sheet.
final class PodcastTranscriptViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Podcast Transcript"
        view.backgroundColor = .systemBackground

        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.alignment = .trailing
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
        ])

        addAudioBubble(duration: "0:04", transcript: Self.shortTranscript)
        addAudioBubble(duration: "1:32", transcript: Self.longTranscript)
    }

    private func addAudioBubble(duration: String, transcript: String) {
        let bubble = AudioBubbleView(duration: duration)
        bubble.transcriptView.setTranscript(transcript)
        bubble.transcriptView.showMoreHandler = { [weak self, weak bubble] in
            guard let self, let bubble else { return }
            present(bubble.transcriptView.makeDetailViewController(), animated: true)
        }
        stackView.addArrangedSubview(bubble)
        bubble.widthAnchor.constraint(
            lessThanOrEqualTo: stackView.widthAnchor,
            multiplier: 0.8
        ).isActive = true
    }

    private static let shortTranscript = """
    Please remind me about this dinner 1 hour before.
    """

    private static let longTranscript = """
    Welcome back to the show. Today we're walking through the **new podcast \
    mode**: paste in any blog post and we generate a narrated audio version \
    you can listen to on the go.

    Under the hood the pipeline has three stages:

    - Summarize the post into a spoken-word script
    - Synthesize the narration with a natural voice
    - Return the audio *and* this transcript alongside it

    That last part is what you're reading right now. The transcript comes \
    back with the audio response, so the chat can preview a couple of lines \
    under the player and expand into this detail view when you want to read \
    instead of listen.

    Thanks for listening — see you in the next episode.
    """
}

/// A stand-in for the app's audio message cell: play button, waveform, and
/// duration in a bubble, with the transcript preview tucked underneath.
private final class AudioBubbleView: UIView {

    let transcriptView = TranscriptPreviewView()

    init(duration: String) {
        super.init(frame: .zero)

        backgroundColor = .systemGray2
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous

        let playButton = UIButton(configuration: {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: "play.circle.fill")
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 34)
            config.baseForegroundColor = .white
            config.contentInsets = .zero
            return config
        }())

        let waveform = WaveformView()
        waveform.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let durationLabel = UILabel()
        durationLabel.text = duration
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        durationLabel.textColor = .white

        let audioRow = UIStackView(arrangedSubviews: [playButton, waveform, durationLabel])
        audioRow.axis = .horizontal
        audioRow.alignment = .center
        audioRow.spacing = 10

        transcriptView.textColor = .white.withAlphaComponent(0.85)

        let content = UIStackView(arrangedSubviews: [audioRow, transcriptView])
        content.axis = .vertical
        content.alignment = .fill
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}

/// Static decorative waveform bars, in place of real audio samples.
private final class WaveformView: UIView {

    private static let samples: [CGFloat] = [
        0.35, 0.7, 0.5, 0.9, 0.6, 0.4, 0.8, 0.55, 0.3, 0.65,
        0.85, 0.45, 0.6, 0.9, 0.5, 0.35, 0.75, 0.6, 0.4, 0.8,
        0.5, 0.65, 0.35, 0.55, 0.7, 0.45, 0.6, 0.5, 0.4, 0.3,
    ]

    private static let barWidth: CGFloat = 3
    private static let gap: CGFloat = 2.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        isOpaque = false
    }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: CGFloat(Self.samples.count) * (Self.barWidth + Self.gap) - Self.gap,
            height: 34
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func draw(_: CGRect) {
        let step = Self.barWidth + Self.gap
        let count = min(Self.samples.count, Int(bounds.width / step))
        guard count > 0 else { return }

        UIColor.white.setFill()
        for index in 0 ..< count {
            let height = max(4, Self.samples[index] * bounds.height)
            let bar = CGRect(
                x: CGFloat(index) * step,
                y: (bounds.height - height) / 2,
                width: Self.barWidth,
                height: height
            )
            UIBezierPath(roundedRect: bar, cornerRadius: Self.barWidth / 2).fill()
        }
    }
}
