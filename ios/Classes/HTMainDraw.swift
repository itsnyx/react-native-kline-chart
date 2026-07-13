//
//  HTMainDraw.swift
//  HTKLineView
//
//  Created by hublot on 2020/3/17.
//  Copyright © 2020 hublot. All rights reserved.
//

import UIKit

class HTMainDraw: NSObject, HTKLineDrawProtocol {

    func minMaxRange(_ visibleModelArray: [HTKLineModel], _ configManager: HTKLineConfigManager) -> Range<CGFloat> {
        var maxValue = CGFloat.leastNormalMagnitude
        var minValue = CGFloat.greatestFiniteMagnitude

        for model in visibleModelArray {
            var valueList = [model.high, model.low]
            switch configManager.mainType {
            case .ma:
                valueList.append(contentsOf: model.maList.map({ (item) -> CGFloat in
                    return item.value
                }))
                break
            case .boll:
                valueList.append(contentsOf: [model.bollMb, model.bollUp, model.bollDn])
                break
            default:
                break
            }

            // Phase 8-B: keep overlay values in the visible range. Only finite
            // values are added so a NaN never poisons the min/max.
            let overlays = configManager.mainOverlays
            if !overlays.isEmpty {
                if overlays.contains("ma") {
                    valueList.append(contentsOf: model.maList.map({ $0.value }).filter({ $0.isFinite }))
                }
                if overlays.contains("boll") {
                    valueList.append(contentsOf: [model.bollUp, model.bollMb, model.bollDn].filter({ $0.isFinite }))
                }
                if overlays.contains("ichi") {
                    valueList.append(contentsOf: [model.ichiTenkan, model.ichiKijun, model.ichiSpanA, model.ichiSpanB, model.ichiChikou].filter({ $0.isFinite }))
                }
                if overlays.contains("ema") {
                    valueList.append(contentsOf: model.emaList.map({ $0.value }).filter({ $0.isFinite }))
                }
                if overlays.contains("avl"), model.avl.isFinite {
                    valueList.append(model.avl)
                }
                if overlays.contains("vwap"), model.vwap.isFinite {
                    valueList.append(model.vwap)
                }
                if overlays.contains("super"), model.superTrend.isFinite {
                    valueList.append(model.superTrend)
                }
                if overlays.contains("sar"), model.sar.isFinite {
                    valueList.append(model.sar)
                }
                if overlays.contains("resist") {
                    valueList.append(contentsOf: [model.resistR, model.resistS].filter({ $0.isFinite }))
                }
            }

            maxValue = max(maxValue, valueList.max() ?? 0)
            minValue = min(minValue, valueList.min() ?? 0)
        }
        return Range<CGFloat>.init(uncheckedBounds: (lower: minValue, upper: maxValue))
    }

    func drawCandle(_ model: HTKLineModel, _ index: Int, _ maxValue: CGFloat, _ minValue: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        let color = model.increment ? configManager.increaseColor : configManager.decreaseColor
        let findValue: (Bool) -> CGFloat = { (isHighValue: Bool) in
            var findCloseValue = model.increment
            if (!isHighValue) {
                findCloseValue = !findCloseValue
            }
            return findCloseValue ? model.close : model.open
        }
        if (configManager.isMinute) {

        } else {
            _ = findValue // solid path below draws body + wick directly
            let style = configManager.candleStyle
            let itemWidth = configManager.itemWidth
            let candleWidth = configManager.candleWidth
            let denom = (maxValue - minValue)
            let scale = denom == 0 ? 1 : denom / height
            let centerX = CGFloat(index) * itemWidth + itemWidth / 2
            let yFor: (CGFloat) -> CGFloat = { v in baseY + (maxValue - v) / scale }
            let openY = yFor(model.open)
            let closeY = yFor(model.close)
            let highY = yFor(model.high)
            let lowY = yFor(model.low)
            var bodyTop = min(openY, closeY)
            var bodyBottom = max(openY, closeY)
            if bodyBottom - bodyTop < 1 {
                bodyBottom = bodyTop + 1
            }

            if style == "ohlc" {
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(configManager.candleLineWidth)
                context.beginPath()
                context.move(to: CGPoint(x: centerX, y: highY))
                context.addLine(to: CGPoint(x: centerX, y: lowY))
                context.move(to: CGPoint(x: centerX - candleWidth / 2, y: openY))
                context.addLine(to: CGPoint(x: centerX, y: openY))
                context.move(to: CGPoint(x: centerX, y: closeY))
                context.addLine(to: CGPoint(x: centerX + candleWidth / 2, y: closeY))
                context.strokePath()
            } else {
                let hollow: Bool
                switch style {
                case "allHollow": hollow = true
                case "upHollow": hollow = model.increment
                case "downHollow": hollow = !model.increment
                default: hollow = false
                }
                // Wick (thin filled bar from high to low).
                drawCandle(high: model.high, low: model.low, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, width: configManager.candleLineWidth, color: color, verticalAlignBottom: false, context: context, configManager: configManager)
                let bodyRect = CGRect(x: centerX - candleWidth / 2, y: bodyTop, width: candleWidth, height: bodyBottom - bodyTop)
                if hollow {
                    context.setStrokeColor(color.cgColor)
                    context.setLineWidth(configManager.candleLineWidth)
                    context.stroke(bodyRect)
                } else {
                    context.setFillColor(color.cgColor)
                    context.fill(bodyRect)
                }
            }
        }
    }

