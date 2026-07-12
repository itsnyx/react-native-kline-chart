package com.github.fujianlian.klinechart.draw;

public enum SecondStatus {
    // MACD/KDJ/RSI/WR are the original built-in sub indicators. GENERIC renders
    // any of the additional oscillators (ROC, CCI, OBV, StochRSI, MFI, DMI, DMA,
    // MTM, EMV) from the per-candle `subLines` list supplied by the JS layer.
    MACD, KDJ, RSI, WR, GENERIC, NONE,
}
