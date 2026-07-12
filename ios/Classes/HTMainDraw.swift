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
                          i < lastModel.maList.count,
                          itemModel.index >= 0,
                          itemModel.index < configManager.targetColorList.count else {
                        continue
                    }
                    let color = configManager.targetColorList[itemModel.index]
                    drawLine(value: model.maList[i].value, lastValue: lastModel.maList[i].value, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: color, isBezier: false, context: context, configManager: configManager)
                }
            case .boll:
                let itemList = [
                    ["value": model.bollMb, "lastValue": lastModel.bollMb, "color": configManager.targetColorList[0]],
                    ["value": model.bollUp, "lastValue": lastModel.bollUp, "color": configManager.targetColorList[1]],
                    ["value": model.bollDn, "lastValue": lastModel.bollDn, "color": configManager.targetColorList[2]],
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
                    let v = model.maList[i].value
                    let lv = lastModel.maList[i].value
                    if !v.isFinite || !lv.isFinite { continue }
                    drawLine(value: v, lastValue: lv, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: overlayColor(i, configManager), isBezier: false, context: context, configManager: configManager)
                }
            }
        }
        if overlays.contains("boll") {
            if model.bollMb.isFinite, lastModel.bollMb != 0 {
                drawLine(value: model.bollMb, lastValue: lastModel.bollMb, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: overlayColor(0, configManager), isBezier: false, context: context, configManager: configManager)
            }
            if model.bollUp.isFinite, lastModel.bollUp != 0 {
                drawLine(value: model.bollUp, lastValue: lastModel.bollUp, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: overlayColor(1, configManager), isBezier: false, context: context, configManager: configManager)
            }
            if model.bollDn.isFinite, lastModel.bollDn != 0 {
                drawLine(value: model.bollDn, lastValue: lastModel.bollDn, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: overlayColor(2, configManager), isBezier: false, context: context, configManager: configManager)
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
            drawIchiLine(model.ichiTenkan, lastModel.ichiTenkan, overlayColor(0, configManager), maxValue, minValue, baseY, height, index, lastIndex, context, configManager)
            drawIchiLine(model.ichiKijun, lastModel.ichiKijun, overlayColor(3, configManager), maxValue, minValue, baseY, height, index, lastIndex, context, configManager)
            drawIchiLine(model.ichiSpanA, lastModel.ichiSpanA, overlayColor(4, configManager), maxValue, minValue, baseY, height, index, lastIndex, context, configManager)
            drawIchiLine(model.ichiSpanB, lastModel.ichiSpanB, overlayColor(5, configManager), maxValue, minValue, baseY, height, index, lastIndex, context, configManager)
            drawIchiLine(model.ichiChikou, lastModel.ichiChikou, overlayColor(1, configManager), maxValue, minValue, baseY, height, index, lastIndex, context, configManager)
        }
        if overlays.contains("ema") {
            let n = min(model.emaList.count, lastModel.emaList.count)
            if n > 0 {
                for i in 0..<n {
                    let v = model.emaList[i].value
                    let lv = lastModel.emaList[i].value
                    if !v.isFinite || !lv.isFinite {
                        continue
                    }
                    drawLine(value: v, lastValue: lv, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: overlayColor(i, configManager), isBezier: false, context: context, configManager: configManager)
                }
            }
        }
        if overlays.contains("avl"), model.avl.isFinite, lastModel.avl.isFinite {
            drawLine(value: model.avl, lastValue: lastModel.avl, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: overlayColor(2, configManager), isBezier: false, context: context, configManager: configManager)
        }
        if overlays.contains("vwap"), model.vwap.isFinite, lastModel.vwap.isFinite {
            drawLine(value: model.vwap, lastValue: lastModel.vwap, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: overlayColor(1, configManager), isBezier: false, context: context, configManager: configManager)
        }
        if overlays.contains("super"), model.superTrend.isFinite, lastModel.superTrend.isFinite {
            let color = model.superTrendUp ? configManager.increaseColor : configManager.decreaseColor
            drawLine(value: model.superTrend, lastValue: lastModel.superTrend, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: color, isBezier: false, context: context, configManager: configManager)
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
            context.setFillColor(overlayColor(3, configManager).cgColor)
            context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
    }

    /// Draws one Ichimoku line segment, skipping non-finite endpoints.
    func drawIchiLine(_ value: CGFloat, _ lastValue: CGFloat, _ color: UIColor, _ maxValue: CGFloat, _ minValue: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ index: Int, _ lastIndex: Int, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        if !value.isFinite || !lastValue.isFinite {
            return
        }
        drawLine(value: value, lastValue: lastValue, maxValue: maxValue, minValue: minValue, baseY: baseY, height: height, index: index, lastIndex: lastIndex, color: color, isBezier: false, context: context, configManager: configManager)
    }

    func drawText(_ model: HTKLineModel, _ baseX: CGFloat, _ baseY: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        if (configManager.isMinute) {

        } else {
            var x = baseX
            switch configManager.mainType {
            case .none:
                break
            case .ma:
                for (i, itemModel) in configManager.maList.enumerated() {
                    guard i >= 0,
                          i < model.maList.count,
                          itemModel.index >= 0,
                          itemModel.index < configManager.targetColorList.count else {
                        continue
                    }
                    let item = model.maList[i]
                    let title = String(format: "MA%@:%@", item.title, configManager.precision(item.value, configManager.price))
                    let color = configManager.targetColorList[itemModel.index]
                    let font = configManager.createFont(configManager.headerTextFontSize)
                    x += drawText(title: title, point: CGPoint.init(x: x, y: baseY), color: color, font: font, context: context, configManager: configManager)
                    x += 5
                }
            case .boll:
                let itemList = [
                    ["title": String(format: "BOLL:%@", configManager.precision(model.bollMb, configManager.price)), "color": configManager.targetColorList[0]],
                    ["title": String(format: "UB:%@", configManager.precision(model.bollUp, configManager.price)), "color": configManager.targetColorList[1]],
                    ["title": String(format: "LB:%@", configManager.precision(model.bollDn, configManager.price)), "color": configManager.targetColorList[2]],
                ]
                let font = configManager.createFont(configManager.headerTextFontSize)
                for item in itemList {
                    x += drawText(title: item["title"] as? String ?? "", point: CGPoint.init(x: x, y: baseY), color: item["color"] as? UIColor ?? UIColor.orange, font: font, context: context, configManager: configManager)
                    x += 5
                }
            }

            // Phase 8-B: append overlay legends after the primary indicator.
            x = drawOverlayLegend(model, x, baseY, context, configManager)
        }
    }

    /** Draws EMA/AVL/VWAP/SuperTrend/SAR header labels; returns the new x. */
    func drawOverlayLegend(_ model: HTKLineModel, _ startX: CGFloat, _ baseY: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) -> CGFloat {
        let overlays = configManager.mainOverlays
        if overlays.isEmpty {
            return startX
        }
        var x = startX
        let font = configManager.createFont(configManager.headerTextFontSize)
        if overlays.contains("ema") {
            for (i, item) in model.emaList.enumerated() {
                if !item.value.isFinite {
                    continue
                }
                let title = String(format: "EMA%@:%@", item.title, configManager.precision(item.value, configManager.price))
                x += drawText(title: title, point: CGPoint.init(x: x, y: baseY), color: overlayColor(i, configManager), font: font, context: context, configManager: configManager)
                x += 5
            }
        }
        if overlays.contains("avl"), model.avl.isFinite {
            let title = String(format: "AVL:%@", configManager.precision(model.avl, configManager.price))
            x += drawText(title: title, point: CGPoint.init(x: x, y: baseY), color: overlayColor(2, configManager), font: font, context: context, configManager: configManager)
            x += 5
        }
        if overlays.contains("vwap"), model.vwap.isFinite {
            let title = String(format: "VWAP:%@", configManager.precision(model.vwap, configManager.price))
            x += drawText(title: title, point: CGPoint.init(x: x, y: baseY), color: overlayColor(1, configManager), font: font, context: context, configManager: configManager)
            x += 5
        }
        if overlays.contains("super"), model.superTrend.isFinite {
            let color = model.superTrendUp ? configManager.increaseColor : configManager.decreaseColor
            let title = String(format: "SuperTrend:%@", configManager.precision(model.superTrend, configManager.price))
            x += drawText(title: title, point: CGPoint.init(x: x, y: baseY), color: color, font: font, context: context, configManager: configManager)
            x += 5
        }
        if overlays.contains("sar"), model.sar.isFinite {
            let title = String(format: "SAR:%@", configManager.precision(model.sar, configManager.price))
            x += drawText(title: title, point: CGPoint.init(x: x, y: baseY), color: overlayColor(3, configManager), font: font, context: context, configManager: configManager)
            x += 5
        }
        return x
    }

    func drawValue(_ maxValue: CGFloat, _ minValue: CGFloat, _ baseX: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        drawValue(maxValue, minValue, baseX, baseY, height, 4, configManager.price, context, configManager)
    }

}