    func drawGradient(_ visibleModelArray: [HTKLineModel], _ maxValue: CGFloat, _ minValue: CGFloat, _ baseX: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        let colorList = configManager.packGradientColorList(configManager.minuteGradientColorList)
        let locationList = configManager.minuteGradientLocationList
        if let gradient = CGGradient.init(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: colorList, locations: locationList, count: locationList.count) {
            var bezierPath = UIBezierPath.init()
            for (i, model) in visibleModelArray.enumerated() {
                let lastIndex = i == 0 ? i : i - 1
                let lastModel = visibleModelArray[lastIndex]
                bezierPath = createLinePath(value: model.close, lastValue: lastModel.close, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: i, lastIndex: lastIndex, isBezier: true, existPath: bezierPath, context: context, configManager: configManager)
            }
            bezierPath.addLine(to: CGPoint.init(x: bezierPath.currentPoint.x, y: baseY + height))
            bezierPath.addLine(to: CGPoint.init(x: configManager.itemWidth / 2, y: baseY + height))
            bezierPath.close()
            context.addPath(bezierPath.cgPath)
            context.clip()
            context.drawLinearGradient(gradient, start: CGPoint.init(x: 0, y: baseY), end: CGPoint.init(x: 0, y: height + baseY), options: .drawsBeforeStartLocation)
            context.resetClip()
        }
    }

    func drawLine(_ model: HTKLineModel, _ lastModel: HTKLineModel, _ maxValue: CGFloat, _ minValue: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ index: Int, _ lastIndex: Int, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        if (configManager.isMinute) {
            drawLine(value: model.close, lastValue: lastModel.close, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: configManager.minuteLineColor, isBezier: true, context: context, configManager: configManager)
        } else {
            switch configManager.mainType {
            case .none:
                break
            case .ma:
                guard !configManager.maList.isEmpty,
                      !model.maList.isEmpty,
                      !lastModel.maList.isEmpty else {
                    return
                }
                for (i, itemModel) in configManager.maList.enumerated() {
                    guard i >= 0,
                          i < model.maList.count,
                          i < lastModel.maList.count else {
                        continue
                    }
                    // Native N6: explicit per-line color wins; the palette slot
                    // (safely wrapped) stays as the fallback for old JS bundles.
                    let color = itemModel.color ?? overlayColor(itemModel.index, configManager)
                    drawLine(value: model.maList[i].value, lastValue: lastModel.maList[i].value, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: color, isBezier: false, context: context, configManager: configManager)
                }
            case .boll:
                let itemList = [
                    ["value": model.bollMb, "lastValue": lastModel.bollMb, "color": configManager.indicatorColor("boll", 0, overlayColor(0, configManager))],
                    ["value": model.bollUp, "lastValue": lastModel.bollUp, "color": configManager.indicatorColor("boll", 1, overlayColor(1, configManager))],
                    ["value": model.bollDn, "lastValue": lastModel.bollDn, "color": configManager.indicatorColor("boll", 2, overlayColor(2, configManager))],
                ]
                for item in itemList {
                    drawLine(value: item["value"] as? CGFloat ?? 0, lastValue: item["lastValue"] as? CGFloat ?? 0, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: item["color"] as? UIColor ?? UIColor.orange, isBezier: false, context: context, configManager: configManager)
                }
            }

            // Phase 8-B: draw additional selected overlays on top of MA/BOLL.
            drawMainOverlays(model, lastModel, maxValue, minValue, baseY, height, index, lastIndex, context, configManager)
        }
    }

