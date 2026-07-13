//
//  HTKKlineModel.swift
//  HTKLineView
//
//  Created by hublot on 2020/3/18.
//  Copyright © 2020 hublot. All rights reserved.
//

import UIKit

class HTKLineItemModel: NSObject {

    var value: CGFloat = 0

    var title = ""

    var selected = true

    var index = 0

    // Native N6 (0.4.3): explicit per-line color. When present it wins over the
    // shared targetColorList slot lookup, so the exact color the user picked in
    // the indicator settings is drawn regardless of what else is on screen.
    var color: UIColor? = nil

    /// `color` arrives as a processColor int (optionList target items) or a
    /// "#RRGGBB" hex string (per-candle items computed on the JS side).
    static func parseColor(_ value: Any?) -> UIColor? {
        if let number = value as? NSNumber {
            return RCTConvert.uiColor(number.intValue)
        }
        if let string = value as? String {
            var hex = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard hex.hasPrefix("#") else {
                return nil
            }
            hex.removeFirst()
            guard hex.count == 6 || hex.count == 8, let raw = UInt64(hex, radix: 16) else {
                return nil
            }
            let hasAlpha = hex.count == 8
            let r = CGFloat((raw >> (hasAlpha ? 24 : 16)) & 0xFF) / 255.0
            let g = CGFloat((raw >> (hasAlpha ? 16 : 8)) & 0xFF) / 255.0
            let b = CGFloat((raw >> (hasAlpha ? 8 : 0)) & 0xFF) / 255.0
            let a = hasAlpha ? CGFloat(raw & 0xFF) / 255.0 : 1.0
            return UIColor(red: r, green: g, blue: b, alpha: a)
        }
        return nil
    }

    static func packModelArray(_ modelList: [[String: Any]]) -> [HTKLineItemModel] {
        var modelArray = [HTKLineItemModel]()
        for dictionary in modelList {
            let itemModel = HTKLineItemModel()
            itemModel.title = dictionary["title"] as? String ?? ""
            itemModel.value = dictionary["value"] as? CGFloat ?? 0
            itemModel.selected = dictionary["selected"] as? Bool ?? true
            itemModel.index = dictionary["index"] as? Int ?? 0
            itemModel.color = parseColor(dictionary["color"])
            if itemModel.selected {
                modelArray.append(itemModel)
            }
        }
        return modelArray
    }

}


class HTKLineModel: NSObject {

    var dateString: String = ""

    var id: Double = 0

    var open: CGFloat = 0

    var high: CGFloat = 0

    var low: CGFloat = 0

    var close: CGFloat = 0

    var volume: CGFloat = 0

    var bollMb: CGFloat = 0

    var bollUp: CGFloat = 0

    var bollDn: CGFloat = 0

    var maList = [HTKLineItemModel]()

    var maVolumeList = [HTKLineItemModel]()

    var macdValue: CGFloat = 0

    var macdDea: CGFloat = 0

    var macdDif: CGFloat = 0

    var kdjK: CGFloat = 0

    var kdjD: CGFloat = 0

    var kdjJ: CGFloat = 0

    var rsiList = [HTKLineItemModel]()

    var wrList = [HTKLineItemModel]()

    // Native N4: generic sub-oscillator lines ({value,title}); drawn by HTGenericDraw.
    var subLines = [HTKLineItemModel]()

    // Native N7: one subLines list per stacked generic panel (order = secondList).
    var subLinesList = [[HTKLineItemModel]]()

    // Phase 8-B main-chart overlays. Scalars default to .nan so the draw layer
    // can skip candles that have no computed value.
    var emaList = [HTKLineItemModel]()

    var sar: CGFloat = .nan

    var avl: CGFloat = .nan

    var vwap: CGFloat = .nan

    var superTrend: CGFloat = .nan

    var superTrendUp: Bool = true

    // Support & Resistance overlay levels (.nan = none for this candle).
    var resistR: CGFloat = .nan
    var resistS: CGFloat = .nan

    // Native N3: Ichimoku Cloud values (.nan = none for this candle).
    var ichiTenkan: CGFloat = .nan
    var ichiKijun: CGFloat = .nan
    var ichiSpanA: CGFloat = .nan
    var ichiSpanB: CGFloat = .nan
    var ichiChikou: CGFloat = .nan

