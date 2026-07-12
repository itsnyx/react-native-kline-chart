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
    private final Paint mLinePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    public GenericOscillatorDraw(BaseKLineChartView view) {
        mContext = view.getContext();
        mLinePaint.setStyle(Paint.Style.STROKE);
        mLinePaint.setStrokeJoin(Paint.Join.ROUND);
        mLinePaint.setStrokeCap(Paint.Cap.ROUND);
    }

    private int lineColor(BaseKLineChartView view, int index) {
        int[] colors = view.configManager.targetColorList;
        if (colors == null || colors.length == 0) {
            return Color.GRAY;
        }
        return colors[((index % colors.length) + colors.length) % colors.length];
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
        if (cur.subLines == null || last.subLines == null) {
            return;
        }
        int n = Math.min(cur.subLines.size(), last.subLines.size());
        for (int i = 0; i < n; i++) {
            HTKLineTargetItem c = (HTKLineTargetItem) cur.subLines.get(i);
            HTKLineTargetItem l = (HTKLineTargetItem) last.subLines.get(i);
            if (c == null || l == null || !isFinite(c.value) || !isFinite(l.value)) {
                continue;
            }
            mLinePaint.setColor(lineColor(view, i));
            view.drawChildLine(canvas, mLinePaint, lastX, l.value, curX, c.value);
        }
    }

    @Override
    public void drawText(@NonNull Canvas canvas, @NonNull BaseKLineChartView view, int position, float x, float y) {
        KLineEntity point = (KLineEntity) view.getItem(position);
        if (point == null || point.subLines == null) {
            return;
        }
        String label = view.configManager.secondLabel;
        if (label == null) {
            label = "";
        }
        for (int i = 0; i < point.subLines.size(); i++) {
            HTKLineTargetItem item = (HTKLineTargetItem) point.subLines.get(i);
            if (item == null || !isFinite(item.value)) {
                continue;
            }
            mLinePaint.setColor(lineColor(view, i));
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
        if (item.subLines == null || item.subLines.isEmpty()) {
            return 0;
        }
        float result = isMax ? -Float.MAX_VALUE : Float.MAX_VALUE;
        boolean found = false;
        for (int i = 0; i < item.subLines.size(); i++) {
            HTKLineTargetItem line = (HTKLineTargetItem) item.subLines.get(i);
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
