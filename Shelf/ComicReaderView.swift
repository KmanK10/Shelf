import SwiftUI
import UIKit

struct ComicReaderView: View {
    var launch: ReaderLaunch
    var startPage: Int
    var onAdvance: (ReaderLaunch) -> Void

    @Environment(ShelfModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int
    @State private var showsChrome = true
    @State private var saveTask: Task<Void, Never>?

    init(launch: ReaderLaunch, startPage: Int, onAdvance: @escaping (ReaderLaunch) -> Void) {
        self.launch = launch
        self.startPage = startPage
        self.onAdvance = onAdvance
        _currentPage = State(initialValue: startPage)
    }

    var body: some View {
        let rightToLeft = model.readingDirection == .rightToLeft
        ZStack(alignment: .top) {
            ComicPageControllerRepresentable(
                pageCount: max(launch.pageCount, 1),
                startPage: currentPage,
                rightToLeft: rightToLeft,
                loadImage: { page in
                    await model.pageImage(chapterId: launch.chapterId, page: page)
                },
                onPageChange: { page in
                    guard page != currentPage else { return }
                    currentPage = page
                    scheduleSave()
                },
                onToggleChrome: { showsChrome.toggle() }
            )
            .id(rightToLeft)
            .ignoresSafeArea()

            if showsChrome {
                ReaderToolbar(
                    title: launch.title,
                    subtitle: launch.seriesTitle,
                    pageLabel: "\(currentPage + 1) / \(max(launch.pageCount, 1))",
                    showsDirection: true,
                    onClose: { close() },
                    onPreviousChapter: currentPage == 0 ? { Task { await moveChapter(forward: false) } } : nil,
                    onNextChapter: currentPage >= max(launch.pageCount, 1) - 1 ? { Task { await moveChapter(forward: true) } } : nil
                )
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(!showsChrome)
        .onDisappear { saveTask?.cancel(); Task { await save(keepScroll: false) } }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await save(keepScroll: false)
        }
    }

    private func save(keepScroll: Bool) async {
        guard currentPage != startPage else { return }
        await model.savePosition(
            for: launch,
            pageIndex: currentPage,
            pageCount: launch.pageCount,
            bookScrollId: nil,
            keepScroll: keepScroll
        )
    }

    private func close() {
        saveTask?.cancel()
        Task {
            await save(keepScroll: false)
            dismiss()
        }
    }

    private func moveChapter(forward: Bool) async {
        await save(keepScroll: false)
        do {
            guard let next = try await model.adjacentLaunch(after: launch, forward: forward) else { return }
            onAdvance(next)
        } catch {
            model.readerSyncError = error.localizedDescription
        }
    }
}

struct ComicPageControllerRepresentable: UIViewControllerRepresentable {
    var pageCount: Int
    var startPage: Int
    var rightToLeft: Bool
    var loadImage: (Int) async -> UIImage?
    var onPageChange: (Int) -> Void
    var onToggleChrome: () -> Void

    func makeUIViewController(context: Context) -> ComicReaderController {
        let controller = ComicReaderController(pageCount: pageCount, startPage: startPage, rightToLeft: rightToLeft)
        controller.loadImage = loadImage
        controller.onPageChange = onPageChange
        controller.onToggleChrome = onToggleChrome
        return controller
    }

    func updateUIViewController(_ controller: ComicReaderController, context: Context) {
        controller.loadImage = loadImage
        controller.onPageChange = onPageChange
        controller.onToggleChrome = onToggleChrome
    }
}

final class ComicReaderController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    let pageCount: Int
    let startPage: Int
    let rightToLeft: Bool
    var loadImage: ((Int) async -> UIImage?)?
    var onPageChange: ((Int) -> Void)?
    var onToggleChrome: (() -> Void)?

    private let pageViewController: UIPageViewController

    init(pageCount: Int, startPage: Int, rightToLeft: Bool) {
        self.pageCount = max(pageCount, 1)
        self.startPage = min(max(0, startPage), max(pageCount, 1) - 1)
        self.rightToLeft = rightToLeft
        pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        pageViewController.dataSource = self
        pageViewController.delegate = self
        pageViewController.view.semanticContentAttribute = rightToLeft ? .forceRightToLeft : .forceLeftToRight
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pageViewController.didMove(toParent: self)
        let first = makePage(startPage)
        pageViewController.setViewControllers([first], direction: .forward, animated: false)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = (viewController as? ZoomPageController)?.index else { return nil }
        let next = page - 1
        guard next >= 0 else { return nil }
        return makePage(next)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = (viewController as? ZoomPageController)?.index else { return nil }
        let next = page + 1
        guard next < pageCount else { return nil }
        return makePage(next)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed, let page = pageViewController.viewControllers?.first as? ZoomPageController else { return }
        onPageChange?(page.index)
    }

    func setPagingEnabled(_ enabled: Bool) {
        pageViewController.dataSource = enabled ? self : nil
        for subview in pageViewController.view.subviews {
            guard let scroll = subview as? UIScrollView else { continue }
            scroll.isScrollEnabled = enabled
        }
    }

    private func makePage(_ index: Int) -> ZoomPageController {
        let page = ZoomPageController(index: index)
        page.loadImage = { [weak self] in
            await self?.loadImage?(index)
        }
        page.onZoomed = { [weak self] zoomed in
            self?.setPagingEnabled(!zoomed)
        }
        page.onSingleTap = { [weak self] in
            self?.onToggleChrome?()
        }
        return page
    }
}

final class ZoomPageController: UIViewController, UIScrollViewDelegate {
    let index: Int
    var loadImage: (() async -> UIImage?)?
    var onZoomed: ((Bool) -> Void)?
    var onSingleTap: (() -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var didZoomManually = false
    private var laidOutSize: CGSize = .zero

    init(index: Int) {
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        view.addSubview(scrollView)
        scrollView.addSubview(imageView)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        spinner.startAnimating()
        Task { @MainActor in
            let image = await loadImage?()
            spinner.stopAnimating()
            imageView.image = image
            didZoomManually = false
            layoutImage(resetZoom: true)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = scrollView.bounds.size
        let boundsChanged = laidOutSize != size
        if boundsChanged {
            laidOutSize = size
        }
        layoutImage(resetZoom: boundsChanged && !didZoomManually)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        didZoomManually = zoomed
        onZoomed?(zoomed)
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard imageView.image != nil else { return }
        let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        if zoomed {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let point = recognizer.location(in: imageView)
        let target = min(scrollView.minimumZoomScale * 2.5, scrollView.maximumZoomScale)
        let size = CGSize(width: scrollView.bounds.width / target, height: scrollView.bounds.height / target)
        let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
    }

    private func layoutImage(resetZoom: Bool) {
        guard let image = imageView.image, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        imageView.frame = CGRect(origin: .zero, size: image.size)
        let widthScale = scrollView.bounds.width / image.size.width
        let heightScale = scrollView.bounds.height / image.size.height
        let minScale = min(widthScale, heightScale)
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = max(minScale * 4, 4)
        if resetZoom {
            scrollView.zoomScale = minScale
        }
        centerImage()
    }

    private func centerImage() {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        imageView.center = CGPoint(x: scrollView.contentSize.width * 0.5 + offsetX, y: scrollView.contentSize.height * 0.5 + offsetY)
    }
}
