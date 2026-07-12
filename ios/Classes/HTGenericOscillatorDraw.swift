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

    func minMaxRange(_ visibleModelArray: [HTKLineModel], _ configManager: HTKLineConfigManager) -> Range<CGFloat> {
        var maxValue = CGFloat.leastNormalMagnitude
        var minValue = CGFloat.greatestFiniteMagnitude
        var found = false
        for model in visibleModelArray {
            for item in model.subLines where item.value.isFinite {
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
        let n = min(model.subLines.count, lastModel.subLines.count)
        if n == 0 {
            return
        }
        for i in 0..<n {
            let value = model.subLines[i].value
            let lastValue = lastModel.subLines[i].value
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
                color: color(i, configManager),
                isBezier: false,
                context: context,
                configManager: configManager
            )
        }
    }

    func drawText(_ model: HTKLineModel, _ baseX: CGFloat, _ baseY: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        var x = baseX
        let font = configManager.createFont(configManager.headerTextFontSize)
        for (i, item) in model.subLines.enumerated() where item.value.isFinite {
            let name = item.title.isEmpty ? configManager.secondLabel : item.title
            let title = String(format: "%@:%@", name, configManager.precision(item.value, -1))
            x += drawText(title: title, point: CGPoint.init(x: x, y: baseY), color: color(i, configManager), font: font, context: context, configManager: configManager)
            x += 5
        }
    }

    func drawValue(_ maxValue: CGFloat, _ minValue: CGFloat, _ baseX: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        drawValue(maxValue, minValue, baseX, baseY, height, 0, -1, context, configManager)
    }

}
