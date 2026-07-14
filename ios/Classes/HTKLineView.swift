//
//  HTKLineView.swift
//  HTKLineView
//
//  Created by hublot on 2020/3/17.
//  Copyright © 2020 hublot. All rights reserved.
//

import UIKit
import Lottie
import ObjectiveC

class HTKLineView: UIScrollView, UIGestureRecognizerDelegate {
        
    weak var containerView: HTKLineContainerView?
    var configManager: HTKLineConfigManager
    
    lazy var drawContext: HTDrawContext = {
        let drawContext = HTDrawContext.init(self, configManager)
        return drawContext
    }()

    var visibleRange = 0...0

    var selectedIndex = -1

    /// Change-detection for the app-side crosshair readout (hoverInfoMode ==
    /// "topLayer"). onCrosshairChange only fires when the visible/index state
    /// actually changes, so it can be polled cheaply from draw().
    private var lastCrosshairIndex = -1
    private var lastCrosshairVisible = false

    /// Light haptic fired when the selected candle index changes during long-press hover
    /// (gated by configManager.hapticOnSelection).
    private lazy var selectionFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    /// When selecting via long-press, we snap X to the nearest candle (selectedIndex),
    /// but keep Y free so the user can drag vertically to inspect arbitrary prices.
    /// Stored in view coordinates (same space as drawing).
    var selectedY: CGFloat = .nan

    // While long-press hovering, temporarily disable scrolling so the scroll view pan
    // doesn’t steal the gesture (and clear selection via scroll callbacks).
    private var wasScrollEnabledBeforeLongPress: Bool = true
    // Nearest parent scroll view (e.g. RN vertical ScrollView) we temporarily disable during hover.
    private weak var parentScrollViewDuringLongPress: UIScrollView?
    private var parentWasScrollEnabledBeforeLongPress: Bool = true

    // Disable the parent (vertical) scroll view while this chart is being scrolled horizontally.
    private var parentWasScrollEnabledBeforeDrag: Bool = true
    private var didDisableParentForDrag: Bool = false
    // When true, hover mode stays active after the user lifts their finger, so they can tap
    // the right-side price pill (+ icon) or inspect values without immediately returning to scroll mode.
    private var isHoverModeLocked: Bool = false

    // `shouldScrollToEnd` can be requested before RN lays out the view (bounds.width == 0).
    // Defer the initial scroll-to-end until we have a real size.
    private var didApplyInitialScrollToEnd: Bool = false
    private var lastKnownBoundsSize: CGSize = .zero
    private var lastKnownContentSize: CGSize = .zero

    // Hit target for the right-side hover price pill (used to trigger `onNewOrder`).
    private var selectedPricePillRect: CGRect = .zero
    private var selectedPriceValue: CGFloat = .nan

    // Hit target for the close price center pill (shown when scrolled left, tap to scroll to present).
    private var closePriceCenterPillRect: CGRect = .zero

    private var baseLeftInset: CGFloat { bounds.width * 0.5 }

    // Timer for updating the candle countdown every second.
    private var candleCountdownTimer: Timer?

    // Horizontal zoom factor applied to itemWidth/candleWidth (1.0 = 100%).
    // Default to 0.8 so the chart opens slightly zoomed out (80%). Pinch clamps to 0.3–3.
    var scale: CGFloat = 0.8

    // Y-axis zoom factor: 1.0 = 100% (auto-fit), up to 5.0 = 20% (zoomed out).
    // Persists across gestures so the zoom level is retained after finger lift.
    private var yAxisZoomFactor: CGFloat = 1.0

    // --- Right y-axis drag scaling (vertical zoom) ---
    private var yAxisScaleStartY: CGFloat = .nan
    private var yAxisScaleStartFactor: CGFloat = 1.0
    private let yAxisGestureWidth: CGFloat = 64
    private let yAxisGestureSensitivityFactor: CGFloat = 0.7

    // Vertical pinch state – tracks the vertical span between two fingers so the
    // pinch gesture can simultaneously adjust the Y-axis zoom factor.
    private var pinchStartVerticalSpan: CGFloat = .nan
    private var pinchStartYAxisZoomFactor: CGFloat = 1.0

    private lazy var yAxisPanGesture: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(yAxisPanSelector(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        return pan
    }()

    private lazy var longPressGesture: UILongPressGestureRecognizer = {
        let g = UILongPressGestureRecognizer(target: self, action: #selector(longPressSelector(_:)))
        g.delegate = self
        // Be a bit more forgiving of tiny finger jitter while waiting for the long press.
        g.allowableMovement = 20
        return g
    }()

    let mainDraw = HTMainDraw.init()

    let volumeDraw = HTVolumeDraw.init()

    let macdDraw = HTMacdDraw.init()

    let kdjDraw = HTKdjDraw.init()

    let rsiDraw = HTRsiDraw.init()

    let wrDraw = HTWrDraw.init()

    let genericDraw = HTGenericOscillatorDraw.init()

    var childDraw: HTKLineDrawProtocol?

    var animationView = LottieAnimationView()

    // Optional logo image drawn in the center of the main chart, behind candles.
    // Backed by a base64 string in configManager.centerLogoSource.
    private var centerLogoImage: UIImage?
    private var lastCenterLogoSource: String = ""

    var lastLoadAnimationSource = ""

    // Loading spinner shown at the left edge when fetching older candles.
    private lazy var loadingSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .white)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.alpha = 0
        return spinner
    }()
    private var isShowingLoadingSpinner = false

    // Animated close price: smoothly interpolate the displayed value.
    private var displayedClosePrice: CGFloat = .nan
    private var closePriceAnimationTarget: CGFloat = .nan
    private var closePriceDisplayLink: CADisplayLink?
    private var closePriceAnimationStart: CGFloat = .nan
    private var closePriceAnimationEnd: CGFloat = .nan
    private var closePriceAnimationStartTime: CFTimeInterval = 0
    private let closePriceAnimationDuration: CFTimeInterval = 0.35





    // Animated vertical scale: smoothly interpolate min/max when visible range changes.
    private var animatedMainMin: CGFloat = .nan
    private var animatedMainMax: CGFloat = .nan
    private var animatedVolMin: CGFloat = .nan
    private var animatedVolMax: CGFloat = .nan
    private var animatedChildMin: CGFloat = .nan
    private var animatedChildMax: CGFloat = .nan
    private let scaleAnimLerp: CGFloat = 0.12

    // Track panel config so we can reset vertical scale when volume/child indicator changes.
    private var lastRenderedChildType: HTKLineChildType = .none
    private var lastRenderedShowVolume: Bool = true
    // Track the main-chart indicator set (MA/BOLL + overlays like EMA/BOLL) so the
    // main vertical scale SNAPS to the new range instead of animating when an
    // indicator that widens the range (e.g. BOLL) is added or removed.
    private var lastRenderedMainSignature: String = ""

    // 计算属性
    var visibleModelArray = [HTKLineModel]()
    var volumeRange: ClosedRange<CGFloat> = 0...0
    var allWidth: CGFloat = 0
    var allHeight: CGFloat = 0
    var mainMinMaxRange = Range<CGFloat>.init(uncheckedBounds: (lower: 0, upper: 0))
    var textHeight: CGFloat  = 0
    var mainBaseY: CGFloat  = 0
    var mainHeight: CGFloat  = 0
    var volumeMinMaxRange = Range<CGFloat>.init(uncheckedBounds: (lower: 0, upper: 0))
    var volumeBaseY: CGFloat  = 0
    var volumeHeight: CGFloat  = 0
    var childMinMaxRange = Range<CGFloat>.init(uncheckedBounds: (lower: 0, upper: 0))
    var childBaseY: CGFloat  = 0
    var childHeight: CGFloat  = 0

    // Native N7: stacked multi sub-panels (order = configManager.secondList).
    // Each entry is one oscillator panel below the volume band. `childDrawList`
    // holds its renderer, `childGenericIndexList` the index into a candle's
    // `subLinesList` (-1 for non-generic), and the geometry/scale arrays its
    // layout. When `childDrawList` is empty the legacy single-panel path runs.
    var childDrawList = [HTKLineDrawProtocol]()
    var childGenericIndexList = [Int]()
    var childBaseYs = [CGFloat]()
    var childHeights = [CGFloat]()
    var childMinMaxRanges = [Range<CGFloat>]()
    var animatedChildMins = [CGFloat]()
    var animatedChildMaxs = [CGFloat]()

    /// True when the stacked multi-panel path is active.
    var isMultiPanel: Bool {
        return !childDrawList.isEmpty
    }

    /// Bottom of the lowest sub-panel (or the vol/main band when there is none),
    /// used by the crosshair vertical line, x-axis time row and grid bottom.
    var childAreaBottom: CGFloat {
        if isMultiPanel, let last = childBaseYs.indices.last {
            return childBaseYs[last] + childHeights[last]
        }
        return childBaseY + childHeight
    }

    /// The child renderer for `second`/`secondList` code `code`, or nil.
    private func childDrawForCode(_ code: Int) -> HTKLineDrawProtocol? {
        if code >= 100 {
            return genericDraw
        }
        switch HTKLineChildType(rawValue: code) ?? .none {
        case .none: return nil
        case .macd: return macdDraw
        case .kdj: return kdjDraw
        case .rsi: return rsiDraw
        case .wr: return wrDraw
        case .generic: return genericDraw
        }
    }

    /// Native N7: rebuild the stacked panel renderers from configManager.secondList.
    /// Mirrors Android's applySecondList — populated only when >1 code is present
    /// or an oscillator is stacked alongside volume; otherwise stays empty so the
    /// legacy single `childDraw` path is used.
    func applySecondList() {
        childDrawList = []
        childGenericIndexList = []
        var genericCount = 0
        for code in configManager.secondList {
            guard let draw = childDrawForCode(code) else {
                continue
            }
            childDrawList.append(draw)
            if code >= 100 {
                childGenericIndexList.append(genericCount)
                genericCount += 1
            } else {
                childGenericIndexList.append(-1)
            }
        }
        if animatedChildMins.count != childDrawList.count {
            animatedChildMins = [CGFloat](repeating: .nan, count: childDrawList.count)
            animatedChildMaxs = [CGFloat](repeating: .nan, count: childDrawList.count)
        }
    }




