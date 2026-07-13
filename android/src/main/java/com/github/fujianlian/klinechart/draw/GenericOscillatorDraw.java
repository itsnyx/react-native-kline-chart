package com.github.fujianlian.klinechart.draw;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.github.fujianlian.klinechart.BaseKLineChartView;
import com.github.fujianlian.klinechart.HTKLineConfigManager;
import com.github.fujianlian.klinechart.HTKLineTargetItem;
import com.github.fujianlian.klinechart.KLineEntity;
import com.github.fujianlian.klinechart.base.IChartDraw;
import com.github.fujianlian.klinechart.base.IValueFormatter;
import com.github.fujianlian.klinechart.entity.ICandle;
import com.github.fujianlian.klinechart.formatter.ValueFormatter;

/**
 * Native N4: a single sub-chart renderer for every additional oscillator
 * (ROC, CCI, OBV, StochRSI, MFI, DMI, DMA, MTM, EMV). Rather than one draw class
 * per indicator, the JS layer pre-computes each candle's lines into a generic
 * {@code subLines} list ({value,title}), and this class draws them. Every access
 * is guarded so a candle without data is simply skipped (crash-safe).
 */
public class GenericOscillatorDraw implements IChartDraw<ICandle> {

    private final Context mContext;
    // Native N7: back-reference so getMaxValue/getMinValue (no view param) can
    // resolve the current stacked panel's per-candle subLines.
    private final BaseKLineChartView mView;
    private final Paint mLinePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    public GenericOscillatorDraw(BaseKLineChartView view) {
        mContext = view.getContext();
        mView = view;
        mLinePaint.setStyle(Paint.Style.STROKE);
        mLinePaint.setStrokeJoin(Paint.Join.ROUND);
        mLinePaint.setStrokeCap(Paint.Cap.ROUND);
    }

    /** The current panel's subLines for this candle (multi-panel aware). */
    private java.util.List<HTKLineTargetItem> lines(BaseKLineChartView view, KLineEntity e) {
        return view.getCurrentSubLines(e);
    }

    private int lineColor(BaseKLineChartView view, int index) {
        int[] colors = view.configManager.targetColorList;
        if (colors == null || colors.length == 0) {
            return Color.GRAY;
        }
        return colors[((index % colors.length) + colors.length) % colors.length];
    }

    /**
     * Native N6 (0.4.3): the sub line's explicit color — from the per-candle
     * item when JS attached one, else the "sub" indicatorColors entry — with
     * the shared palette slot as the final fallback for old JS bundles.
     */
    private int subLineColor(BaseKLineChartView view, HTKLineTargetItem item, int i) {
        if (item != null && item.hasColor) {
            return item.color;
        }
        return view.configManager.indicatorColor("sub", i, lineColor(view, i));
    }

    private static boolean isFinite(float v) {
        return !Float.isNaN(v) && !Float.isInfinite(v);
    }

    @Override
    public void drawTranslated(@Nullable ICandle lastPoint, @NonNull ICandle curPoint, float lastX, float curX, @NonNull Canvas canvas, @NonNull BaseKLineChartView view, int position) {
        if (!(curPoint instanceof KLineEntity) || !(lastPoint instanceof KLineEntity)) {
            return;
        }
        KLineEntity cur = (KLineEntity) curPoint;
        KLineEntity last = (KLineEntity) lastPoint;
        java.util.List<HTKLineTargetItem> curLines = lines(view, cur);
        java.util.List<HTKLineTargetItem> lastLines = lines(view, last);
        if (curLines == null || lastLines == null) {
            return;
        }
        int n = Math.min(curLines.size(), lastLines.size());
        for (int i = 0; i < n; i++) {
            HTKLineTargetItem c = (HTKLineTargetItem) curLines.get(i);
            HTKLineTargetItem l = (HTKLineTargetItem) lastLines.get(i);
            if (c == null || l == null || !isFinite(c.value) || !isFinite(l.value)) {
                continue;
            }
            mLinePaint.setColor(subLineColor(view, c, i));
            view.drawChildLine(canvas, mLinePaint, lastX, l.value, curX, c.value);
        }
    }

    @Override
    public void drawText(@NonNull Canvas canvas, @NonNull BaseKLineChartView view, int position, float x, float y) {
        KLineEntity point = (KLineEntity) view.getItem(position);
        java.util.List<HTKLineTargetItem> pointLines = lines(view, point);
        if (point == null || pointLines == null) {
            return;
        }
        String label = view.configManager.secondLabel;
        if (label == null) {
            label = "";
        }
        for (int i = 0; i < pointLines.size(); i++) {
            HTKLineTargetItem item = (HTKLineTargetItem) pointLines.get(i);
            if (item == null || !isFinite(item.value)) {
                continue;
            }
            mLinePaint.setColor(subLineColor(view, item, i));
            String title = item.title != null && item.title.length() > 0
                    ? item.title
                    : label;
            String text = title + ":" + view.formatValue(item.value) + "  ";
            canvas.drawText(text, x, y, mLinePaint);
            x += mLinePaint.measureText(text);
        }
    }

    private float extreme(ICandle point, boolean isMax) {
        KLineEntity item = (KLineEntity) point;
        java.util.List<HTKLineTargetItem> itemLines = lines(mView, item);
        if (itemLines == null || itemLines.isEmpty()) {
            return 0;
        }
        float result = isMax ? -Float.MAX_VALUE : Float.MAX_VALUE;
        boolean found = false;
        for (int i = 0; i < itemLines.size(); i++) {
            HTKLineTargetItem line = (HTKLineTargetItem) itemLines.get(i);
            if (line == null || !isFinite(line.value)) {
                continue;
            }
            found = true;
            result = isMax ? Math.max(result, line.value) : Math.min(result, line.value);
        }
        return found ? result : 0;
    }

    @Override
    public float getMaxValue(ICandle point) {
        return extreme(point, true);
    }

    @Override
    public float getMinValue(ICandle point) {
        return extreme(point, false);
    }

    @Override
    public IValueFormatter getValueFormatter() {
        return new ValueFormatter();
    }

    public void setLineWidth(float width) {
        mLinePaint.setStrokeWidth(width);
    }

    public void setTextSize(float textSize) {
        mLinePaint.setTextSize(textSize);
    }

    public void setTextFontFamily(String fontFamily) {
        Typeface typeface = HTKLineConfigManager.findFont(mContext, fontFamily);
        mLinePaint.setTypeface(typeface);
    }
}