    /** Color from the shared palette, wrapping the index; gray if palette empty. */
    private func overlayColor(_ i: Int, _ configManager: HTKLineConfigManager) -> UIColor {
        let list = configManager.targetColorList
        if list.isEmpty {
            return UIColor.gray
        }
        let idx = ((i % list.count) + list.count) % list.count
        return list[idx]
    }

    /**
     * Draws the Phase 8-B overlays. Every value is checked for finiteness so a
     * candle missing an overlay value (warm-up period, absent field) is skipped
     * rather than drawn at a bogus coordinate.
     */
    func drawMainOverlays(_ model: HTKLineModel, _ lastModel: HTKLineModel, _ maxValue: CGFloat, _ minValue: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ index: Int, _ lastIndex: Int, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        let overlays = configManager.mainOverlays
        if overlays.isEmpty {
            return
        }

        // MA / BOLL as overlays so they combine with the primary + others.
        if overlays.contains("ma") {
            let n = min(model.maList.count, lastModel.maList.count)
            if n > 0 {
                for i in 0..<n {
                    let item = model.maList[i]
                    let v = item.value
                    let lv = lastModel.maList[i].value
                    if !v.isFinite || !lv.isFinite { continue }
                    drawLine(value: v, lastValue: lv, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: item.color ?? overlayColor(i, configManager), isBezier: false, context: context, configManager: configManager)
                }
            }
        }
        if overlays.contains("boll") {
            if model.bollMb.isFinite, lastModel.bollMb != 0 {
                drawLine(value: model.bollMb, lastValue: lastModel.bollMb, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: configManager.indicatorColor("boll", 0, overlayColor(0, configManager)), isBezier: false, context: context, configManager: configManager)
            }
            if model.bollUp.isFinite, lastModel.bollUp != 0 {
                drawLine(value: model.bollUp, lastValue: lastModel.bollUp, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: configManager.indicatorColor("boll", 1, overlayColor(1, configManager)), isBezier: false, context: context, configManager: configManager)
            }
            if model.bollDn.isFinite, lastModel.bollDn != 0 {
                drawLine(value: model.bollDn, lastValue: lastModel.bollDn, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: configManager.indicatorColor("boll", 2, overlayColor(2, configManager)), isBezier: false, context: context, configManager: configManager)
            }
        }
        if overlays.contains("ichi") {
            // Cloud fill between Span A / Span B (per adjacent segment).
            if model.ichiSpanA.isFinite, lastModel.ichiSpanA.isFinite, model.ichiSpanB.isFinite, lastModel.ichiSpanB.isFinite {
                let itemWidth = configManager.itemWidth
                let paddingHorizontal = (itemWidth - configManager.lineWidth) / 2.0
                let denom = (maxValue - minValue)
                let scale = denom == 0 ? 1 : denom / height
                let px: (Int) -> CGFloat = { CGFloat($0) * itemWidth + paddingHorizontal }
                let py: (CGFloat) -> CGFloat = { baseY + (maxValue - $0) / scale }
                let bullish = model.ichiSpanA >= model.ichiSpanB
                let base = bullish ? configManager.increaseColor : configManager.decreaseColor
                context.setFillColor(base.withAlphaComponent(0.19).cgColor)
                context.beginPath()
                context.move(to: CGPoint(x: px(lastIndex), y: py(lastModel.ichiSpanA)))
                context.addLine(to: CGPoint(x: px(index), y: py(model.ichiSpanA)))
                context.addLine(to: CGPoint(x: px(index), y: py(model.ichiSpanB)))
                context.addLine(to: CGPoint(x: px(lastIndex), y: py(lastModel.ichiSpanB)))
                context.closePath()
                context.fillPath()
            }
            drawIchiLine(model.ichiTenkan, lastModel.ichiTenkan, configManager.indicatorColor("ichi", 0, overlayColor(0, configManager)), maxValue, minValue, baseY, height, index, lastIndex, context, configManager)
            drawIchiLine(model.ichiKijun, lastModel.ichiKijun, configManager.indicatorColor("ichi", 1, overlayColor(3, configManager)), maxValue, minValue, baseY, height, index, lastIndex, context, configManager)
            drawIchiLine(model.ichiSpanA, lastModel.ichiSpanA, configManager.indicatorColor("ichi", 2, overlayColor(4, configManager)), maxValue, minValue, baseY, height, index, lastIndex, context, configManager)
            drawIchiLine(model.ichiSpanB, lastModel.ichiSpanB, configManager.indicatorColor("ichi", 3, overlayColor(5, configManager)), maxValue, minValue, baseY, height, index, lastIndex, context, configManager)
            drawIchiLine(model.ichiChikou, lastModel.ichiChikou, configManager.indicatorColor("ichi", 4, overlayColor(1, configManager)), maxValue, minValue, baseY, height, index, lastIndex, context, configManager)
        }
        if overlays.contains("ema") {
            let n = min(model.emaList.count, lastModel.emaList.count)
            if n > 0 {
                for i in 0..<n {
                    let item = model.emaList[i]
                    let v = item.value
                    let lv = lastModel.emaList[i].value
                    if !v.isFinite || !lv.isFinite {
                        continue
                    }
                    drawLine(value: v, lastValue: lv, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: item.color ?? overlayColor(i, configManager), isBezier: false, context: context, configManager: configManager)
                }
            }
        }
        if overlays.contains("avl"), model.avl.isFinite, lastModel.avl.isFinite {
            drawLine(value: model.avl, lastValue: lastModel.avl, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: configManager.indicatorColor("avl", 0, overlayColor(2, configManager)), isBezier: false, context: context, configManager: configManager)
        }
        if overlays.contains("vwap"), model.vwap.isFinite, lastModel.vwap.isFinite {
            drawLine(value: model.vwap, lastValue: lastModel.vwap, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: configManager.indicatorColor("vwap", 0, overlayColor(1, configManager)), isBezier: false, context: context, configManager: configManager)
        }
        if overlays.contains("super"), model.superTrend.isFinite, lastModel.superTrend.isFinite {
            // Two user colors: indicatorColors.super = [upColor, downColor];
            // market direction colors remain the fallback for old JS bundles.
            let superFallback = model.superTrendUp ? configManager.increaseColor : configManager.decreaseColor
            drawLine(value: model.superTrend, lastValue: lastModel.superTrend, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: configManager.indicatorColor("super", model.superTrendUp ? 0 : 1, superFallback), isBezier: false, context: context, configManager: configManager)
        }
        if overlays.contains("sar"), model.sar.isFinite {
            let itemWidth = configManager.itemWidth
            let width = configManager.lineWidth
            let paddingHorizontal = (itemWidth - width) / 2.0
            let denom = (maxValue - minValue)
            let scale = denom == 0 ? 1 : denom / height
            let x = CGFloat(index) * itemWidth + paddingHorizontal
            let y = baseY + (maxValue - model.sar) / scale
            let r: CGFloat = 2.0
            context.setFillColor(configManager.indicatorColor("sar", 0, overlayColor(3, configManager)).cgColor)
            context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        // Support & Resistance: user colors when configured, otherwise the
        // bearish color for resistance / bullish for support (non-finite skips).
        if overlays.contains("resist") {
            if model.resistR.isFinite, lastModel.resistR.isFinite {
                drawLine(value: model.resistR, lastValue: lastModel.resistR, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: configManager.indicatorColor("resist", 0, configManager.decreaseColor), isBezier: false, context: context, configManager: configManager)
            }
            if model.resistS.isFinite, lastModel.resistS.isFinite {
                drawLine(value: model.resistS, lastValue: lastModel.resistS, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: configManager.indicatorColor("resist", 1, configManager.increaseColor), isBezier: false, context: context, configManager: configManager)
            }
        }
    }

    /// Draws one Ichimoku line segment, skipping non-finite endpoints.
    func drawIchiLine(_ value: CGFloat, _ lastValue: CGFloat, _ color: UIColor, _ maxValue: CGFloat, _ minValue: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ index: Int, _ lastIndex: Int, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        if !value.isFinite || !lastValue.isFinite {
            return
        }
        drawLine(value: value, lastValue: lastValue, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: color, isBezier: false, context: context, configManager: configManager)
    }

    /**
     * Header legend as rows (one row per indicator), each a list of colored
     * segments. Rendered stacked vertically (see drawText), capped at 4 lines
     * so many overlapping indicators don't flood the chart.
     */
    func buildLegendRows(_ model: HTKLineModel, _ configManager: HTKLineConfigManager) -> [[(String, UIColor)]] {
        var rows: [[(String, UIColor)]] = []

        // Primary MA / BOLL row.
        switch configManager.mainType {
        case .none:
            break
        case .ma:
            var row: [(String, UIColor)] = []
            for (i, itemModel) in configManager.maList.enumerated() {
                guard i >= 0, i < model.maList.count else {
                    continue
                }
                let item = model.maList[i]
                let title = String(format: "MA%@:%@", item.title, configManager.precision(item.value, configManager.price))
                row.append((title, itemModel.color ?? overlayColor(itemModel.index, configManager)))
            }
            if !row.isEmpty {
                rows.append(row)
            }
        case .boll:
            rows.append([
                (String(format: "BOLL:%@", configManager.precision(model.bollMb, configManager.price)), configManager.indicatorColor("boll", 0, overlayColor(0, configManager))),
                (String(format: "UB:%@", configManager.precision(model.bollUp, configManager.price)), configManager.indicatorColor("boll", 1, overlayColor(1, configManager))),
                (String(format: "LB:%@", configManager.precision(model.bollDn, configManager.price)), configManager.indicatorColor("boll", 2, overlayColor(2, configManager))),
            ])
        }

        // Overlay rows (each indicator on its own line).
        let overlays = configManager.mainOverlays
        if !overlays.isEmpty {
            if overlays.contains("ema") {
                var row: [(String, UIColor)] = []
                for (i, item) in model.emaList.enumerated() {
                    if !item.value.isFinite {
                        continue
                    }
                    let title = String(format: "EMA%@:%@", item.title, configManager.precision(item.value, configManager.price))
                    row.append((title, item.color ?? overlayColor(i, configManager)))
                }
                if !row.isEmpty {
                    rows.append(row)
                }
            }
            if overlays.contains("avl"), model.avl.isFinite {
                rows.append([(String(format: "AVL:%@", configManager.precision(model.avl, configManager.price)), configManager.indicatorColor("avl", 0, overlayColor(2, configManager)))])
            }
            if overlays.contains("vwap"), model.vwap.isFinite {
                rows.append([(String(format: "VWAP:%@", configManager.precision(model.vwap, configManager.price)), configManager.indicatorColor("vwap", 0, overlayColor(1, configManager)))])
            }
            if overlays.contains("super"), model.superTrend.isFinite {
                let superFallback = model.superTrendUp ? configManager.increaseColor : configManager.decreaseColor
                rows.append([(String(format: "SuperTrend:%@", configManager.precision(model.superTrend, configManager.price)), configManager.indicatorColor("super", model.superTrendUp ? 0 : 1, superFallback))])
            }
            if overlays.contains("sar"), model.sar.isFinite {
                rows.append([(String(format: "SAR:%@", configManager.precision(model.sar, configManager.price)), configManager.indicatorColor("sar", 0, overlayColor(3, configManager)))])
            }
            if overlays.contains("resist") {
                var row: [(String, UIColor)] = []
                if model.resistR.isFinite {
                    row.append((String(format: "R:%@", configManager.precision(model.resistR, configManager.price)), configManager.indicatorColor("resist", 0, configManager.decreaseColor)))
                }
                if model.resistS.isFinite {
                    row.append((String(format: "S:%@", configManager.precision(model.resistS, configManager.price)), configManager.indicatorColor("resist", 1, configManager.increaseColor)))
                }
                if !row.isEmpty {
                    rows.append(row)
                }
            }
        }
        return rows
    }

    func drawText(_ model: HTKLineModel, _ baseX: CGFloat, _ baseY: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        if configManager.isMinute {
            return
        }
        let rows = buildLegendRows(model, configManager)
        if rows.isEmpty {
            return
        }
        // Each indicator draws on its own line, stacked vertically; cap the
        // number of lines so many overlapping indicators can't flood the chart.
        let font = configManager.createFont(configManager.headerTextFontSize)
        let maxRows = min(4, rows.count)
        let lineHeight = textHeight(font: font) + 3
        for r in 0..<maxRows {
            var x = baseX
            let y = baseY + CGFloat(r) * lineHeight
            for seg in rows[r] {
                x += drawText(title: seg.0, point: CGPoint(x: x, y: y), color: seg.1, font: font, context: context, configManager: configManager)
                x += 5
            }
        }
    }

    func drawValue(_ maxValue: CGFloat, _ minValue: CGFloat, _ baseX: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        drawValue(maxValue, minValue, baseX, baseY, height, 4, configManager.price, context, configManager)
    }

}