    init(_ frame: CGRect, _ configManager: HTKLineConfigManager) {
        self.configManager = configManager
        super.init(frame: frame)
        delegate = self
        bounces = false
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = UIColor.clear

        addGestureRecognizer(longPressGesture)
        
        // Tap gesture should only fire if the long press fails (i.e., user lifted finger
        // before the long press minimum duration). This prevents a tap from clearing
        // the hover selection immediately after the user lifts their finger from a long press.
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapSelector))
        tapGesture.require(toFail: longPressGesture)
        addGestureRecognizer(tapGesture)
        
        addGestureRecognizer(UIPinchGestureRecognizer.init(target: self, action: #selector(pinchSelector)))
        addGestureRecognizer(yAxisPanGesture)

        // Prefer long-press hover over horizontal scrolling. This prevents the scroll view pan
        // from beginning immediately (due to tiny finger movement) and causing long-press to fail.
        panGestureRecognizer.require(toFail: longPressGesture)

        addSubview(loadingSpinner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        candleCountdownTimer?.invalidate()
        candleCountdownTimer = nil
        closePriceDisplayLink?.invalidate()
        closePriceDisplayLink = nil
    }

    func reloadConfigManager(_ configManager: HTKLineConfigManager) {

        // Enable/disable the long-press hover overlay. Disabling the recognizer (rather than just
        // ignoring it in the handler) is important: `panGestureRecognizer.require(toFail:)` on the
        // scroll views would otherwise let a recognized long-press block normal scrolling.
        longPressGesture.isEnabled = configManager.hoverInfoEnabled
        if !configManager.hoverInfoEnabled, selectedIndex != -1 {
            // Clear any active hover selection so a stale overlay doesn't linger after disabling.
            selectedIndex = -1
            selectedY = .nan
            selectedPricePillRect = .zero
            selectedPriceValue = .nan
            exitHoverModeIfNeeded()
        }

        let childType = configManager.childType
        let showVolume = configManager.showVolume
        // Signature of everything that changes the main chart's value range.
        let mainSignature = "\(configManager.mainType.rawValue)|" +
            configManager.mainOverlays.sorted().joined(separator: ",")
        if childType != lastRenderedChildType || showVolume != lastRenderedShowVolume
            || mainSignature != lastRenderedMainSignature {
            resetAnimatedScaleValues()
            lastRenderedChildType = childType
            lastRenderedShowVolume = showVolume
            lastRenderedMainSignature = mainSignature
        }

        switch configManager.childType {
        case .none:
            childDraw = nil
        case .macd:
            childDraw = macdDraw
        case .kdj:
            childDraw = kdjDraw
        case .rsi:
            childDraw = rsiDraw
        case .wr:
            childDraw = wrDraw
        case .generic:
            childDraw = genericDraw
        }

        // Native N7: (re)build the stacked sub-panel list. When it changes the
        // per-panel scale animation must reset so panels don't inherit a stale
        // min/max from a different indicator.
        let oldPanelCount = childDrawList.count
        applySecondList()
        if childDrawList.count != oldPanelCount {
            animatedChildMins = [CGFloat](repeating: .nan, count: childDrawList.count)
            animatedChildMaxs = [CGFloat](repeating: .nan, count: childDrawList.count)
        }

        // "At end" is measured against the resting flush position (newest candle against the
        // axis), not the padded content end — so the chart follows whether or not the user has
        // scrolled into the right padding.
        let oldFlushEnd = max(0, contentSize.width - rightTailPadding - bounds.size.width)
        let isEnd = contentOffset.x + 1 >= oldFlushEnd
        reloadContentSize()

        // Reset deferral marker when JS asks for "keep at end".
        if configManager.shouldScrollToEnd {
            didApplyInitialScrollToEnd = false
        }

        if (configManager.shouldScrollToEnd || isEnd) {
            // If layout hasn't happened yet (width == 0), defer to layoutSubviews().
            if bounds.size.width > 0 {
                // Preserve any overscroll into the right tail so config reloads
                // don't yank an overscrolled chart back to the resting position.
                let overscroll = max(contentOffset.x - oldFlushEnd, 0)
                let toEndContentOffset = endContentOffsetX + overscroll
                let distance = abs(contentOffset.x - toEndContentOffset)
                let animated = distance <= configManager.itemWidth
                didApplyInitialScrollToEnd = true
                reloadContentOffset(toEndContentOffset, animated)
                scrollViewDidScroll(self)
            } else {
                scrollViewDidScroll(self)
            }
        } else {
            scrollViewDidScroll(self)
        }

        // (1) Reload/prepare the Lottie "live price" animation when source changes.
        if lastLoadAnimationSource != configManager.closePriceRightLightLottieSource {
        lastLoadAnimationSource = configManager.closePriceRightLightLottieSource

        DispatchQueue.global().async { [weak self] in
                guard
                    let this = self,
                    let data = this.configManager.closePriceRightLightLottieSource.data(using: String.Encoding.utf8),
                    let animation = try? JSONDecoder().decode(LottieAnimation.self, from: data)
                else {
                return
            }
            DispatchQueue.main.async {
                this.animationView.animation = animation
                this.animationView.loopMode = .loop
                this.animationView.play()
                var size = animation.size
                let scale = this.configManager.closePriceRightLightLottieScale
                size.width *= scale
                size.height *= scale
                this.animationView.frame.size = size
                this.animationView.isHidden = true
                this.addSubview(this.animationView)
                this.setNeedsDisplay()
                }
            }
        }

        // (2) Decode / cache the center logo image (if any) when its source changes.
        let logoSource = configManager.centerLogoSource
        if logoSource != lastCenterLogoSource {
            lastCenterLogoSource = logoSource
            centerLogoImage = nil

            guard !logoSource.isEmpty else {
                return
            }

            // Accept either a bare base64 string or a data-URL string.
            var base64String = logoSource
            if let range = base64String.range(of: ",") {
                base64String = String(base64String[range.upperBound...])
            }

            if let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) {
                centerLogoImage = UIImage(data: data)
            }
        }

        // (3) Start/stop candle countdown timer based on config.
        updateCandleCountdownTimer()
    }

    /// Starts or stops the 1-second countdown timer depending on `showCandleCountdown`.
    private func updateCandleCountdownTimer() {
        if configManager.showCandleCountdown && configManager.candleIntervalMs > 0 {
            if candleCountdownTimer == nil {
                candleCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.setNeedsDisplay()
                }
            }
        } else {
            candleCountdownTimer?.invalidate()
            candleCountdownTimer = nil
        }
    }

    // Extra scrollable space to the right of the newest candle. This space is reachable by
    // scrolling but is NOT shown at rest. Sized so the user can overscroll toward the present
    // until only `minVisibleCandles` candles remain on screen (Bitget-style), with the legacy
    // `rightPaddingCandles` tail as a floor for small/unlaid-out views.
    var rightTailPadding: CGFloat {
        let legacyTail = configManager.itemWidth * configManager.rightPaddingCandles
        let overscrollTail = bounds.size.width - configManager.paddingRight - configManager.itemWidth * configManager.minVisibleCandles
        return max(legacyTail, overscrollTail)
    }

    /// The resting "end" content offset: the newest candle sits flush against the right price
    /// axis with NO right padding visible. Used for the initial scroll-to-end and live-follow,
    /// so the chart always opens on the latest candle without empty space. The user can still
    /// scroll further right (up to `contentSize.width - bounds.width`) to reveal the padding.
    var endContentOffsetX: CGFloat { max(0, contentSize.width - rightTailPadding - bounds.size.width) }

    func reloadContentSize() {
        configManager.reloadScrollViewScale(scale)
        // Content width is determined by candle count plus the configured right padding and a
        // tail of `rightPaddingCandles` candle widths so the newest candle keeps some breathing room.
        let contentWidth = configManager.itemWidth * CGFloat(configManager.modelArray.count) + configManager.paddingRight + rightTailPadding
        contentSize = CGSize(width: contentWidth, height: frame.size.height)
    }

    func reloadContentOffset(_ contentOffsetX: CGFloat, _ animated: Bool = false) {
        let offsetX = max(0, min(contentOffsetX, contentSize.width - bounds.size.width))
        setContentOffset(CGPoint.init(x: offsetX, y: 0), animated: animated)
    }
    

    func contextTranslate(_ context: CGContext, _ x: CGFloat, _ block: (CGContext) -> Void) {
        // Guard against NaN/infinity values that would crash Core Graphics
        guard x.isFinite else {
            block(context)
            return
        }
        context.saveGState()
        context.translateBy(x: x, y: 0)
        block(context)
        context.restoreGState()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), configManager.modelArray.count > 0 else {
            return
        }
        
        // Guard against invalid dimensions that could cause NaN/infinity in calculations
        guard configManager.itemWidth > 0, bounds.size.width > 0, bounds.size.height > 0,
              contentOffset.x.isFinite else {
            return
        }

        calculateBaseHeight()

        // Draw center logo (if provided) behind all candles/lines but inside the main chart area.
        drawCenterLogo(in: context)

        // Background grid behind the candles, fixed to the viewport (not the scrolling content).
        contextTranslate(context, contentOffset.x, { context in
            drawGrid(context)
        })

        contextTranslate(context, CGFloat(visibleRange.lowerBound) * configManager.itemWidth, { context in
            drawCandle(context)
        })

        contextTranslate(context, contentOffset.x, { context in
//            context.setFillColor(UIColor.red.withAlphaComponent(0.1).cgColor)
//            context.fill(CGRect.init(x: 0, y: mainBaseY, width: allWidth, height: mainHeight))

            drawText(context)
            drawValue(context)



            drawHighLow(context)
            drawTime(context)
            drawClosePrice(context)
            drawCandleCountdown(context)
            // Draw user drawings (lines/labels/etc.) below the hover selector overlays.
            // This ensures the right-side hover price pill is always rendered on top.
            drawContext.draw(contentOffset.x)
            drawSelectedLine(context)
            drawSelectedBoard(context)
            drawSelectedTime(context)
        })

        maybeEmitCrosshair()
    }

    /// When hoverInfoMode == "topLayer" the native library does NOT draw a hover
    /// info panel — instead it forwards the selected candle to the app via
    /// onCrosshairChange so the app renders the OHLC readout itself. Polled from
    /// draw(), but only fires when the selection (visible flag or index) changes.
    private func maybeEmitCrosshair() {
        let topLayer = configManager.hoverInfoMode == "topLayer"

        if !topLayer {
            if lastCrosshairVisible {
                lastCrosshairVisible = false
                lastCrosshairIndex = -1
                containerView?.onCrosshairChange?(["visible": false, "index": -1])
            }
            return
        }

        let visible = visibleRange.contains(selectedIndex)
        if visible == lastCrosshairVisible,
           !visible || selectedIndex == lastCrosshairIndex {
            return
        }

        lastCrosshairVisible = visible
        lastCrosshairIndex = visible ? selectedIndex : -1

        guard visible else {
            containerView?.onCrosshairChange?(["visible": false, "index": -1])
            return
        }

        let model = visibleModelArray[selectedIndex - visibleRange.lowerBound]
        containerView?.onCrosshairChange?([
            "visible": true,
            "index": selectedIndex,
            "time": model.dateString,
            "id": Double(model.id),
            "open": Double(model.open),
            "high": Double(model.high),
            "low": Double(model.low),
            "close": Double(model.close),
            "volume": Double(model.volume),
        ])
    }

    func calculateBaseHeight() {
        // Be defensive: `visibleRange` can temporarily be out of bounds during updates/zoom.
        // Clamp it to a valid range before slicing to avoid crashes.
        let count = configManager.modelArray.count
        if count > 0 {
            let lower = max(0, min(visibleRange.lowerBound, count - 1))
            let upper = max(0, min(visibleRange.upperBound, count - 1))
            let lo = min(lower, upper)
            let hi = max(lower, upper)
            visibleRange = lo...hi
            self.visibleModelArray = Array(configManager.modelArray[lo...hi])
        } else {
            visibleRange = 0...0
            self.visibleModelArray = []
        }
        // Layout:
        // - main section: [0 .. mainBoundary)
        // - volume section: [mainBoundary .. volumeBoundary) (optional)
        // - child section: [volumeBoundary .. 1]
        //
        // When volume is hidden, we "merge" volumeFlex into the main chart so the
        // main area expands and the child area stays the same size.
        let mainBoundary = configManager.mainFlex + (configManager.showVolume ? 0 : configManager.volumeFlex)
        // When volume is shown but there is NO child oscillator, give the empty
        // child area to the volume panel so it stays large and fully visible
        // (critical on short landscape viewports where the base volumeFlex alone
        // is too small to be usable).
        let childFlex = 1 - configManager.mainFlex - configManager.volumeFlex
        let volExtra: CGFloat = (configManager.showVolume && childDraw == nil) ? childFlex : 0
        let volumeBoundary = mainBoundary + (configManager.showVolume ? configManager.volumeFlex + volExtra : 0)
        self.volumeRange = mainBoundary...volumeBoundary
        
        self.allHeight = self.bounds.size.height - configManager.paddingBottom
        self.allWidth = self.bounds.size.width
        
        // Auto range (includes MA/BOLL etc), then optionally override with fixed y-axis scale.
        let autoMainRange = mainDraw.minMaxRange(visibleModelArray, configManager)

        // Candle extremes (used to prevent clipping when zooming in via y-axis drag).
        var candleHigh: CGFloat = CGFloat.leastNormalMagnitude
        var candleLow: CGFloat = CGFloat.greatestFiniteMagnitude
        for model in visibleModelArray {
            candleHigh = max(candleHigh, model.high)
            candleLow = min(candleLow, model.low)
        }
        if candleHigh <= candleLow {
            candleHigh = autoMainRange.upperBound
            candleLow = autoMainRange.lowerBound
        }

        // Symmetrize padding around candle high/low so the highest and lowest
        // prices are equally distant from chart edges when indicators (MA/BOLL)
        // extend the range asymmetrically.
        var symMainRange = autoMainRange
        if autoMainRange.upperBound != autoMainRange.lowerBound {
            let paddingAbove = autoMainRange.upperBound - candleHigh
            let paddingBelow = candleLow - autoMainRange.lowerBound
            if paddingAbove > paddingBelow {
                symMainRange = Range<CGFloat>(uncheckedBounds: (lower: candleLow - paddingAbove, upper: autoMainRange.upperBound))
            } else if paddingBelow > paddingAbove {
                symMainRange = Range<CGFloat>(uncheckedBounds: (lower: autoMainRange.lowerBound, upper: candleHigh + paddingBelow))
            }
        }

        // Apply persistent y-axis zoom factor (1.0 = auto-fit, >1 = zoomed out).
        if yAxisZoomFactor > 1.0 {
            let center = (symMainRange.upperBound + symMainRange.lowerBound) / 2
            let range = (symMainRange.upperBound - symMainRange.lowerBound) * yAxisZoomFactor
            self.mainMinMaxRange = Range<CGFloat>(uncheckedBounds: (lower: center - range / 2, upper: center + range / 2))
        } else {
            self.mainMinMaxRange = symMainRange
        }
        self.textHeight = mainDraw.textHeight(font: UIFont.systemFont(ofSize: 11)) / 2

        // Native N7: when sub-panels are stacked (subPanelHeight sent + >=1
        // oscillator), the layout switches to a fixed-height model that mirrors
        // Android — the main chart takes the remaining space above a run of
        // fixed `panelPx` panels (VOL + each oscillator, contiguous). The RN
        // container is grown by the JS side so the main area stays readable.
        if isMultiPanel && configManager.subPanelHeight > 0 {
            let panelPx = configManager.subPanelHeight
            let subPanelCount = (configManager.showVolume ? 1 : 0) + childDrawList.count
            var mainBottom = allHeight - CGFloat(subPanelCount) * panelPx
            let minMain = configManager.paddingTop + textHeight + 60
            if mainBottom < minMain {
                mainBottom = minMain
            }
            self.mainBaseY = configManager.paddingTop - textHeight
            self.mainHeight = mainBottom - mainBaseY - textHeight

            var y = mainBottom
            if configManager.showVolume {
                self.volumeMinMaxRange = volumeDraw.minMaxRange(visibleModelArray, configManager)
                self.volumeBaseY = y + configManager.headerHeight + textHeight
                self.volumeHeight = panelPx - configManager.headerHeight - textHeight
                y += panelPx
            } else {
                self.volumeMinMaxRange = Range<CGFloat>.init(uncheckedBounds: (lower: 0, upper: 0))
                self.volumeBaseY = y
                self.volumeHeight = 0
            }

            childBaseYs = []
            childHeights = []
            childMinMaxRanges = []
            for (p, draw) in childDrawList.enumerated() {
                // Bind the generic-panel context so a generic oscillator's
                // minMaxRange reads the right per-candle subLinesList entry.
                configManager.currentGenericIndex = childGenericIndexList[p]
                configManager.currentPanelIndex = p
                let by = y + configManager.headerHeight + textHeight
                let h = panelPx - configManager.headerHeight - textHeight
                let range = draw.minMaxRange(visibleModelArray, configManager)
                childBaseYs.append(by)
                childHeights.append(h)
                childMinMaxRanges.append(range)
                y += panelPx
            }
            configManager.currentGenericIndex = -1
            configManager.currentPanelIndex = 0

            // Native N7: each stacked panel's range is SNAPPED (no animation) and
            // sanitized, mirroring Android. Animating per-panel scale made a newly
            // added oscillator visibly resize its Y-axis from a stale/garbage seed,
            // and could leave RSI/WR invisible while it slowly lerped from an
            // inverted (no-data) range. Snapping shows the panel at the right scale
            // on the first frame its data is present.
            var needsRedraw = false
            for p in 0..<childMinMaxRanges.count {
                var mn = childMinMaxRanges[p].lowerBound
                var mx = childMinMaxRanges[p].upperBound
                // WR is a 0…-100 oscillator: anchor the top at 0 so it reads like
                // the built-in WR panel instead of auto-fitting to its data band.
                if childDrawList[p] === wrDraw {
                    mx = 0
                    if abs(mn) < 0.01 { mn = -10 }
                }
                if !mn.isFinite || !mx.isFinite || mx < mn {
                    // No / degenerate data this frame — use a small finite range so
                    // the scale never becomes NaN or inverted (which would draw the
                    // lines off-panel and look like the indicator is missing).
                    mn = 0
                    mx = 1
                } else if mx == mn {
                    // Flat line — pad so it renders through the middle of the panel.
                    mx += abs(mx * 0.05)
                    mn -= abs(mn * 0.05)
                    if mx == mn { mx = mn + 1 }
                }
                childMinMaxRanges[p] = Range<CGFloat>(uncheckedBounds: (lower: mn, upper: mx))
            }

            // Animate main/volume as usual.
            let targetMainMin = mainMinMaxRange.lowerBound
            let targetMainMax = mainMinMaxRange.upperBound
            let targetVolMin = volumeMinMaxRange.lowerBound
            let targetVolMax = volumeMinMaxRange.upperBound
            if animatedMainMin.isNaN {
                animatedMainMin = targetMainMin
                animatedMainMax = targetMainMax
                animatedVolMin = targetVolMin
                animatedVolMax = targetVolMax
            } else {
                animatedMainMin += (targetMainMin - animatedMainMin) * scaleAnimLerp
                animatedMainMax += (targetMainMax - animatedMainMax) * scaleAnimLerp
                animatedVolMin += (targetVolMin - animatedVolMin) * scaleAnimLerp
                animatedVolMax += (targetVolMax - animatedVolMax) * scaleAnimLerp
                if abs(animatedMainMax - targetMainMax) > 0.0001 || abs(animatedMainMin - targetMainMin) > 0.0001
                    || abs(animatedVolMax - targetVolMax) > 0.0001 || abs(animatedVolMin - targetVolMin) > 0.0001 {
                    needsRedraw = true
                }
            }
            self.mainMinMaxRange = Range<CGFloat>(uncheckedBounds: (lower: animatedMainMin, upper: animatedMainMax))
            self.volumeMinMaxRange = Range<CGFloat>(uncheckedBounds: (lower: animatedVolMin, upper: animatedVolMax))

            // Keep the single child fields bound to the first panel so legacy
            // reads (hover selection clamp, etc.) still have valid geometry.
            if let firstBaseY = childBaseYs.first {
                self.childBaseY = firstBaseY
                self.childHeight = childHeights[0]
                self.childMinMaxRange = childMinMaxRanges[0]
            }
            if needsRedraw {
                DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay() }
            }
            return
        }

        // Legacy single-panel (fractional flex) layout.
        childBaseYs = []
        childHeights = []
        childMinMaxRanges = []
        self.mainBaseY = configManager.paddingTop - textHeight
        self.mainHeight = allHeight * volumeRange.lowerBound - mainBaseY - textHeight

        if configManager.showVolume {
            self.volumeMinMaxRange = volumeDraw.minMaxRange(visibleModelArray, configManager)
            self.volumeBaseY = allHeight * volumeRange.lowerBound + configManager.headerHeight + textHeight
            // Floor the panel body so the fixed header/text offsets can't drive it
            // negative on short viewports (which would hide the volume bars).
            self.volumeHeight = max(12, allHeight * (volumeRange.upperBound - volumeRange.lowerBound) - configManager.headerHeight - textHeight)
        } else {
            self.volumeMinMaxRange = Range<CGFloat>.init(uncheckedBounds: (lower: 0, upper: 0))
            self.volumeBaseY = allHeight * volumeRange.lowerBound
            self.volumeHeight = 0
        }

        self.childMinMaxRange = childDraw?.minMaxRange(visibleModelArray, configManager) ?? Range<CGFloat>.init(uncheckedBounds: (lower: 0, upper: 0))
        self.childBaseY = allHeight * volumeRange.upperBound + configManager.headerHeight + textHeight
        self.childHeight = allHeight * (1 - volumeRange.upperBound) - configManager.headerHeight - textHeight

        // Animate min/max toward target values for smooth vertical rescaling.
        let targetMainMin = mainMinMaxRange.lowerBound
        let targetMainMax = mainMinMaxRange.upperBound
        let targetVolMin = volumeMinMaxRange.lowerBound
        let targetVolMax = volumeMinMaxRange.upperBound
        let targetChildMin = childMinMaxRange.lowerBound
        let targetChildMax = childMinMaxRange.upperBound

        if animatedMainMin.isNaN {
            animatedMainMin = targetMainMin
            animatedMainMax = targetMainMax
            animatedVolMin = targetVolMin
            animatedVolMax = targetVolMax
            animatedChildMin = targetChildMin
            animatedChildMax = targetChildMax
        } else {
            animatedMainMin += (targetMainMin - animatedMainMin) * scaleAnimLerp
            animatedMainMax += (targetMainMax - animatedMainMax) * scaleAnimLerp
            animatedVolMin += (targetVolMin - animatedVolMin) * scaleAnimLerp
            animatedVolMax += (targetVolMax - animatedVolMax) * scaleAnimLerp
            animatedChildMin += (targetChildMin - animatedChildMin) * scaleAnimLerp
            animatedChildMax += (targetChildMax - animatedChildMax) * scaleAnimLerp
            let needsRedraw =
                abs(animatedMainMax - targetMainMax) > 0.0001
                || abs(animatedMainMin - targetMainMin) > 0.0001
                || abs(animatedVolMax - targetVolMax) > 0.0001
                || abs(animatedVolMin - targetVolMin) > 0.0001
                || abs(animatedChildMax - targetChildMax) > 0.0001
                || abs(animatedChildMin - targetChildMin) > 0.0001
            if needsRedraw {
                DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay() }
            }
        }
        self.mainMinMaxRange = Range<CGFloat>(uncheckedBounds: (lower: animatedMainMin, upper: animatedMainMax))
        self.volumeMinMaxRange = Range<CGFloat>(uncheckedBounds: (lower: animatedVolMin, upper: animatedVolMax))
        self.childMinMaxRange = Range<CGFloat>(uncheckedBounds: (lower: animatedChildMin, upper: animatedChildMax))
    }

    func resetAnimatedScaleValues() {
        animatedMainMin = .nan
        animatedMainMax = .nan
        animatedVolMin = .nan
        animatedVolMax = .nan
        animatedChildMin = .nan
        animatedChildMax = .nan
    }

    private func isInRightYAxisArea(_ point: CGPoint) -> Bool {
        // Only allow scaling in the main chart vertical span.
        let mainTop = mainBaseY
        let mainBottom = mainBaseY + mainHeight
        if point.y < mainTop || point.y > mainBottom {
            return false
        }
        // Hit target on the far right where y-axis labels are drawn.
        let width = max(yAxisGestureWidth, configManager.paddingRight)
        return point.x >= (bounds.size.width - width)
    }

    /// Convert gesture location to view-relative coordinates (not affected by scroll offset).
    /// In UIScrollView, location(in: self) returns bounds coordinates where origin = contentOffset.
    private func viewLocationFrom(_ gestureRecognizer: UIGestureRecognizer) -> CGPoint {
        let locationInSuperview = gestureRecognizer.location(in: superview ?? self)
        let viewOriginInSuperview = superview != nil ? frame.origin : CGPoint.zero
        return CGPoint(
            x: locationInSuperview.x - viewOriginInSuperview.x,
            y: locationInSuperview.y - viewOriginInSuperview.y
        )
    }

    // Only begin our y-axis pan when user drags vertically inside the right y-axis region.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === yAxisPanGesture {
            let p = viewLocationFrom(gestureRecognizer)
            guard isInRightYAxisArea(p) else { return false }
            let v = (gestureRecognizer as? UIPanGestureRecognizer)?.velocity(in: self) ?? .zero
            return abs(v.y) > abs(v.x)
        }
        if gestureRecognizer === longPressGesture {
            let p = viewLocationFrom(gestureRecognizer)
            // Never allow the long-press hover selector to start from the y-axis area.
            return !isInRightYAxisArea(p)
        }
        return true
    }

    // Prevent scroll view's own pan from competing when we are handling y-axis scaling.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === yAxisPanGesture || otherGestureRecognizer === yAxisPanGesture {
            return false
        }
        // While long-press hovering, do NOT allow other scroll views (e.g. parent vertical ScrollView)
        // to recognize their pan simultaneously. Otherwise dragging the crosshair scrolls the page.
        if gestureRecognizer === longPressGesture || otherGestureRecognizer === longPressGesture {
            if isScrollViewPanGesture(otherGestureRecognizer) || isScrollViewPanGesture(gestureRecognizer) {
                return false
            }
        }
        return true
    }

    private func isScrollViewPanGesture(_ gesture: UIGestureRecognizer) -> Bool {
        // Match UIScrollView pan gestures, including RN's internal scroll view subclasses.
        guard let pan = gesture as? UIPanGestureRecognizer else { return false }
        guard let v = pan.view else { return false }
        // `HTKLineView` is also a UIScrollView; we only care about OTHER scroll views here.
        return (v is UIScrollView) && (v !== self)
    }

    private func nearestParentScrollView() -> UIScrollView? {
        var v = superview
        while let view = v {
            if let sv = view as? UIScrollView, sv !== self {
                return sv
            }
            v = view.superview
        }
        return nil
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // Improve long-press reliability when embedded inside a parent (vertical) ScrollView.
        // We don't want to fully block scrolling; long-press will quickly fail if the user drags.
        if let parent = nearestParentScrollView() {
            parent.panGestureRecognizer.require(toFail: longPressGesture)
            parentScrollViewDuringLongPress = parent
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let boundsChanged = lastKnownBoundsSize != bounds.size
        let contentChanged = lastKnownContentSize != contentSize

        // Always (re)apply a pending initial scroll-to-end as soon as we have a real width, even
        // if neither bounds nor content changed since the last pass. Otherwise a layout pass that
        // doesn't change sizes can skip the initial positioning and leave the chart parked on
        // older candles (the "shows older candle on first render" bug).
        let needsInitialScrollToEnd = configManager.shouldScrollToEnd
            && !didApplyInitialScrollToEnd
            && bounds.size.width > 0

        guard boundsChanged || contentChanged || needsInitialScrollToEnd else { return }

        // Whether the chart was resting at the newest candle BEFORE this resize, measured
        // against the OLD width/content flush position (not the padded max). A rotation or
        // fullscreen toggle must keep an end-pinned chart pinned; otherwise the offset clamp
        // below can leave the right-padding tail exposed as a blank gap before the price axis.
        let oldWidth = lastKnownBoundsSize.width
        let oldTail = max(
            configManager.itemWidth * configManager.rightPaddingCandles,
            oldWidth - configManager.paddingRight - configManager.itemWidth * configManager.minVisibleCandles
        )
        let wasAtEnd = oldWidth > 0
            && contentOffset.x + 1 >= max(0, lastKnownContentSize.width - oldTail - oldWidth)

        lastKnownBoundsSize = bounds.size

        // The overscroll tail (rightTailPadding) depends on the view width, so recompute the
        // content size whenever bounds change (first layout, rotation, fullscreen toggle).
        if boundsChanged && !configManager.modelArray.isEmpty {
            reloadContentSize()
        }
        lastKnownContentSize = contentSize

        if !isShowingLoadingSpinner {
            contentInset = UIEdgeInsets(top: 0, left: baseLeftInset, bottom: 0, right: 0)
        }

        // Clamp any invalid contentOffset that could have been set while bounds were 0.
        let maxOffsetX = max(0, contentSize.width - bounds.size.width)
        if contentOffset.x.isFinite, contentOffset.x > maxOffsetX + 0.5 {
            setContentOffset(CGPoint(x: maxOffsetX, y: 0), animated: false)
        }

        // Apply the pending initial "scroll to end" once we have a real width. We intentionally do
        // not require contentSize > bounds: with few candles the end offset clamps to 0, which still
        // keeps the newest candle visible.
        if needsInitialScrollToEnd {
            scrollToEndIfPossible(animated: false)
        } else if boundsChanged && wasAtEnd {
            // Keep the newest candle flush against the price axis across resizes.
            scrollToEndIfPossible(animated: false)
        } else {
            // Ensure visibleRange matches the latest layout/offset (also triggers redraw).
            scrollViewDidScroll(self)
        }
    }

    /// Marks that the initial scroll-to-end still needs to be applied (e.g. data arrived before
    /// the view had a real width). The next `layoutSubviews` will pin the chart to the newest candle.
    func requestInitialScrollToEnd() {
        didApplyInitialScrollToEnd = false
        setNeedsLayout()
    }

    /// Marks the initial scroll-to-end as already applied (caller pinned to the end directly).
    func markInitialScrollToEndApplied() {
        didApplyInitialScrollToEnd = true
    }

    private func scrollToEndIfPossible(animated: Bool) {
        guard bounds.size.width > 0 else { return }
        // Rest at the flush end (newest candle against the axis), not the padded max.
        let endOffsetX = endContentOffsetX
        didApplyInitialScrollToEnd = true
        setContentOffset(CGPoint(x: endOffsetX, y: 0), animated: animated)
        scrollViewDidScroll(self)
    }

    // MARK: - Loading spinner

    func showLoadingIndicator() {
        guard !isShowingLoadingSpinner else { return }
        isShowingLoadingSpinner = true
        loadingSpinner.startAnimating()
        // Add left inset so spinner has room
        contentInset = UIEdgeInsets(top: 0, left: baseLeftInset + 48, bottom: 0, right: 0)
        updateLoadingSpinnerPosition()
        UIView.animate(withDuration: 0.25) {
            self.loadingSpinner.alpha = 1
        }
    }

    func hideLoadingIndicator(animated: Bool = true) {
        guard isShowingLoadingSpinner else { return }
        isShowingLoadingSpinner = false
        let hide = {
            self.loadingSpinner.alpha = 0
            self.contentInset = UIEdgeInsets(top: 0, left: self.baseLeftInset, bottom: 0, right: 0)
        }
        let done = { (_: Bool) in
            self.loadingSpinner.stopAnimating()
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: hide, completion: done)
        } else {
            hide()
            done(true)
        }
    }

    private func updateLoadingSpinnerPosition() {
        let spinnerSize: CGFloat = 20
        let y = bounds.height / 2
        // Position in content coordinates at the very left, inside the inset area
        loadingSpinner.frame = CGRect(
            x: contentOffset.x - contentInset.left + (contentInset.left - spinnerSize) / 2,
            y: y - spinnerSize / 2,
            width: spinnerSize,
            height: spinnerSize
        )
    }

    // MARK: - Animated close price

    private func animateClosePriceTo(_ newValue: CGFloat) {
        guard newValue.isFinite else { return }

        if displayedClosePrice.isNaN {
            displayedClosePrice = newValue
            closePriceAnimationTarget = newValue
            return
        }
        // Only start a new animation when the actual target price changes,
        // not on every draw() triggered by the animation's own setNeedsDisplay().
        if !closePriceAnimationTarget.isNaN && abs(closePriceAnimationTarget - newValue) < 0.000001 {
            return
        }
        closePriceAnimationTarget = newValue

        closePriceAnimationStart = displayedClosePrice
        closePriceAnimationEnd = newValue
        closePriceAnimationStartTime = CACurrentMediaTime()

        if closePriceDisplayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(closePriceAnimationTick))
            link.add(to: RunLoop.main, forMode: .common)
            closePriceDisplayLink = link
        }
    }

    @objc private func closePriceAnimationTick() {
        let elapsed = CACurrentMediaTime() - closePriceAnimationStartTime
        let progress = min(elapsed / closePriceAnimationDuration, 1.0)
        // Ease-out cubic
        let t = 1.0 - pow(1.0 - progress, 3)
        displayedClosePrice = closePriceAnimationStart + (closePriceAnimationEnd - closePriceAnimationStart) * CGFloat(t)

        if progress >= 1.0 {
            displayedClosePrice = closePriceAnimationEnd
            closePriceDisplayLink?.invalidate()
            closePriceDisplayLink = nil
        }
        setNeedsDisplay()
    }

    private func enterHoverModeIfNeeded() {
        guard !isHoverModeLocked else { return }
        isHoverModeLocked = true

        wasScrollEnabledBeforeLongPress = isScrollEnabled
        isScrollEnabled = false

        let parent = parentScrollViewDuringLongPress ?? nearestParentScrollView()
        parentScrollViewDuringLongPress = parent
        if let parent {
            parentWasScrollEnabledBeforeLongPress = parent.isScrollEnabled
            parent.isScrollEnabled = false
        }
    }

    private func exitHoverModeIfNeeded() {
        guard isHoverModeLocked else { return }
        isHoverModeLocked = false

        isScrollEnabled = wasScrollEnabledBeforeLongPress
        if let parent = parentScrollViewDuringLongPress {
            parent.isScrollEnabled = parentWasScrollEnabledBeforeLongPress
        }
    }

    @objc private func yAxisPanSelector(_ pan: UIPanGestureRecognizer) {
        let point = viewLocationFrom(pan)

        switch pan.state {
        case .began:
            guard isInRightYAxisArea(point) else { return }
            yAxisScaleStartY = point.y
            yAxisScaleStartFactor = yAxisZoomFactor
            setNeedsDisplay()

        case .changed:
            guard yAxisScaleStartY.isFinite else { return }
            let dy = point.y - yAxisScaleStartY
            let denom = max(1, mainHeight * yAxisGestureSensitivityFactor)
            let factor = yAxisScaleStartFactor * exp(dy / denom)
            // Clamp: 1.0 (100% auto-fit) to 5.0 (20% zoom-out)
            yAxisZoomFactor = max(1.0, min(5.0, factor))
            setNeedsDisplay()

        case .ended, .cancelled, .failed:
            yAxisScaleStartY = .nan
            setNeedsDisplay()
        default:
            break
        }
    }

    /// Draw a semi-transparent logo image centered in the main chart area, behind candles.
    private func drawCenterLogo(in context: CGContext) {
        guard
            let image = centerLogoImage,
            mainHeight > 0,
            allWidth > 0
        else {
            return
        }

        // Constrain logo size relative to chart dimensions (e.g. at most ~35% of width/height).
        let maxLogoWidth = allWidth * 0.35
        let maxLogoHeight = mainHeight * 0.35
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return
        }

        let widthScale = maxLogoWidth / imageSize.width
        let heightScale = maxLogoHeight / imageSize.height
        let scale = min(widthScale, heightScale, 1.0)

        let drawWidth = imageSize.width * scale
        let drawHeight = imageSize.height * scale
        
        // Keep the logo visually fixed in the center of the viewport while the
        // candles (scrollable content) move underneath it.
        //
        // The scroll view exposes content in the range
        // [contentOffset.x, contentOffset.x + bounds.width]. To pin the logo to
        // the visual center of the screen, we place it at:
        //   worldX = contentOffset.x + (bounds.width - logoWidth) / 2
        // so that on-screen X is always (bounds.width - logoWidth) / 2.
        let originX = contentOffset.x + (allWidth - drawWidth) / 2.0
        let originY = mainBaseY + (mainHeight - drawHeight) / 2.0
        let drawRect = CGRect(x: originX, y: originY, width: drawWidth, height: drawHeight)

        context.saveGState()
        // Light transparency so candles and grid remain clearly visible.
        context.setAlpha(0.10)
        image.draw(in: drawRect)
        context.restoreGState()
    }

    /// Draws the background grid behind the candles: horizontal lines aligned with the
    /// Y-axis price labels and vertical lines dividing the width into 5 regions (4 lines).
    /// The color matches the Y-axis price text color but with a very low opacity so it is
    /// barely noticeable.
    func drawGrid(_ context: CGContext) {
        guard allWidth > 0, mainHeight > 0 else {
            return
        }

        let gridColor = configManager.textColor.withAlphaComponent(0.08)
        // 1 physical pixel regardless of screen scale.
        let lineWidth = 1.0 / UIScreen.main.scale

        context.saveGState()
        context.setStrokeColor(gridColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineDash(phase: 0, lengths: [])

        // Horizontal lines aligned with the Y-axis price labels (4 values => 4 lines).
        let rowCount = 4
        let rowDistance = mainHeight / CGFloat(max(1, rowCount - 1))
        for i in 0..<rowCount {
            let y = mainBaseY + rowDistance * CGFloat(i)
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: allWidth, y: y))
        }

        // Vertical lines: split the width into 5 regions with 4 lines.
        let verticalRegions = 5
        let columnSpace = allWidth / CGFloat(verticalRegions)
        let bottom = childAreaBottom
        for i in 1..<verticalRegions {
            let x = columnSpace * CGFloat(i)
            context.move(to: CGPoint(x: x, y: mainBaseY))
            context.addLine(to: CGPoint(x: x, y: bottom))
        }

        context.strokePath()
        context.restoreGState()
    }

    func yFromValue(_ value: CGFloat) -> CGFloat {
        guard mainHeight > 0 else {
            return mainBaseY
        }
        let scale = (mainMinMaxRange.upperBound - mainMinMaxRange.lowerBound) / mainHeight
        var y = mainBaseY + mainHeight * 0.5
        if scale.isFinite && scale != 0 {
            y = mainBaseY + (mainMinMaxRange.upperBound - value) / scale
        }
        return y.isFinite ? y : mainBaseY
    }
    
    func valueFromY(_ y: CGFloat) -> CGFloat {
        guard mainHeight > 0 else {
            return mainMinMaxRange.lowerBound
        }
        let scale = (mainMinMaxRange.upperBound - mainMinMaxRange.lowerBound) / mainHeight
        var value = scale * mainHeight * 0.5
        if scale.isFinite && scale != 0 {
            value = mainMinMaxRange.upperBound - (y - mainBaseY) * scale
        }
        return value.isFinite ? value : mainMinMaxRange.lowerBound
    }
    
    func xFromValue(_ value: CGFloat) -> CGFloat {
        guard let firstItem = configManager.modelArray.first, let lastItem = configManager.modelArray.last else {
            return 0
        }
        guard configManager.modelArray.count > 1, configManager.itemWidth > 0 else {
            return 0
        }
        let scale = CGFloat(lastItem.id - firstItem.id) / (configManager.itemWidth * CGFloat(configManager.modelArray.count - 1))
        guard scale.isFinite && scale != 0 else {
            return 0
        }
        let x = (value - CGFloat(firstItem.id)) / scale + configManager.itemWidth / 2.0 - contentOffset.x
        return x.isFinite ? x : 0
    }

    func valueFromX(_ x: CGFloat) -> CGFloat {
        guard let firstItem = configManager.modelArray.first, let lastItem = configManager.modelArray.last else {
            return 0
        }
        guard configManager.modelArray.count > 1, configManager.itemWidth > 0 else {
            return 0
        }
        let scale = CGFloat(lastItem.id - firstItem.id) / (configManager.itemWidth * CGFloat(configManager.modelArray.count - 1))
        guard scale.isFinite && scale != 0 else {
            return 0
        }
        let value = scale * (x + contentOffset.x - configManager.itemWidth / 2.0) + CGFloat(firstItem.id)
        return value.isFinite ? value : 0
    }

    func drawCandle(_ context: CGContext) {
        if (configManager.isMinute) {
            mainDraw.drawGradient(visibleModelArray, mainMinMaxRange.upperBound, mainMinMaxRange.lowerBound, allWidth, mainBaseY, mainHeight, context, configManager)
        }

        let lastModelInArray = configManager.modelArray.last
        let animatedClose = displayedClosePrice.isNaN ? nil : displayedClosePrice

        for (i, model) in visibleModelArray.enumerated() {
            var savedClose: CGFloat?
            if let animatedClose = animatedClose, model === lastModelInArray {
                savedClose = model.close
                model.close = animatedClose
            }
            mainDraw.drawCandle(model, i, mainMinMaxRange.upperBound, mainMinMaxRange.lowerBound, mainBaseY, mainHeight, context, configManager)
            if let saved = savedClose {
                model.close = saved
            }
            if configManager.showVolume {
                volumeDraw.drawCandle(model, i, volumeMinMaxRange.upperBound, volumeMinMaxRange.lowerBound, volumeBaseY, volumeHeight, context, configManager)
            }

            let lastIndex = i == 0 ? i : i - 1
            let lastModel = visibleModelArray[lastIndex]
            mainDraw.drawLine(model, lastModel, mainMinMaxRange.upperBound, mainMinMaxRange.lowerBound, mainBaseY, mainHeight, i, lastIndex, context, configManager)
            if configManager.showVolume {
                volumeDraw.drawLine(model, lastModel, volumeMinMaxRange.upperBound, volumeMinMaxRange.lowerBound, volumeBaseY, volumeHeight, i, lastIndex, context, configManager)
            }

            if isMultiPanel {
                for p in 0..<childDrawList.count {
                    configManager.currentGenericIndex = childGenericIndexList[p]
                    configManager.currentPanelIndex = p
                    let range = childMinMaxRanges[p]
                    childDrawList[p].drawCandle(model, i, range.upperBound, range.lowerBound, childBaseYs[p], childHeights[p], context, configManager)
                    childDrawList[p].drawLine(model, lastModel, range.upperBound, range.lowerBound, childBaseYs[p], childHeights[p], i, lastIndex, context, configManager)
                }
                configManager.currentGenericIndex = -1
                configManager.currentPanelIndex = 0
            } else {
                childDraw?.drawCandle(model, i, childMinMaxRange.upperBound, childMinMaxRange.lowerBound, childBaseY, childHeight, context, configManager)
                childDraw?.drawLine(model, lastModel, childMinMaxRange.upperBound, childMinMaxRange.lowerBound, childBaseY, childHeight, i, lastIndex, context, configManager)
            }
        }

        // Ichimoku future kumo: continues past the newest candle into the
        // right-side overscroll space, but only when that edge is on screen.
        if visibleRange.upperBound == configManager.modelArray.count - 1,
           let lastModel = visibleModelArray.last {
            mainDraw.drawIchiFuture(lastModel, visibleModelArray.count - 1, mainMinMaxRange.upperBound, mainMinMaxRange.lowerBound, mainBaseY, mainHeight, context, configManager)
        }
    }

    func drawText(_ context: CGContext) {
        var model = visibleModelArray.last
        if visibleRange.contains(selectedIndex) {
            model = visibleModelArray[selectedIndex - visibleRange.lowerBound]
        }
        if let model = model {
            let baseX: CGFloat = 5
            mainDraw.drawText(model, baseX, 10, context, configManager)
            if configManager.showVolume {
                volumeDraw.drawText(model, baseX, volumeBaseY - configManager.headerHeight, context, configManager)
            }
            if isMultiPanel {
                for p in 0..<childDrawList.count {
                    configManager.currentGenericIndex = childGenericIndexList[p]
                    configManager.currentPanelIndex = p
                    childDrawList[p].drawText(model, baseX, childBaseYs[p] - configManager.headerHeight, context, configManager)
                }
                configManager.currentGenericIndex = -1
                configManager.currentPanelIndex = 0
            } else {
                childDraw?.drawText(model, baseX, childBaseY - configManager.headerHeight, context, configManager)
            }
        }
    }

    func drawValue(_ context: CGContext) {
        let baseX = self.allWidth
        mainDraw.drawValue(mainMinMaxRange.upperBound, mainMinMaxRange.lowerBound, baseX, mainBaseY, mainHeight, context, configManager)
        if configManager.showVolume {
            volumeDraw.drawValue(volumeMinMaxRange.upperBound, volumeMinMaxRange.lowerBound, baseX, volumeBaseY, volumeHeight, context, configManager)
        }
        if isMultiPanel {
            for p in 0..<childDrawList.count {
                configManager.currentGenericIndex = childGenericIndexList[p]
                configManager.currentPanelIndex = p
                let range = childMinMaxRanges[p]
                childDrawList[p].drawValue(range.upperBound, range.lowerBound, baseX, childBaseYs[p], childHeights[p], context, configManager)
            }
            configManager.currentGenericIndex = -1
            configManager.currentPanelIndex = 0
        } else {
            childDraw?.drawValue(childMinMaxRange.upperBound, childMinMaxRange.lowerBound, baseX, childBaseY, childHeight, context, configManager)
        }
    }

    func drawTime(_ context: CGContext) {
        let count = 6
        let valueDistance = self.allWidth / CGFloat(count - 1)
        for i in 0..<count {
            let font = configManager.createFont(configManager.candleTextFontSize)
            let x = valueDistance * CGFloat(i)
            let itemNumber = (x - 1 + contentOffset.x) / configManager.itemWidth
            var itemIndex = Int(ceil(itemNumber))
            itemIndex -= 1
            itemIndex -= visibleRange.lowerBound
            itemIndex = max(0, itemIndex)
            if (itemIndex >= visibleModelArray.count) {
                continue
            }
            let item = visibleModelArray[itemIndex]
            let title = configManager.formatBottomDate(epochMs: item.id)
            let width = mainDraw.textWidth(title: title, font: font)
            let height = mainDraw.textHeight(font: font)
            let y = childAreaBottom + (configManager.paddingBottom - height) / 2
            mainDraw.drawText(title: title, point: CGPoint.init(x: x - width / 2.0, y: y), color: configManager.textColor, font: font, context: context, configManager: configManager)
        }
    }

    func drawHighLow(_ context: CGContext) {
        guard !configManager.isMinute else {
            return
        }
        var highIndex = 0
        var lowIndex = 0
        for (i, model) in visibleModelArray.enumerated() {
            if (model.high > visibleModelArray[highIndex].high) {
                highIndex = i
            }
            if (model.low < visibleModelArray[lowIndex].low) {
                lowIndex = i
            }
        }

        let drawValue: (Int, CGFloat) -> Void = { [weak self] (index, value) in
            guard let this = self else {
                return
            }

            var title = this.configManager.precision(value, this.configManager.price)
            let font = this.configManager.createFont(this.configManager.candleTextFontSize)
            let lineString = "--"
            let offset = CGFloat(index + this.visibleRange.lowerBound) * this.configManager.itemWidth - this.contentOffset.x
            let halfWidth = this.allWidth / 2
            var x = offset + this.configManager.itemWidth / 2

            var y = this.yFromValue(value)
            if (offset < halfWidth) {
                title = lineString + title
            } else {
                title = title + lineString
                x -= this.mainDraw.textWidth(title: title, font: font)
            }
            y -= this.mainDraw.textHeight(font: font) / 2
            y -= 1
            this.mainDraw.drawText(title: title, point: CGPoint.init(x: x, y: y), color: this.configManager.candleTextColor, font: font, context: context, configManager: this.configManager)
        }
        drawValue(highIndex, visibleModelArray[highIndex].high)
        drawValue(lowIndex, visibleModelArray[lowIndex].low)

    }

    func drawClosePrice(_ context: CGContext) {
        guard let lastModel = configManager.modelArray.last else {
            closePriceCenterPillRect = .zero
            return
        }

        // Kick off animated interpolation toward the latest close price.
        animateClosePriceTo(lastModel.close)
        let animatedClose = displayedClosePrice.isNaN ? lastModel.close : displayedClosePrice

        let offset = CGFloat(visibleRange.upperBound) * configManager.itemWidth - contentOffset.x
        let valueWidth = mainDraw.textWidth(title: configManager.precision(animatedClose, configManager.price), font: configManager.createFont(configManager.rightTextFontSize))
        let showCenter = offset > allWidth - valueWidth - configManager.itemWidth
        animationView.isHidden = true
        if (showCenter) {
            drawClosePriceCenter(context, lastModel, animatedClose)
        } else {
            // Clear the tap target when viewing the present (center pill not shown).
            closePriceCenterPillRect = .zero
            drawClosePriceRight(context, lastModel, offset, animatedClose)
        }
    }

    func drawClosePriceCenter(_ context: CGContext, _ lastModel: HTKLineModel, _ animatedClose: CGFloat) {
        let title = configManager.precision(animatedClose, configManager.price)
        let font = configManager.createFont(configManager.candleTextFontSize)
        let width = mainDraw.textWidth(title: title, font: font)
        let height = mainDraw.textHeight(font: font)
        let paddingHorizontal: CGFloat = 7
        let paddingVertical: CGFloat = 5
        let triangleWidth: CGFloat = 5
        let triangleHeight: CGFloat = 7
        let triangleMarginLeft: CGFloat = 3
        let x = allWidth - configManager.paddingRight
        let rectHeight = height + paddingVertical * 2
        let y = max(mainBaseY - textHeight + rectHeight / 2, min(mainBaseY + mainHeight + textHeight - rectHeight / 2, yFromValue(animatedClose)))
        let rectWidth = paddingHorizontal + width + triangleMarginLeft + triangleWidth + paddingHorizontal
        let rect = CGRect.init(x: x - rectWidth / 2, y: y - height / 2 - paddingVertical, width: rectWidth, height: rectHeight)

        // Save the pill rect for tap-to-scroll-to-present detection.
        closePriceCenterPillRect = rect

        context.saveGState()
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.setStrokeColor(configManager.closePriceCenterSeparatorColor.cgColor)
        context.setLineWidth(configManager.lineWidth / 3)
        context.addLines(between: [CGPoint.init(x: 0, y: y), CGPoint.init(x: allWidth, y: y)])
        context.strokePath()
        context.restoreGState()

        let rectPath = UIBezierPath.init(roundedRect: rect, cornerRadius: rect.size.height / 2)
        context.setFillColor(configManager.closePriceCenterBackgroundColor.cgColor)
        context.addPath(rectPath.cgPath)
        context.fillPath()
        context.setStrokeColor(configManager.closePriceCenterBorderColor.cgColor)
        context.addPath(rectPath.cgPath)
        context.strokePath()
        mainDraw.drawText(title: title, point: CGPoint.init(x: rect.minX + paddingHorizontal, y: rect.minY + paddingVertical), color: configManager.closePriceRightSeparatorColor, font: font, context: context, configManager: configManager)

        let trianglePath = UIBezierPath.init()
        trianglePath.move(to: CGPoint.init(x: rect.maxX - paddingHorizontal, y: y))
        trianglePath.addLine(to: CGPoint.init(x: rect.maxX - paddingHorizontal - triangleWidth, y: y + triangleHeight / 2))
        trianglePath.addLine(to: CGPoint.init(x: rect.maxX - paddingHorizontal - triangleWidth, y: y - triangleHeight / 2))
        trianglePath.close()
        context.setFillColor(configManager.closePriceCenterTriangleColor.cgColor)
        context.addPath(trianglePath.cgPath)
        context.fillPath()
    }

    func drawClosePriceRight(_ context: CGContext, _ lastModel: HTKLineModel, _ offset: CGFloat, _ animatedClose: CGFloat) {
        let y = yFromValue(animatedClose)

        // --- Dashed line from last candle to the right edge ---
        context.saveGState()
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.setStrokeColor(configManager.closePriceRightSeparatorColor.cgColor)
        context.setLineWidth(configManager.lineWidth / 3)
        let x = offset + configManager.itemWidth / 2
        context.addLines(between: [CGPoint.init(x: x, y: y), CGPoint.init(x: allWidth, y: y)])
        context.strokePath()
        context.restoreGState()

        // --- Compute price text ---
        let priceTitle = configManager.precision(animatedClose, configManager.price)
        let font = configManager.createFont(configManager.rightTextFontSize)
        let color = configManager.closePriceRightSeparatorColor
        let priceWidth = mainDraw.textWidth(title: priceTitle, font: font)
        let lineHeight = mainDraw.textHeight(font: font)

        // --- Compute optional countdown text ---
        let countdownTitle = candleCountdownString()
        let hasCountdown = countdownTitle != nil
        let countdownWidth = hasCountdown ? mainDraw.textWidth(title: countdownTitle!, font: font) : 0

        // --- Pill dimensions ---
        let paddingH: CGFloat = 5
        let paddingV: CGFloat = 3
        let spacing: CGFloat = hasCountdown ? 2 : 0
        let contentWidth = max(priceWidth, countdownWidth)
        let pillWidth = contentWidth + paddingH * 2
        let pillHeight = lineHeight + (hasCountdown ? lineHeight + spacing : 0) + paddingV * 2
        let pillX = allWidth - pillWidth
        let pillY = y - pillHeight / 2

        // Clamp within main chart area.
        let clampedPillY = max(mainBaseY - textHeight, min(mainBaseY + mainHeight + textHeight - pillHeight, pillY))

        let pillRect = CGRect(x: pillX, y: clampedPillY, width: pillWidth, height: pillHeight)
        let cornerRadius: CGFloat = 4

        // --- Draw pill background ---
        let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: cornerRadius)
        context.setFillColor(configManager.closePriceRightBackgroundColor.cgColor)
        context.addPath(pillPath.cgPath)
        context.fillPath()

        // --- Draw pill border ---
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(0.8)
        context.addPath(pillPath.cgPath)
        context.strokePath()

        // --- Draw price text (centered in pill) ---
        let priceX = pillRect.minX + (pillWidth - priceWidth) / 2
        let priceY = pillRect.minY + paddingV
        mainDraw.drawText(title: priceTitle, point: CGPoint(x: priceX, y: priceY), color: color, font: font, context: context, configManager: configManager)

        // --- Draw countdown text below price (centered in pill) ---
        if hasCountdown, let countdown = countdownTitle {
            let countdownX = pillRect.minX + (pillWidth - countdownWidth) / 2
            let countdownY = priceY + lineHeight + spacing
            mainDraw.drawText(title: countdown, point: CGPoint(x: countdownX, y: countdownY), color: color, font: font, context: context, configManager: configManager)
        }

        // --- Real-time bid/ask labels (Bitget style), left of the price pill ---
        drawBidAskLabels(context, lineY: y, anchorRight: pillRect.minX - 6)

        // --- Lottie animation for minute charts ---
        if (configManager.isMinute) {
            animationView.isHidden = false
            UIView.animate(withDuration: 0.15) {
                self.animationView.center = CGPoint.init(x: x + self.configManager.itemWidth / 2 + self.contentOffset.x, y: y)
            }
        }
    }

    /// Draws the real-time Ask (above) and Bid (below) outlined labels on the close-price
    /// line, right-aligned against `anchorRight`. Enabled via the `bidAsk` prop.
    func drawBidAskLabels(_ context: CGContext, lineY: CGFloat, anchorRight: CGFloat) {
        guard configManager.showBidAsk, configManager.bidPrice > 0, configManager.askPrice > 0 else {
            return
        }
        let font = configManager.createFont(configManager.rightTextFontSize)
        let paddingH: CGFloat = 6
        let paddingV: CGFloat = 3
        let gap: CGFloat = 3 // distance between the price line and each label box
        let items: [(label: String, price: CGFloat, color: UIColor, above: Bool)] = [
            (configManager.askText, configManager.askPrice, configManager.decreaseColor, true),
            (configManager.bidText, configManager.bidPrice, configManager.increaseColor, false),
        ]
        for item in items {
            let title = item.label + "  " + configManager.precision(item.price, configManager.price)
            let textWidth = mainDraw.textWidth(title: title, font: font)
            let textHeight = mainDraw.textHeight(font: font)
            let boxWidth = textWidth + paddingH * 2
            let boxHeight = textHeight + paddingV * 2
            let boxX = anchorRight - boxWidth
            let boxY = item.above ? lineY - gap - boxHeight : lineY + gap
            let rect = CGRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            context.setFillColor(configManager.closePriceRightBackgroundColor.cgColor)
            context.addPath(path.cgPath)
            context.fillPath()
            context.setStrokeColor(item.color.cgColor)
            context.setLineWidth(1)
            context.addPath(path.cgPath)
            context.strokePath()
            mainDraw.drawText(title: title, point: CGPoint(x: boxX + paddingH, y: boxY + paddingV), color: item.color, font: font, context: context, configManager: configManager)
        }
    }

    /// Returns the countdown string for the current candle, or nil if not applicable.
    private func candleCountdownString() -> String? {
        guard configManager.showCandleCountdown,
              configManager.candleIntervalMs > 0,
              let lastModel = configManager.modelArray.last else {
            return nil
        }

        let count = configManager.modelArray.count
        guard count > 0, visibleRange.upperBound >= count - 1 else {
            return nil
        }

        let intervalMs = configManager.candleIntervalMs
        let rawId = Double(lastModel.id)
        let candleOpenMs = rawId < 9_999_999_999 ? rawId * 1000.0 : rawId
        let nowMs = Date().timeIntervalSince1970 * 1000.0

        // Compute when the current candle closes. We anchor on the candle's real open time
        // (already aligned by the data source, e.g. UTC vs UTC+8 / Monday-vs-Sunday week start),
        // rather than re-deriving boundaries from the Unix epoch (which would snap weekly candles
        // to Thursdays). Monthly periods use calendar math; weekStartDay is only a fallback for
        // when no usable open time is available.
        let monthThresholdMs: Double = 27 * 86_400_000 // anything longer than ~27 days is monthly
        let candleCloseMs: Double
        if intervalMs > monthThresholdMs {
            candleCloseMs = nextMonthCloseMs(fromOpenMs: candleOpenMs > 0 ? candleOpenMs : nowMs)
        } else if candleOpenMs > 0 {
            candleCloseMs = candleOpenMs + intervalMs
        } else {
            // No reliable open time to anchor on.
            candleCloseMs = fallbackCloseMs(nowMs: nowMs, intervalMs: intervalMs)
        }
        let remainingMs = candleCloseMs - nowMs
        guard remainingMs > 0 else { return nil }
        let remaining = Int(remainingMs / 1000.0)

        // Format based on the actual remaining time, not the selected interval.
        // - >= 1 day left  -> "DD:HH"
        // - < 1 hour left  -> "MM:SS"
        // - otherwise      -> "HH:MM:SS"
        if remaining >= 86_400 {
            let days = remaining / 86_400
            let hours = (remaining % 86_400) / 3600
            return String(format: "%02dD:%02dH", days, hours)
        } else if remaining < 3600 {
            return String(format: "%02d:%02d", remaining / 60, remaining % 60)
        } else {
            return String(format: "%02d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60)
        }
    }

    /// First day of the calendar month following `openMs` (UTC), preserving the open's time-of-day.
    /// Adding a calendar month handles 28-31 day months and works for both UTC- and UTC+8-aligned
    /// monthly opens (e.g. "1st 00:00 UTC" or "last-day 16:00 UTC").
    private func nextMonthCloseMs(fromOpenMs openMs: Double) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? cal.timeZone
        let openDate = Date(timeIntervalSince1970: openMs / 1000.0)
        if let next = cal.date(byAdding: .month, value: 1, to: openDate) {
            return next.timeIntervalSince1970 * 1000.0
        }
        return openMs + 30 * 86_400_000
    }

    /// Fallback close time when no candle open is available to anchor on. Weekly intervals use the
    /// configured `weekStartDay` (0=Sunday … 6=Saturday); other intervals fall back to epoch-aligned
    /// period boundaries.
    private func fallbackCloseMs(nowMs: Double, intervalMs: Double) -> Double {
        let dayMs: Double = 86_400_000
        let weekMs: Double = 7 * dayMs
        if intervalMs == weekMs {
            let daysSinceEpoch = floor(nowMs / dayMs)
            // Unix epoch (1970-01-01) was a Thursday → weekday index 4 with Sunday=0.
            let weekdayNow = (Int(daysSinceEpoch) + 4) % 7
            let weekStart = ((weekdayNow - configManager.weekStartDay) % 7 + 7) % 7
            let weekStartMs = (daysSinceEpoch - Double(weekStart)) * dayMs
            return weekStartMs + weekMs
        }
        return floor(nowMs / intervalMs) * intervalMs + intervalMs
    }

    /// Draws the remaining time until the current candle closes.
    /// Now handled inside drawClosePriceRight as a combined pill.
    /// This method is kept for the case when drawClosePriceCenter is shown instead.
    func drawCandleCountdown(_ context: CGContext) {
        // When the right-side pill is visible, countdown is drawn inside it.
        // Only draw standalone countdown when the center pill is shown.
        guard let lastModel = configManager.modelArray.last else { return }
        let offset = CGFloat(visibleRange.upperBound) * configManager.itemWidth - contentOffset.x
        let animatedClose = displayedClosePrice.isNaN ? lastModel.close : displayedClosePrice
        let valueWidth = mainDraw.textWidth(title: configManager.precision(animatedClose, configManager.price), font: configManager.createFont(configManager.rightTextFontSize))
        let showCenter = offset > allWidth - valueWidth - configManager.itemWidth
        guard showCenter else { return } // Right pill already has countdown

        guard let countdownTitle = candleCountdownString() else { return }

        let font = configManager.createFont(configManager.rightTextFontSize)
        let countdownWidth = mainDraw.textWidth(title: countdownTitle, font: font)
        let countdownHeight = mainDraw.textHeight(font: font)

        let y = yFromValue(animatedClose)
        let countdownY = y + countdownHeight / 2 + 2
        let countdownX = allWidth - countdownWidth

        let maxY = mainBaseY + mainHeight + countdownHeight
        guard countdownY + countdownHeight <= maxY + 10 else { return }

        let bgRect = CGRect(x: countdownX, y: countdownY, width: countdownWidth, height: countdownHeight)
        context.setFillColor(configManager.closePriceRightBackgroundColor.cgColor)
        context.fill(bgRect)
        mainDraw.drawText(title: countdownTitle, point: CGPoint(x: countdownX, y: countdownY), color: configManager.closePriceRightSeparatorColor, font: font, context: context, configManager: configManager)
    }

    func drawSelectedLine(_ context: CGContext) {
        guard visibleRange.contains(selectedIndex) else {
            selectedPricePillRect = .zero
            selectedPriceValue = .nan
            return
        }
        let candleClose = visibleModelArray[selectedIndex - visibleRange.lowerBound].close
        let x = (CGFloat(selectedIndex) + 0.5) * configManager.itemWidth - contentOffset.x
        // Allow the crosshair Y to follow the finger, but clamp it to the main chart area
        // so the right-side "price" label remains meaningful.
        let mainTop = mainBaseY
        let mainBottom = mainBaseY + mainHeight
        let y: CGFloat
        if selectedY.isFinite {
            y = max(mainTop, min(mainBottom, selectedY))
        } else {
            y = yFromValue(candleClose)
        }
        let value = valueFromY(y)
        selectedPriceValue = value

        // --- Crosshair lines (thin, dashed) ---
        context.saveGState()
        context.setStrokeColor(configManager.candleTextColor.cgColor)
        context.setLineWidth(max(0.5, configManager.lineWidth / 2))
        context.setLineDash(phase: 0, lengths: [3, 3])
        // Horizontal line across the full width at the crosshair Y.
        context.move(to: CGPoint(x: 0, y: y))
        context.addLine(to: CGPoint(x: allWidth, y: y))
        // Vertical line through the main + sub chart areas at the selected candle.
        context.move(to: CGPoint(x: x, y: mainBaseY))
        context.addLine(to: CGPoint(x: x, y: childAreaBottom))
        context.strokePath()
        context.restoreGState()

        // --- Selected point dot (small, ~25% of the original size) ---
        let dotOuter = max(2.5, configManager.candleWidth * 0.25)
        let dotInner = dotOuter * 0.6
        context.addArc(center: CGPoint(x: x, y: y), radius: dotOuter, startAngle: 0, endAngle: CGFloat(Double.pi * 2), clockwise: true)
        context.setFillColor(configManager.selectedPointContainerColor.cgColor)
        context.fillPath()
        context.addArc(center: CGPoint(x: x, y: y), radius: dotInner, startAngle: 0, endAngle: CGFloat(Double.pi * 2), clockwise: true)
        context.setFillColor(configManager.selectedPointContentColor.cgColor)
        context.fillPath()

        // --- Hover price pill: [ + ] | price (top) + change % (below) ---
        // The change % is the crosshair price relative to the latest live price, so it updates
        // as the finger moves (both vertically and across candles).
        let priceTitle = configManager.precision(value, configManager.price)
        let liveClose = configManager.modelArray.last?.close ?? 0
        let changePct: CGFloat = liveClose != 0 ? (value - liveClose) / liveClose * 100 : 0
        let changeTitle = String(format: "%@%@%%", changePct >= 0 ? "+" : "", configManager.precision(changePct, 2))

        let font = configManager.createFont(max(8, configManager.candleTextFontSize * 0.85))
        let priceWidth = mainDraw.textWidth(title: priceTitle, font: font)
        let changeWidth = mainDraw.textWidth(title: changeTitle, font: font)
        let textHeight = mainDraw.textHeight(font: font)

        let innerPadV: CGFloat = 3
        let lineGap: CGFloat = 1
        let textPaddingH: CGFloat = 6
        let contentTextWidth = max(priceWidth, changeWidth)
        let pillHeight = textHeight * 2 + lineGap + innerPadV * 2

        let showPlus = configManager.showPlusIcon
        // Icon area hugs the (small) circle with minimal padding instead of being a full square.
        let circleRadius: CGFloat = showPlus ? (pillHeight - 6) / 2 * 0.5 : 0
        let iconLeftPad: CGFloat = 5
        let iconRightPad: CGFloat = 4
        let iconAreaWidth: CGFloat = showPlus ? (iconLeftPad + circleRadius * 2 + iconRightPad) : 0
        let dividerWidth: CGFloat = showPlus ? (1 / UIScreen.main.scale) : 0
        let pillWidth = iconAreaWidth + dividerWidth + contentTextWidth + textPaddingH * 2

        let rightEdge = allWidth
        let marginY: CGFloat = 2
        let pillMinY = max(marginY, min(bounds.size.height - marginY - pillHeight, y - pillHeight / 2))
        let pillRect = CGRect(x: rightEdge - pillWidth, y: pillMinY, width: pillWidth, height: pillHeight)
        selectedPricePillRect = pillRect

        context.saveGState()

        // White pill background + subtle border.
        let radius = pillHeight / 2
        let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: radius)
        context.setFillColor(UIColor.white.cgColor)
        context.addPath(pillPath.cgPath)
        context.fillPath()
        context.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
        context.setLineWidth(1 / UIScreen.main.scale)
        context.addPath(pillPath.cgPath)
        context.strokePath()

        let dividerX = pillRect.minX + iconAreaWidth
        if showPlus {
            // "+" button: black circle with a white border ring + white plus glyph.
            let iconCenter = CGPoint(x: pillRect.minX + iconLeftPad + circleRadius, y: pillRect.midY)
            context.addArc(center: iconCenter, radius: circleRadius, startAngle: 0, endAngle: CGFloat(Double.pi * 2), clockwise: true)
            context.setFillColor(UIColor.black.cgColor)
            context.fillPath()
            // White border ring around the black circle.
            context.addArc(center: iconCenter, radius: circleRadius, startAngle: 0, endAngle: CGFloat(Double.pi * 2), clockwise: true)
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(max(1.5, circleRadius * 0.16))
            context.strokePath()

            let plusStroke: CGFloat = max(1.2, circleRadius * 0.22)
            let plusLen: CGFloat = circleRadius
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(plusStroke)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: iconCenter.x - plusLen / 2, y: iconCenter.y))
            context.addLine(to: CGPoint(x: iconCenter.x + plusLen / 2, y: iconCenter.y))
            context.move(to: CGPoint(x: iconCenter.x, y: iconCenter.y - plusLen / 2))
            context.addLine(to: CGPoint(x: iconCenter.x, y: iconCenter.y + plusLen / 2))
            context.strokePath()

            // Vertical divider between the icon and the text.
            context.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
            context.setLineWidth(max(1 / UIScreen.main.scale, dividerWidth))
            context.move(to: CGPoint(x: dividerX, y: pillRect.minY + 6))
            context.addLine(to: CGPoint(x: dividerX, y: pillRect.maxY - 6))
            context.strokePath()
        }

        // Price (top, black) + change % (below, colored), left-aligned after the divider.
        let textX = (showPlus ? dividerX : pillRect.minX) + textPaddingH
        let priceY = pillRect.minY + innerPadV
        let changeY = priceY + textHeight + lineGap
        mainDraw.drawText(title: priceTitle, point: CGPoint(x: textX, y: priceY), color: UIColor.black, font: font, context: context, configManager: configManager)
        mainDraw.drawText(title: changeTitle, point: CGPoint(x: textX, y: changeY), color: UIColor.black, font: font, context: context, configManager: configManager)

        context.restoreGState()

    }

    func drawSelectedBoard(_ context: CGContext) {
        guard visibleRange.contains(selectedIndex) else {
            return
        }
        guard !configManager.isMinute else {
            return
        }
        let itemList = visibleModelArray[selectedIndex - visibleRange.lowerBound].selectedItemList

        // "topLayer" mode: the native library no longer draws a hover panel/strip.
        // Instead maybeEmitCrosshair() forwards the selected candle to the app via
        // onCrosshairChange, and the app renders the OHLC readout itself.
        if configManager.hoverInfoMode == "topLayer" {
            return
        }

        let font = configManager.createFont(configManager.panelTextFontSize)
        let color = configManager.candleTextColor
        let offset = CGFloat(selectedIndex) * configManager.itemWidth - contentOffset.x
        let halfWidth = allWidth / 2
        let leftAlign = offset > halfWidth
        let margin: CGFloat = 5
        let padding: CGFloat = 7
        let lineSpace: CGFloat = 8
        let y = mainBaseY - textHeight + configManager.lineWidth
        var textY = y + padding
        var width = configManager.panelMinWidth
        for item in itemList {
            let title = item["title"] as? String ?? ""
            let detail = item["detail"] as? String ?? ""
            let text = String(format: "%@%@", title, detail)
            let textWidth = mainDraw.textWidth(title: text, font: font)
            let detailHeight = mainDraw.textHeight(font: font)
            width = max(width, textWidth + 20)
            textY += detailHeight
            textY += lineSpace
        }
        // Keep the hover info panel clear of the right-side y-axis labels.
        let axisFont = configManager.createFont(configManager.candleTextFontSize)
        let maxLabel = configManager.precision(mainMinMaxRange.upperBound, configManager.price)
        let minLabel = configManager.precision(mainMinMaxRange.lowerBound, configManager.price)
        let axisLabelWidth = max(
            mainDraw.textWidth(title: maxLabel, font: axisFont),
            mainDraw.textWidth(title: minLabel, font: axisFont)
        )
        let axisInset: CGFloat = axisLabelWidth + 10

        var x = leftAlign ? margin : max(margin, allWidth - width - margin - axisInset)

        // Also keep the hover info panel clear of the hover price pill (+ icon) on the right.
        // drawSelectedLine() runs before drawSelectedBoard(), so `selectedPricePillRect` is already updated.
        let pillGap: CGFloat = 8
        if !selectedPricePillRect.isEmpty {
            x = min(x, max(margin, selectedPricePillRect.minX - pillGap - width))
        }
        context.setFillColor(configManager.panelBackgroundColor.cgColor)
        context.setLineWidth(configManager.lineWidth / 2.0)
        context.setStrokeColor(configManager.panelBorderColor.cgColor)
        let rect = CGRect.init(x: x, y: y, width: width, height: textY - lineSpace + padding - y)
        let bezierPath  = UIBezierPath.init(roundedRect: rect, cornerRadius: 5)
        context.addPath(bezierPath.cgPath)
        context.fillPath()
        context.addPath(bezierPath.cgPath)
        context.strokePath()
        textY = y + padding
        for item in itemList {
            let title = item["title"] as? String ?? ""
            let detail = item["detail"] as? String ?? ""
            let detailColor = item["color"] as? UIColor ?? color
            mainDraw.drawText(title: title, point: CGPoint.init(x: x + padding, y: textY), color: color, font: font, context: context, configManager: configManager)
            let detailWidth = mainDraw.textWidth(title: detail, font: font)
            let detailHeight = mainDraw.textHeight(font: font)
            mainDraw.drawText(title: detail, point: CGPoint.init(x: x + width - padding - detailWidth, y: textY), color: detailColor, font: font, context: context, configManager: configManager)
            textY += detailHeight
            textY += lineSpace
        }
    }

    /**
     * Abstract-on-chart "topLayer" mode: the selected candle's info items flow
     * left-to-right in a full-width strip pinned to the top of the chart,
     * wrapping onto extra rows as needed (instead of the floating panel).
     */
    func drawTopLayerAbstract(_ context: CGContext, itemList: [[String: Any]]) {
        if itemList.isEmpty {
            return
        }
        let font = configManager.createFont(configManager.panelTextFontSize)
        let padH: CGFloat = 10
        let padV: CGFloat = 6
        let itemGap: CGFloat = 12
        let titleGap: CGFloat = 4
        let rowGap: CGFloat = 4
        let lineH = mainDraw.textHeight(font: font)
        let maxX = allWidth - padH

        // Measure pass: how many rows does the flow layout need?
        var rows = 1
        var x: CGFloat = padH
        for item in itemList {
            let title = item["title"] as? String ?? ""
            let detail = item["detail"] as? String ?? ""
            let w = mainDraw.textWidth(title: title, font: font) + titleGap + mainDraw.textWidth(title: detail, font: font)
            if x + w > maxX, x > padH {
                rows += 1
                x = padH
            }
            x += w + itemGap
        }
        let stripHeight = padV * 2 + CGFloat(rows) * lineH + CGFloat(rows - 1) * rowGap

        // Full-width strip background + bottom hairline, pinned to the top.
        context.setFillColor(configManager.panelBackgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: allWidth, height: stripHeight))
        context.setStrokeColor(configManager.panelBorderColor.cgColor)
        context.setLineWidth(configManager.lineWidth / 2.0)
        context.move(to: CGPoint(x: 0, y: stripHeight))
        context.addLine(to: CGPoint(x: allWidth, y: stripHeight))
        context.strokePath()

        // Draw pass.
        x = padH
        var y: CGFloat = padV
        for item in itemList {
            let title = item["title"] as? String ?? ""
            let detail = item["detail"] as? String ?? ""
            let titleWidth = mainDraw.textWidth(title: title, font: font)
            let detailWidth = mainDraw.textWidth(title: detail, font: font)
            let w = titleWidth + titleGap + detailWidth
            if x + w > maxX, x > padH {
                x = padH
                y += lineH + rowGap
            }
            mainDraw.drawText(title: title, point: CGPoint(x: x, y: y), color: configManager.textColor, font: font, context: context, configManager: configManager)
            let detailColor = item["color"] as? UIColor ?? configManager.candleTextColor
            mainDraw.drawText(title: detail, point: CGPoint(x: x + titleWidth + titleGap, y: y), color: detailColor, font: font, context: context, configManager: configManager)
            x += w + itemGap
        }
    }

    func drawSelectedTime(_ context: CGContext) {
        guard visibleRange.contains(selectedIndex) else {
            return
        }
        let selectedModel = visibleModelArray[selectedIndex - visibleRange.lowerBound]
        let value = configManager.formatBottomDate(epochMs: selectedModel.id)
        let x = (CGFloat(selectedIndex) + 0.5) * configManager.itemWidth - contentOffset.x
        let font = configManager.createFont(configManager.candleTextFontSize)
        let title = value
        let width = mainDraw.textWidth(title: title, font: font)
        let textHeight = mainDraw.textHeight(font: font)

        // Bottom active date (hover mode): pill background (no border), compact height to match x-axis labels.
        let paddingH: CGFloat = 6
        let paddingV: CGFloat = 3
        let cornerRadius: CGFloat = 5

        let rowCenterY = childAreaBottom + configManager.paddingBottom / 2
        let pillHeight = textHeight + paddingV * 2
        let rectY = rowCenterY - pillHeight / 2
        let rect = CGRect(x: x - width / 2 - paddingH, y: rectY, width: width + paddingH * 2, height: pillHeight)

        context.saveGState()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        // Match the right-side hover price pill background.
        context.setFillColor(UIColor.white.cgColor)
        context.addPath(path.cgPath)
        context.drawPath(using: .fill)
        context.restoreGState()

        // Match the pill text color.
        mainDraw.drawText(
            title: title,
            point: CGPoint(x: x - width / 2.0, y: rectY + paddingV),
            color: .black,
            font: font,
            context: context,
            configManager: configManager
        )
    }
    
    func valuePointFromViewPoint(_ point: CGPoint) -> CGPoint {
        return CGPoint.init(x: valueFromX(point.x), y: valueFromY(point.y))
    }

    func viewPointFromValuePoint(_ point: CGPoint) -> CGPoint {
        let x = xFromValue(point.x)
        let y = yFromValue(point.y)
        // Guard against NaN/infinity values that would crash Core Graphics
        guard x.isFinite && y.isFinite else {
            return CGPoint.zero
        }
        return CGPoint.init(x: x, y: y)
    }
    

}

