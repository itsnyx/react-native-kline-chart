//
//  HTWrDraw.swift
//  HTKLineView
//
//  Created by hublot on 2020/3/17.
//  Copyright © 2020 hublot. All rights reserved.
//

import UIKit

class HTWrDraw: NSObject, HTKLineDrawProtocol {

    /** Color from the shared palette, wrapping the index; gray if palette empty. */
    private func paletteColor(_ i: Int, _ configManager: HTKLineConfigManager) -> UIColor {
        let list = configManager.targetColorList
        if list.isEmpty {
            return UIColor.gray
        }
        let idx = ((i % list.count) + list.count) % list.count
        return list[idx]
    }

    func minMaxRange(_ visibleModelArray: [HTKLineModel], _ configManager: HTKLineConfigManager) -> Range<CGFloat> {
        var maxValue = CGFloat.leastNormalMagnitude
        var minValue = CGFloat.greatestFiniteMagnitude

        for model in visibleModelArray {
            let valueList = model.wrList.map { (item) -> CGFloat in
                return item.value
            }
            maxValue = max(maxValue, valueList.max() ?? 0)
            minValue = min(minValue, valueList.min() ?? 0)
        }
        return Range<CGFloat>.init(uncheckedBounds: (lower: minValue, upper: maxValue))
    }

    func drawCandle(_ model: HTKLineModel, _ index: Int, _ maxValue: CGFloat, _ minValue: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
    }

    func drawLine(_ model: HTKLineModel, _ lastModel: HTKLineModel, _ maxValue: CGFloat, _ minValue: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ index: Int, _ lastIndex: Int, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        // Protect against temporary mismatches between `configManager.wrList` and
        // the per‑candle `model.wrList`/`lastModel.wrList` (for example when WR is
        // toggled on before the data payload has been updated). In that case we just
        // skip drawing instead of crashing with an index out of range.
        guard !configManager.wrList.isEmpty,
              !model.wrList.isEmpty,
              !lastModel.wrList.isEmpty else {
            return
        }

        // Iterate positionally: `itemModel.index` is a color slot (it can point
        // past the per-candle list into the extended palette), never a data index.
        for (i, itemModel) in configManager.wrList.enumerated() {
            guard i < model.wrList.count,
                  i < lastModel.wrList.count else {
                continue
            }
            let color = itemModel.color ?? paletteColor(itemModel.index, configManager)
            drawLine(
                value: model.wrList[i].value,
                lastValue: lastModel.wrList[i].value,
                maxValue: maxValue,
                minValue: minValue,
                baseY: baseY,
                height: height,
                index: index,
                lastIndex: lastIndex,
                color: color,
                isBezier: false,
                context: context,
                configManager: configManager
            )
        }
    }

    func drawText(_ model: HTKLineModel, _ baseX: CGFloat, _ baseY: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        var x = baseX
        let font = configManager.createFont(configManager.headerTextFontSize)
        guard !configManager.wrList.isEmpty, !model.wrList.isEmpty else {
            return
        }
        for (i, itemModel) in configManager.wrList.enumerated() {
            guard i < model.wrList.count else {
                continue
            }
            let item = model.wrList[i]
            let title = String(format: "WR(%@):%@", item.title, configManager.precision(item.value, -1))
            let color = itemModel.color ?? paletteColor(itemModel.index, configManager)
            x += drawText(title: title, point: CGPoint.init(x: x, y: baseY), color: color, font: font, context: context, configManager: configManager)
            x += 5
        }
    }

    func drawValue(_ maxValue: CGFloat, _ minValue: CGFloat, _ baseX: CGFloat, _ baseY: CGFloat, _ height: CGFloat, _ context: CGContext, _ configManager: HTKLineConfigManager) {
        drawValue(maxValue, minValue, baseX, baseY, height, 0, -1, context, configManager)
    }


}