    var selectedItemList = [[String: Any]]()

    lazy var increment: Bool = {
        let increment = close >= open
        return increment
    }()

    static func packModel(_ dictionary: [String: Any]) -> HTKLineModel {
        let model = HTKLineModel()
        model.id = (dictionary["id"] as? NSNumber)?.doubleValue ?? 0
        model.dateString = dictionary["dateString"] as? String ?? ""
        model.open = dictionary["open"] as? CGFloat ?? 0
        model.high = dictionary["high"] as? CGFloat ?? 0
        model.low = dictionary["low"] as? CGFloat ?? 0
        model.close = dictionary["close"] as? CGFloat ?? 0
        model.volume = dictionary["vol"] as? CGFloat ?? 0
        model.maList = HTKLineItemModel.packModelArray(dictionary["maList"] as? [[String: Any]] ?? [])
        model.maVolumeList = HTKLineItemModel.packModelArray(dictionary["maVolumeList"] as? [[String: Any]] ?? [])
        model.rsiList = HTKLineItemModel.packModelArray(dictionary["rsiList"] as? [[String: Any]] ?? [])
        model.subLines = HTKLineItemModel.packModelArray(dictionary["subLines"] as? [[String: Any]] ?? [])
        // Native N7: per-generic-panel subLines.
        model.subLinesList = (dictionary["subLinesList"] as? [[[String: Any]]] ?? [])
            .map { HTKLineItemModel.packModelArray($0) }
        model.wrList = HTKLineItemModel.packModelArray(dictionary["wrList"] as? [[String: Any]] ?? [])
        model.bollMb = dictionary["bollMb"] as? CGFloat ?? 0
        model.bollUp = dictionary["bollUp"] as? CGFloat ?? 0
        model.bollDn = dictionary["bollDn"] as? CGFloat ?? 0
        model.macdValue = dictionary["macdValue"] as? CGFloat ?? 0
        model.macdDea = dictionary["macdDea"] as? CGFloat ?? 0
        model.macdDif = dictionary["macdDif"] as? CGFloat ?? 0
        model.kdjK = dictionary["kdjK"] as? CGFloat ?? 0
        model.kdjD = dictionary["kdjD"] as? CGFloat ?? 0
        model.kdjJ = dictionary["kdjJ"] as? CGFloat ?? 0
        // Phase 8-B overlays (all optional → .nan / empty when absent).
        model.emaList = HTKLineItemModel.packModelArray(dictionary["emaList"] as? [[String: Any]] ?? [])
        model.sar = dictionary["sar"] as? CGFloat ?? .nan
        model.avl = dictionary["avl"] as? CGFloat ?? .nan
        model.vwap = dictionary["vwap"] as? CGFloat ?? .nan
        model.superTrend = dictionary["superTrend"] as? CGFloat ?? .nan
        model.superTrendUp = dictionary["superTrendUp"] as? Bool ?? true
        model.resistR = dictionary["resistR"] as? CGFloat ?? .nan
        model.resistS = dictionary["resistS"] as? CGFloat ?? .nan
        model.ichiTenkan = dictionary["ichiTenkan"] as? CGFloat ?? .nan
        model.ichiKijun = dictionary["ichiKijun"] as? CGFloat ?? .nan
        model.ichiSpanA = dictionary["ichiSpanA"] as? CGFloat ?? .nan
        model.ichiSpanB = dictionary["ichiSpanB"] as? CGFloat ?? .nan
        model.ichiChikou = dictionary["ichiChikou"] as? CGFloat ?? .nan
        var selectedItemList = dictionary["selectedItemList"] as? [[String: Any]] ?? [[String: Any]]()
        for (i, dictionary) in selectedItemList.enumerated() {
            if let color = dictionary["color"] as? Int {
                selectedItemList[i]["color"] = RCTConvert.uiColor(color)
            }
        }
        model.selectedItemList = selectedItemList
        return model
    }

    static func packModelArray(_ modelList: [[String: Any]]) -> [HTKLineModel] {
        var modelArray = [HTKLineModel]()

        for dictionary in modelList {
            let model = packModel(dictionary)
            modelArray.append(model)
        }
        return modelArray
    }

}