extension HTKLineView: UIScrollViewDelegate {

    // Use associated storage so we don't change the public API surface.
    private struct AssociatedKeys {
        static var onEndReachedFlag = "ht_onEndReachedFlag"
    }

    private var hasFiredOnEndReached: Bool {
        get { return objc_getAssociatedObject(self, &AssociatedKeys.onEndReachedFlag) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &AssociatedKeys.onEndReachedFlag, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // If there is no data yet, don't compute indices against an empty array.
        // Otherwise `count - 1` becomes -1, and `visibleRange` can become negative
        // which later crashes when slicing `modelArray[visibleRange]`.
        let count = configManager.modelArray.count
        guard count > 0 else {
            visibleRange = 0...0
            self.setNeedsDisplay()
            return
        }

        let contentOffsetX = scrollView.contentOffset.x
        var visibleStartIndex = Int(floor(contentOffsetX / configManager.itemWidth))
        var visibleEndIndex = Int(ceil((contentOffsetX + scrollView.bounds.size.width) / configManager.itemWidth))
        visibleStartIndex = min(max(0, visibleStartIndex), count - 1)
        visibleEndIndex = min(max(0, visibleEndIndex), count - 1)
        visibleRange = visibleStartIndex...visibleEndIndex
        self.setNeedsDisplay()

        // Keep the loading spinner pinned to the left edge as user scrolls.
        if isShowingLoadingSpinner {
            updateLoadingSpinnerPosition()
        }

        // When the very first candle becomes visible, consider that "reached the left edge".
        // Using the computed index is more reliable than a strict contentOffset == 0 check
        // which can miss due to float rounding and padding.
        if visibleStartIndex == 0 {
            if !hasFiredOnEndReached {
                hasFiredOnEndReached = true
                // Mark that the next modelArray update is the result of a "load older
                // candles" flow so we can keep the user's visible range anchored when
                // new data is prepended on the left.
                configManager.loadingMoreFromLeft = true
                showLoadingIndicator()
                containerView?.onEndReached?([:])
            }
        } else {
            // User has scrolled away from the start, so allow the event to fire again
            // next time they come back (after data has been prepended).
            hasFiredOnEndReached = false
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // If hover mode is active (either finger-down or locked), don't clear selection.
        // This prevents the selector from disappearing when the scroll view pan begins.
        if isHoverModeLocked || longPressGesture.state == .began || longPressGesture.state == .changed {
            return
        }
        selectedIndex = -1
        selectedY = .nan
        self.setNeedsDisplay()

        // Disable the parent vertical scroll view while we are being dragged horizontally.
        if !didDisableParentForDrag {
            let parent = parentScrollViewDuringLongPress ?? nearestParentScrollView()
            parentScrollViewDuringLongPress = parent
            if let parent = parent {
                parentWasScrollEnabledBeforeDrag = parent.isScrollEnabled
                parent.isScrollEnabled = false
                didDisableParentForDrag = true
            }
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            restoreParentScrollAfterDrag()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        restoreParentScrollAfterDrag()
    }

    private func restoreParentScrollAfterDrag() {
        guard didDisableParentForDrag else { return }
        didDisableParentForDrag = false
        if let parent = parentScrollViewDuringLongPress {
            parent.isScrollEnabled = parentWasScrollEnabledBeforeDrag
        }
    }

    @objc
    func longPressSelector(_ gesture: UILongPressGestureRecognizer) {
        // Hover info overlay disabled from JS: ignore long-press so normal scrolling is preserved.
        guard configManager.hoverInfoEnabled else {
            return
        }
        // Use location in the superview (or window) to get coordinates relative to the visible
        // viewport, then manually add contentOffset to convert to content coordinates.
        // NOTE: In a UIScrollView, `location(in: self)` returns coordinates in the scroll view's
        // bounds coordinate system, which already incorporates contentOffset (bounds.origin = contentOffset).
        // Using the superview gives us pure view-space coordinates that we then convert ourselves.
        let locationInSuperview = gesture.location(in: superview ?? self)
        let viewOriginInSuperview = superview != nil ? frame.origin : CGPoint.zero
        let viewX = locationInSuperview.x - viewOriginInSuperview.x
        let viewY = locationInSuperview.y - viewOriginInSuperview.y
        
        let itemWidth = configManager.itemWidth
        // Convert view X to content X by adding the scroll offset
        let xInContent = viewX + contentOffset.x

        if itemWidth > 0, !configManager.modelArray.isEmpty {
            // X snaps to candle index; Y follows the finger (clamped during draw).
            let index = Int(floor(xInContent / itemWidth))
            let newIndex = max(0, min(index, configManager.modelArray.count - 1))
            // Fire a light haptic whenever the snapped candle changes (not on finger-up).
            if configManager.hapticOnSelection,
               newIndex != selectedIndex,
               gesture.state == .began || gesture.state == .changed {
                selectionFeedbackGenerator.impactOccurred()
                selectionFeedbackGenerator.prepare()
            }
            selectedIndex = newIndex
            selectedY = viewY
        } else {
            selectedIndex = -1
            selectedY = .nan
        }

        // Update continuously while holding/dragging.
        switch gesture.state {
        case .began:
            // Enter "locked" hover mode: it stays active after finger-up until user taps to dismiss.
            enterHoverModeIfNeeded()
            setNeedsDisplay()
        case .changed:
            // Ensure hover mode is entered even if iOS transitions directly to .changed in some edge cases.
            enterHoverModeIfNeeded()
            setNeedsDisplay()
        case .ended, .cancelled, .failed:
            // Keep hover mode visible after finger-up so the user can tap the price pill icon.
            setNeedsDisplay()
        default:
            break
        }
    }

    @objc
    func tapSelector(_ gesture: UITapGestureRecognizer) {
        // Use superview to get view-relative coordinates (not affected by scroll offset).
        // selectedPricePillRect is in view coordinates, so we need view-relative tap location.
        let locationInSuperview = gesture.location(in: superview ?? self)
        let viewOriginInSuperview = superview != nil ? frame.origin : CGPoint.zero
        let viewLocation = CGPoint(
            x: locationInSuperview.x - viewOriginInSuperview.x,
            y: locationInSuperview.y - viewOriginInSuperview.y
        )

        // If the close price center pill (shown when scrolled left) is tapped, scroll to present.
        if !closePriceCenterPillRect.isEmpty,
           closePriceCenterPillRect.contains(viewLocation) {
            scrollToEndIfPossible(animated: true)
            return
        }

        // If a hover price pill is visible and tapped, trigger onNewOrder(price) and keep the selector.
        if visibleRange.contains(selectedIndex),
           !selectedPricePillRect.isEmpty,
           selectedPricePillRect.contains(viewLocation),
           selectedPriceValue.isFinite {
            containerView?.onNewOrder?([
                "price": Double(selectedPriceValue)
            ])
            return
        }

        // Otherwise, clear selection.
        selectedIndex = -1
        selectedY = .nan
        selectedPricePillRect = .zero
        selectedPriceValue = .nan
        exitHoverModeIfNeeded()
        self.setNeedsDisplay()
    }

    @objc
    func pinchSelector(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            if gesture.numberOfTouches >= 2 {
                let p0 = gesture.location(ofTouch: 0, in: self)
                let p1 = gesture.location(ofTouch: 1, in: self)
                pinchStartVerticalSpan = abs(p0.y - p1.y)
                pinchStartYAxisZoomFactor = yAxisZoomFactor
            }
        case .changed:
            scale += (gesture.scale - 1) / 10

            // Vertical pinch: use the change in vertical finger span to adjust Y-axis zoom.
            if gesture.numberOfTouches >= 2 && pinchStartVerticalSpan > 10 {
                let p0 = gesture.location(ofTouch: 0, in: self)
                let p1 = gesture.location(ofTouch: 1, in: self)
                let currentSpanY = abs(p0.y - p1.y)
                if currentSpanY > 0 {
                    let ratio = pinchStartVerticalSpan / currentSpanY
                    yAxisZoomFactor = max(1.0, min(5.0, pinchStartYAxisZoomFactor * ratio))
                }
            }
        case .ended, .cancelled, .failed:
            pinchStartVerticalSpan = .nan
        default:
            break
        }
        scale = max(0.3, min(scale, 3))

        let width = bounds.size.width
        let halfWidth = width / 2
        let offsetScale = (contentOffset.x + halfWidth) / (contentSize.width - configManager.paddingRight)

        reloadContentSize()
        let contentOffsetX = max(0, min((contentSize.width - configManager.paddingRight) * offsetScale - halfWidth, contentSize.width - width))
        reloadContentOffset(contentOffsetX)
        scrollViewDidScroll(self)
    }

}
