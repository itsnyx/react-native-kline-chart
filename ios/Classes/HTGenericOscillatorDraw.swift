//
//  HTGenericOscillatorDraw.swift
//  HTKLineView
//
//  Native N4: a single sub-chart renderer for every additional oscillator
//  (ROC, CCI, OBV, StochRSI, MFI, DMI, DMA, MTM, EMV). The JS layer pre-computes
//  each candle's lines into a generic `subLines` list ({value,title}); this class
//  draws them. Every access is guarded so a candle without data is simply skipped.
//

import UIKit

class HTGenericOscillatorDraw: NSObject, HTKLineDrawProtocol {

    private func color(_ index: Int, _ configManager: HTKLineConfigManager) -> UIColor {
        let colors = configManager.targetColorList
        if colors.isEmpty {
            return UIColor.gray
        }
        return colors[((index % colors.count) + colors.count) % colors.count]
    }

    /// Native N6 (0.4.3): the sub line's explicit color — from the per-candle
    /// item when JS attached one, else the "sub" indicatorColors entry — with
    /// the shared palette slot as the final fallback for old JS bundles.
    private func subLineColor(_ item: HTKLineItemModel, _ i: Int, _ configManager: HTKLineConfigManager) -> UIColor {
        if let itemColor = item.color {
            return itemColor
        }
        return configManager.indicatorColor("sub", i, color(i, configManager))
    }

    /// Native N7: the current stacked panel's per-candle lines. When several
    /// generic oscillators are stacked, `configManager.currentGenericIndex`
    /// selects the matching `subLinesList` entry; a value of -1 (single panel)
    /// or an old JS payload falls back to the legacy `subLines`.
    private func lines(_ model: HTKLineModel, _ configManager: HTKLineConfigManager) -> [HTKLineItemModel] {
        let g = configManager.currentGenericIndex
        if g >= 0 && g < model.subLinesList.count {
            return model.subLinesList[g]
        }
        return model.subLines
    }

    func minMaxRange(_ visibleModelArray: [HTKLineModel], _ configManager: HTKLineConfigManager) -> Range<CGFloat> {
        var maxValue = CGFloat.leastNormalMagnitude
        var minValue = CGFloat.greatestFiniteMagnitude
        var found = false
        for model in visibleModelArray {
            for item in lines(model, configManager) where item.value.isFinite {
                found = true
                maxValue = max(maxValue, item.value)
                minValue = min(minValue, item.value)
            }
        }
        if !found {
            return Range<CGFloat>.init(uncheckedBounds: (lower: 0, upper: 0))
        }
        return Range<CGFloat>.init(uncheckedBounds: (lower: minValue, upper: maxValue))
    }

    func drawCandle(_ model: HTKLineModel, _ index: Int, _ maxValue: CGFloat, _ minValue: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
    }

    func drawLine(_ model: HTKLineModel, _ lastModel: HTKLineModel, _ maxValue: CGFloat, _ minValue: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ index: Int, _ lastIndex: Int, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        let curLines = lines(model, configManager)
        let lastLines = lines(lastModel, configManager)
        let n = min(curLines.count, lastLines.count)
        if n == 0 {
            return
        }
        for i in 0..<n {
            let item = curLines[i]
            let value = item.value
            let lastValue = lastLines[i].value
            guard value.isFinite, lastValue.isFinite else {
                continue
            }
            drawLine(
                value: value,
                lastValue: lastValue,
                maxValue: maxValue,
                minValue: minValue,
                baseY: baseY,
                height: height,
                index: index,
                lastIndex: lastIndex,
                color: subLineColor(item, i, configManager),
                isBezier: false,
                context: context,
                configManager: configManager
            )
        }
    }

    func drawText(_ model: HTKLineModel, _ baseX: CGFloat, _ baseY: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        var x = baseX
        let font = configManager.createFont(configManager.headerTextFontSize)
        for (i, item) in lines(model, configManager).enumerated() where item.value.isFinite {
            let name = item.title.isEmpty ? configManager.secondLabelText(at: configManager.currentPanelIndex) : item.title
            let title = String(format: "%@:%@", name, configManager.precision(item.value, -1))
            x += drawText(title: title, point: CGPoint.init(x: x, y: baseY), color: subLineColor(item, i, configManager), font: font, context: context, configManager: configManager)
            x += 5
        }
    }

    func drawValue(_ maxValue: CGFloat, _ minValue: CGFloat, _ baseX: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        drawValue(maxValue, minValue, baseX, baseY, height, 0, -1, context, configManager)
    }

}
