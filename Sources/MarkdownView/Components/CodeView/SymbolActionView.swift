#if canImport(UIKit)
    import UIKit

    /// A tappable UIImageView with built-in SF Symbol effect support.
    ///
    /// Supports three common patterns:
    /// - **Confirmation**: Replaces to a checkmark and back (copy, save)
    /// - **Bounce**: Bounces the icon in place (share)
    /// - **State toggle**: Replaces between two icons with optional ongoing effect (speaker)
    class SymbolActionView: UIImageView {

        enum Effect {
            /// Replaces icon with checkmark, then replaces back after completion.
            case confirmation
            /// Bounces the icon upward.
            case bounce
            /// No automatic effect; caller manages transitions manually.
            case none
        }

        static let defaultConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        private let symbolName: String
        private let symbolConfig: UIImage.SymbolConfiguration
        private let effect: Effect
        private var action: (() -> Void)?

        init(
            systemName: String,
            effect: Effect = .none,
            config: UIImage.SymbolConfiguration = SymbolActionView.defaultConfig
        ) {
            self.symbolName = systemName
            self.symbolConfig = config
            self.effect = effect
            super.init(image: UIImage(systemName: systemName, withConfiguration: config))

            tintColor = UIColor(white: 0.6, alpha: 1)
            contentMode = .center
            isUserInteractionEnabled = true

            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func onTap(_ handler: @escaping () -> Void) {
            self.action = handler
        }

        @objc private func handleTap() {
            action?()

            if #available(iOS 17.0, visionOS 1.0, *) {
                switch effect {
                case .confirmation:
                    let checkImage = UIImage(systemName: "checkmark", withConfiguration: symbolConfig)!
                    setSymbolImage(checkImage, contentTransition: .replace) { [weak self] context in
                        guard let self,
                              let imageView = context.sender as? UIImageView,
                              context.isFinished else { return }
                        let originalImage = UIImage(
                            systemName: self.symbolName,
                            withConfiguration: self.symbolConfig
                        )!
                        imageView.setSymbolImage(originalImage, contentTransition: .replace)
                    }
                case .bounce:
                    addSymbolEffect(.bounce.up)
                case .none:
                    break
                }
            }
        }

        // MARK: - State Toggle Support

        /// Replaces the current symbol with a new one using the `.replace` content transition.
        func replaceSymbol(systemName: String) {
            guard #available(iOS 17.0, visionOS 1.0, *) else { return }
            let newImage = UIImage(systemName: systemName, withConfiguration: symbolConfig)!
            setSymbolImage(newImage, contentTransition: .replace)
        }

        /// Adds an ongoing variable color effect (e.g., for active speaker).
        func startVariableColor() {
            guard #available(iOS 17.0, visionOS 1.0, *) else { return }
            addSymbolEffect(.variableColor.iterative)
        }

        /// Removes the variable color effect.
        func stopVariableColor() {
            guard #available(iOS 17.0, visionOS 1.0, *) else { return }
            removeSymbolEffect(ofType: .variableColor)
        }
    }
#endif
