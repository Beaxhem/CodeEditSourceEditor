//
//  FindViewController.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 3/10/25.
//

import AppKit
import CodeEditTextView

/// Creates a container controller for displaying and hiding a find panel with a content view.
final class FindViewController: NSViewController {
    var viewModel: FindPanelViewModel

    /// The amount of padding from the top of the view to inset the find panel by.
    /// When set, the safe area is ignored, and the top padding is measured from the top of the view's frame.
    var topPadding: CGFloat? {
        didSet {
            if viewModel.isShowingFindPanel {
                setFindPanelConstraintShow()
            }
        }
    }

    var childView: NSView

    /// The find panel, once it exists. `nil` until something asks for it.
    ///
    /// Read this — rather than ``findPanel`` — anywhere that only wants to act on a panel
    /// that is already on screen. Touching ``findPanel`` builds one.
    private(set) var installedFindPanel: FindPanelHostingView?

    /// The find panel, built and installed on first use.
    ///
    /// Querynaut fork: this used to be a stored property assigned in `init` and added as a
    /// subview in `loadView`, so every editor carried a live `NSHostingView` whether or not
    /// find was ever opened. Hiding it is not enough — an `NSHostingView` builds and
    /// updates its content regardless of `isHidden`, and this one's content is a search
    /// field, a controls row, and a `FindMethodPicker` that makes an `NSPopUpButton`, two
    /// labels and a menu.
    ///
    /// Sampling a pure layout loop in Querynaut (editors built once, asserted not rebuilt)
    /// put `FindMethodPicker.makeNSView` alone at ~25% of main-thread time, and the find
    /// panel's frames together at roughly three quarters of it — in a one-line query bar
    /// that never opens find.
    ///
    /// Building it on demand costs a single hosting-view construction the first time
    /// ⌘F is pressed, which is a keystroke that already animates. See FORK.md.
    var findPanel: FindPanelHostingView {
        if let installedFindPanel {
            return installedFindPanel
        }

        let panel = FindPanelHostingView(viewModel: viewModel)
        installFindPanel(panel)
        return panel
    }

    var findPanelVerticalConstraint: NSLayoutConstraint!

    /// The 'real' top padding amount.
    /// Is equal to ``topPadding`` if set, or the view's top safe area inset if not.
    var resolvedTopPadding: CGFloat {
        (topPadding ?? view.safeAreaInsets.top)
    }

    init(target: FindPanelTarget, childView: NSView) {
        viewModel = FindPanelViewModel(target: target)
        self.childView = childView
        super.init(nibName: nil, bundle: nil)
        viewModel.dismiss = { [weak self] in
            self?.hideFindPanel()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        super.loadView()

        // Set up the `childView` as a subview of our view. Constrained to all edges, except the top is constrained to
        // the find panel's bottom
        // The find panel is constrained to the top of the view.
        // The find panel's top anchor when hidden, is equal to it's negated height hiding it above the view's contents.
        // When visible, it's set to 0.

        view.clipsToBounds = false
        view.addSubview(childView)

        NSLayoutConstraint.activate([
            // Constrain child view
            childView.topAnchor.constraint(equalTo: view.topAnchor),
            childView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            childView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Querynaut fork: settle the panel's visibility here rather than leaving it to
        // `viewWillAppear`.
        //
        // `TextViewController` attaches this controller with `addChild` plus a manual
        // `addSubview`, which does not drive an appearance transition, so `viewWillAppear`
        // need never run. With the panel built lazily this is now only about the case
        // where the view model already says find is open.
        applyFindPanelVisibility()
    }

    /// Adds the panel to the view and constrains it to the top edge.
    private func installFindPanel(_ panel: FindPanelHostingView) {
        installedFindPanel = panel

        // Ensure find panel is always on top
        panel.wantsLayer = true
        panel.layer?.zPosition = 1000

        view.addSubview(panel, positioned: .above, relativeTo: childView)

        findPanelVerticalConstraint = panel.topAnchor.constraint(equalTo: view.topAnchor)

        NSLayoutConstraint.activate([
            findPanelVerticalConstraint,
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    /// Shows or hides the panel to match ``FindPanelViewModel/isShowingFindPanel``.
    ///
    /// Does not build a panel to hide it — no panel is already the hidden state.
    private func applyFindPanelVisibility() {
        if viewModel.isShowingFindPanel {
            findPanel.isHidden = false
            setFindPanelConstraintShow()
        } else if let installedFindPanel {
            installedFindPanel.isHidden = true
            setFindPanelConstraintHide()
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        applyFindPanelVisibility()
    }
}
