package com.github.fujianlian.klinechart.draw;

import android.content.Context;
import android.graphics.*;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.content.ContextCompat;

import com.github.fujianlian.klinechart.*;
import com.github.fujianlian.klinechart.base.IChartDraw;
import com.github.fujianlian.klinechart.base.IValueFormatter;
import com.github.fujianlian.klinechart.entity.ICandle;
import com.github.fujianlian.klinechart.formatter.ValueFormatter;
import com.github.fujianlian.klinechart.utils.ViewUtil;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 主图的实现类
 * Created by tifezh on 2016/6/14.
 */
public class MainDraw implements IChartDraw<ICandle> {

    private float mCandleWidth = 0;
    private float mCandleLineWidth = 0;

    private Paint mLinePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private Paint mRedPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private Paint mGreenPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private Paint ma5Paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private Paint ma10Paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private Paint ma30Paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private Paint primaryPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    // Phase 8-B: paint for extra main-chart overlays (EMA/AVL/VWAP/SUPER/SAR).
    private Paint overlayPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private float mSarRadius = 3f;

    private Paint minuteGradientPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mSelectorTextPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private Paint mSelectorBackgroundPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private Context mContext;

    private boolean mCandleSolid = true;

    private PrimaryStatus primaryStatus = PrimaryStatus.MA;
    private KLineChartView kChartView;

    public MainDraw(BaseKLineChartView view) {
        Context context = view.getContext();
        kChartView = (KLineChartView) view;
        mContext = context;


        mLinePaint.setColor(ContextCompat.getColor(context, R.color.chart_line));
        mLinePaint.setStrokeJoin(Paint.Join.ROUND);
        mLinePaint.setStrokeCap(Paint.Cap.ROUND);
        mLinePaint.setStyle(Paint.Style.STROKE);


        minuteGradientPaint.setStrokeJoin(Paint.Join.ROUND);
        minuteGradientPaint.setStrokeCap(Paint.Cap.ROUND);
        minuteGradientPaint.setStyle(Paint.Style.FILL);

        overlayPaint.setStrokeJoin(Paint.Join.ROUND);
        overlayPaint.setStrokeCap(Paint.Cap.ROUND);
        overlayPaint.setStyle(Paint.Style.STROKE);
    }

    public void reloadColor(BaseKLineChartView view) {
        mRedPaint.setColor(view.configManager.increaseColor);
        mGreenPaint.setColor(view.configManager.decreaseColor);
        mLinePaint.setColor(view.configManager.minuteLineColor);
    }

    public void setPrimaryStatus(PrimaryStatus primaryStatus) {
        this.primaryStatus = primaryStatus;
    }

    public PrimaryStatus getPrimaryStatus() {
        return primaryStatus;
    }


    public void drawMinuteMinute(float top, int startIndex, float bottom, int stopIndex, @NonNull Canvas canvas, @NonNull BaseKLineChartView view) {
        if (!view.isMinute) {
            return;
        }
        float r = mCandleWidth / 2;
        LinearGradient linearGradient = new LinearGradient(
                0,
                0,
                0,
                bottom - top,
                view.configManager.minuteGradientColorList,
                view.configManager.minuteGradientLocationList,
                Shader.TileMode.CLAMP
        );
//        minuteGradientPaint.setColor(Color.BLUE);
        minuteGradientPaint.setShader(linearGradient);

        Path path = new Path();
        for (int i = startIndex; i <= stopIndex; i++) {
            ICandle currentPoint = (ICandle) view.getItem(i);
            float currentX = view.getItemMiddleScrollX(i);
            float currentY = view.yFromValue(currentPoint.getClosePrice());
            ICandle lastPoint = i == 0 ? currentPoint : (ICandle) view.getItem(i - 1);

            float lastX = i == 0 ? currentX : view.getItemMiddleScrollX(i - 1);
            float lastY = view.yFromValue(lastPoint.getClosePrice());
            float centerX = (currentX - lastX) / 2 + lastX;
            float centerY = (currentY - lastY) / 2 + lastY;
            if (i == startIndex) {
                path.moveTo(lastX, lastY);
            }
            path.cubicTo(centerX, lastY, centerX, currentY, currentX, currentY);
        }
        Path gradientPath = new Path(path);
        gradientPath.lineTo(view.getItemMiddleScrollX(stopIndex), view.getMainBottom());
        gradientPath.lineTo(view.getItemMiddleScrollX(startIndex), view.getMainBottom());
//        gradientPath.lineTo(view.getX(startIndex), top);
        gradientPath.close();
        canvas.drawPath(gradientPath, minuteGradientPaint);
        canvas.drawPath(path, mLinePaint);

    }

    @Override
    public void drawTranslated(@Nullable ICandle lastPoint, @NonNull ICandle curPoint, float lastX, float curX, @NonNull Canvas canvas, @NonNull BaseKLineChartView view, int position) {
        if (view.isMinute) {
            return;
        }
        float closePrice = curPoint.getClosePrice();
        if (position == view.getItemCount() - 1) {
            float animated = view.getDisplayedClosePrice();
            if (!Float.isNaN(animated)) {
                closePrice = animated;
            }
        }
        drawCandle(view, canvas, curX, curPoint.getHighPrice(), curPoint.getLowPrice(), curPoint.getOpenPrice(), closePrice);
        if (primaryStatus == PrimaryStatus.MA) {
            KLineEntity lastItem = (KLineEntity) lastPoint;
            KLineEntity currentItem = (KLineEntity) curPoint;
            // Defensive: make sure per‑candle maList is present and large enough
            if (currentItem.maList == null || lastItem.maList == null) {
                return;
            }
            int configSize = view.configManager.maList != null ? view.configManager.maList.size() : 0;
            int itemSize = Math.min(
                    Math.min(configSize, currentItem.maList.size()),
                    lastItem.maList.size()
            );
            for (int i = 0; i < itemSize; i++) {
                HTKLineTargetItem currentTargetItem = (HTKLineTargetItem) currentItem.maList.get(i);
                HTKLineTargetItem lastTargetItem = (HTKLineTargetItem) lastItem.maList.get(i);
                primaryPaint.setColor(overlayColor(view, view.configManager.maList.get(i).index));
                view.drawMainLine(canvas, this.primaryPaint, lastX, lastTargetItem.value, curX, currentTargetItem.value);
            }
        } else if (primaryStatus == PrimaryStatus.BOLL) {
            //画boll
            if (lastPoint.getMb() != 0) {
                primaryPaint.setColor(overlayColor(view, 0));
                view.drawMainLine(canvas, primaryPaint, lastX, lastPoint.getMb(), curX, curPoint.getMb());
            }
            if (lastPoint.getUp() != 0) {
                primaryPaint.setColor(overlayColor(view, 1));
                view.drawMainLine(canvas, primaryPaint, lastX, lastPoint.getUp(), curX, curPoint.getUp());
            }
            if (lastPoint.getDn() != 0) {
                primaryPaint.setColor(overlayColor(view, 2));
                view.drawMainLine(canvas, primaryPaint, lastX, lastPoint.getDn(), curX, curPoint.getDn());
            }
        }

        // Phase 8-B: draw any additional selected main-chart overlays on top.
        drawMainOverlays(lastPoint, curPoint, lastX, curX, canvas, view);
    }

    private static boolean isFinite(float v) {
        return !Float.isNaN(v) && !Float.isInfinite(v);
    }

    /** Color from the shared indicator palette, wrapping the index safely. */
    private int overlayColor(BaseKLineChartView view, int index) {
        int[] colors = view.configManager.targetColorList;
        if (colors == null || colors.length == 0) {
            return Color.GRAY;
        }
        int i = ((index % colors.length) + colors.length) % colors.length;
        return colors[i];
    }

    /** Draws a single overlay line segment, skipping non-finite endpoints. */
    private void drawOverlayLine(BaseKLineChartView view, Canvas canvas, int color, float lastX, float lastVal, float curX, float curVal) {
        if (!isFinite(lastVal) || !isFinite(curVal)) {
            return;
        }
        overlayPaint.setStyle(Paint.Style.STROKE);
        overlayPaint.setColor(color);
        view.drawMainLine(canvas, overlayPaint, lastX, lastVal, curX, curVal);
    }

    /**
     * Draws the Phase 8-B overlays (EMA lines, AVL/VWAP lines, Supertrend line
     * colored by direction, SAR dots). Every access is guarded so a candle that
     * is missing a value (warm-up period, absent field) is silently skipped.
     */
    private void drawMainOverlays(@Nullable ICandle lastPoint, @NonNull ICandle curPoint, float lastX, float curX, @NonNull Canvas canvas, @NonNull BaseKLineChartView view) {
        List<String> overlays = view.configManager.mainOverlays;
        if (overlays == null || overlays.isEmpty()) {
            return;
        }
        if (!(curPoint instanceof KLineEntity) || !(lastPoint instanceof KLineEntity)) {
            return;
        }
        KLineEntity cur = (KLineEntity) curPoint;
        KLineEntity last = (KLineEntity) lastPoint;

        overlayPaint.setStyle(Paint.Style.STROKE);

        // MA / BOLL as overlays so they can combine with the primary + others.
        if (overlays.contains("ma") && cur.maList != null && last.maList != null) {
            int n = Math.min(cur.maList.size(), last.maList.size());
            for (int i = 0; i < n; i++) {
                HTKLineTargetItem c = (HTKLineTargetItem) cur.maList.get(i);
                HTKLineTargetItem l = (HTKLineTargetItem) last.maList.get(i);
                if (c == null || l == null || !isFinite(c.value) || !isFinite(l.value)) {
                    continue;
                }
                overlayPaint.setColor(overlayColor(view, i));
                view.drawMainLine(canvas, overlayPaint, lastX, l.value, curX, c.value);
            }
        }
        if (overlays.contains("boll")) {
            if (isFinite(cur.getMb()) && isFinite(last.getMb()) && last.getMb() != 0) {
                overlayPaint.setColor(overlayColor(view, 0));
                view.drawMainLine(canvas, overlayPaint, lastX, last.getMb(), curX, cur.getMb());
            }
            if (isFinite(cur.getUp()) && isFinite(last.getUp()) && last.getUp() != 0) {
                overlayPaint.setColor(overlayColor(view, 1));
                view.drawMainLine(canvas, overlayPaint, lastX, last.getUp(), curX, cur.getUp());
            }
            if (isFinite(cur.getDn()) && isFinite(last.getDn()) && last.getDn() != 0) {
                overlayPaint.setColor(overlayColor(view, 2));
                view.drawMainLine(canvas, overlayPaint, lastX, last.getDn(), curX, cur.getDn());
            }
        }

        // Ichimoku: per-segment cloud fill between Span A / Span B, then the lines.
        if (overlays.contains("ichi")) {
            if (isFinite(cur.ichiSpanA) && isFinite(last.ichiSpanA)
                    && isFinite(cur.ichiSpanB) && isFinite(last.ichiSpanB)) {
                boolean bullish = cur.ichiSpanA >= cur.ichiSpanB;
                int cloud = bullish ? view.configManager.increaseColor : view.configManager.decreaseColor;
                overlayPaint.setStyle(Paint.Style.FILL);
                overlayPaint.setColor((cloud & 0x00FFFFFF) | 0x30000000); // ~19% alpha
                android.graphics.Path path = new android.graphics.Path();
                path.moveTo(lastX, view.yFromValue(last.ichiSpanA));
                path.lineTo(curX, view.yFromValue(cur.ichiSpanA));
                path.lineTo(curX, view.yFromValue(cur.ichiSpanB));
                path.lineTo(lastX, view.yFromValue(last.ichiSpanB));
                path.close();
                canvas.drawPath(path, overlayPaint);
                overlayPaint.setStyle(Paint.Style.STROKE);
            }
            drawOverlayLine(view, canvas, overlayColor(view, 0), lastX, last.ichiTenkan, curX, cur.ichiTenkan);
            drawOverlayLine(view, canvas, overlayColor(view, 3), lastX, last.ichiKijun, curX, cur.ichiKijun);
            drawOverlayLine(view, canvas, overlayColor(view, 4), lastX, last.ichiSpanA, curX, cur.ichiSpanA);
            drawOverlayLine(view, canvas, overlayColor(view, 5), lastX, last.ichiSpanB, curX, cur.ichiSpanB);
            drawOverlayLine(view, canvas, overlayColor(view, 1), lastX, last.ichiChikou, curX, cur.ichiChikou);
        }

        if (overlays.contains("ema") && cur.emaList != null && last.emaList != null) {
            int n = Math.min(cur.emaList.size(), last.emaList.size());
            for (int i = 0; i < n; i++) {
                HTKLineTargetItem c = (HTKLineTargetItem) cur.emaList.get(i);
                HTKLineTargetItem l = (HTKLineTargetItem) last.emaList.get(i);
                if (c == null || l == null || !isFinite(c.value) || !isFinite(l.value)) {
                    continue;
                }
                overlayPaint.setColor(overlayColor(view, i));
                view.drawMainLine(canvas, overlayPaint, lastX, l.value, curX, c.value);
            }
        }
        if (overlays.contains("avl") && isFinite(cur.avl) && isFinite(last.avl)) {
            overlayPaint.setColor(overlayColor(view, 2));
            view.drawMainLine(canvas, overlayPaint, lastX, last.avl, curX, cur.avl);
        }
        if (overlays.contains("vwap") && isFinite(cur.vwap) && isFinite(last.vwap)) {
            overlayPaint.setColor(overlayColor(view, 1));
            view.drawMainLine(canvas, overlayPaint, lastX, last.vwap, curX, cur.vwap);
        }
        if (overlays.contains("super") && isFinite(cur.superTrend) && isFinite(last.superTrend)) {
            overlayPaint.setColor(cur.superTrendUp ? view.configManager.increaseColor : view.configManager.decreaseColor);
            view.drawMainLine(canvas, overlayPaint, lastX, last.superTrend, curX, cur.superTrend);
        }
        if (overlays.contains("sar") && isFinite(cur.sar)) {
            overlayPaint.setStyle(Paint.Style.FILL);
            overlayPaint.setColor(overlayColor(view, 3));
            canvas.drawCircle(curX, view.yFromValue(cur.sar), mSarRadius, overlayPaint);
            overlayPaint.setStyle(Paint.Style.STROKE);
        }
        // Support & Resistance: resistance in the bearish color, support in the
        // bullish color (step-style levels; NaN segments are skipped).
        if (overlays.contains("resist")) {
            drawOverlayLine(view, canvas, view.configManager.decreaseColor, lastX, last.resistR, curX, cur.resistR);
            drawOverlayLine(view, canvas, view.configManager.increaseColor, lastX, last.resistS, curX, cur.resistS);
        }
    }

    @Override
    public void drawText(@NonNull Canvas canvas, @NonNull BaseKLineChartView view, int position, float x, float y) {
        KLineEntity point = (KLineEntity) view.getItem(position);
        String text = "";
        String space = "  ";
        if (view.isMinute) {

        } else {
            if (primaryStatus == PrimaryStatus.MA) {
                if (point.maList == null) {
                    return;
                }
                int configSize = view.configManager.maList != null ? view.configManager.maList.size() : 0;
                int itemSize = Math.min(configSize, point.maList.size());
                for (int i = 0; i < itemSize; i++) {
                    HTKLineTargetItem targetItem = (HTKLineTargetItem) point.maList.get(i);
                    this.primaryPaint.setColor(overlayColor(view, view.configManager.maList.get(i).index));
                    StringBuilder stringBuilder = new StringBuilder();
                    stringBuilder.append("MA");
                    stringBuilder.append(targetItem.title);
                    stringBuilder.append(":");
                    stringBuilder.append(view.formatValue(targetItem.value));
                    stringBuilder.append(space);
                    text = stringBuilder.toString();
                    canvas.drawText(text, x, y, this.primaryPaint);
                    x += this.primaryPaint.measureText(text);
                }
            } else if (primaryStatus == PrimaryStatus.BOLL) {
                if (point.getMb() != 0) {
                    text = "BOLL:" + view.formatValue(point.getMb()) + space;
                    this.primaryPaint.setColor(overlayColor(view, 0));
                    canvas.drawText(text, x, y, primaryPaint);
                    x += ma5Paint.measureText(text);
                    text = "UB:" + view.formatValue(point.getUp()) + space;
                    this.primaryPaint.setColor(overlayColor(view, 1));
                    canvas.drawText(text, x, y, primaryPaint);
                    x += ma10Paint.measureText(text);
                    text = "LB:" + view.formatValue(point.getDn());
                    this.primaryPaint.setColor(overlayColor(view, 2));
                    canvas.drawText(text, x, y, primaryPaint);
                }
            }

            // Phase 8-B: append overlay legends (guarded; skips absent values).
            x = drawOverlayLegend(point, view, canvas, x, y, space);
        }
    }

    /** Draws EMA/AVL/VWAP/SuperTrend/SAR header labels; returns the new x cursor. */
    private float drawOverlayLegend(KLineEntity point, BaseKLineChartView view, Canvas canvas, float x, float y, String space) {
        List<String> overlays = view.configManager.mainOverlays;
        if (overlays == null || overlays.isEmpty() || point == null) {
            return x;
        }
        String text;
        if (overlays.contains("ema") && point.emaList != null) {
            for (int i = 0; i < point.emaList.size(); i++) {
                HTKLineTargetItem ti = (HTKLineTargetItem) point.emaList.get(i);
                if (ti == null || !isFinite(ti.value)) {
                    continue;
                }
                this.primaryPaint.setColor(overlayColor(view, i));
                text = "EMA" + ti.title + ":" + view.formatValue(ti.value) + space;
                canvas.drawText(text, x, y, this.primaryPaint);
                x += this.primaryPaint.measureText(text);
            }
        }
        if (overlays.contains("avl") && isFinite(point.avl)) {
            this.primaryPaint.setColor(overlayColor(view, 2));
            text = "AVL:" + view.formatValue(point.avl) + space;
            canvas.drawText(text, x, y, this.primaryPaint);
            x += this.primaryPaint.measureText(text);
        }
        if (overlays.contains("vwap") && isFinite(point.vwap)) {
            this.primaryPaint.setColor(overlayColor(view, 1));
            text = "VWAP:" + view.formatValue(point.vwap) + space;
            canvas.drawText(text, x, y, this.primaryPaint);
            x += this.primaryPaint.measureText(text);
        }
        if (overlays.contains("super") && isFinite(point.superTrend)) {
            this.primaryPaint.setColor(point.superTrendUp ? view.configManager.increaseColor : view.configManager.decreaseColor);
            text = "SuperTrend:" + view.formatValue(point.superTrend) + space;
            canvas.drawText(text, x, y, this.primaryPaint);
            x += this.primaryPaint.measureText(text);
        }
        if (overlays.contains("sar") && isFinite(point.sar)) {
            this.primaryPaint.setColor(overlayColor(view, 3));
            text = "SAR:" + view.formatValue(point.sar) + space;
            canvas.drawText(text, x, y, this.primaryPaint);
            x += this.primaryPaint.measureText(text);
        }
        if (overlays.contains("resist")) {
            if (isFinite(point.resistR)) {
                this.primaryPaint.setColor(view.configManager.decreaseColor);
                text = "R:" + view.formatValue(point.resistR) + space;
                canvas.drawText(text, x, y, this.primaryPaint);
                x += this.primaryPaint.measureText(text);
            }
            if (isFinite(point.resistS)) {
                this.primaryPaint.setColor(view.configManager.increaseColor);
                text = "S:" + view.formatValue(point.resistS) + space;
                canvas.drawText(text, x, y, this.primaryPaint);
                x += this.primaryPaint.measureText(text);
            }
        }
        return x;
    }

    public float findIsMaxValue(ICandle point, final boolean isMax) {
        final KLineEntity item = (KLineEntity) point;
        ArrayList<Float> valueList = new ArrayList<Float>(){{
            add(item.getHighPrice());
            add(item.getLowPrice());
        }};
        if (primaryStatus == PrimaryStatus.MA && item.maList != null && item.maList.size() > 0) {
            valueList.add(item.targetListISMax(item.maList, isMax));
        } else if (primaryStatus == PrimaryStatus.BOLL) {
            valueList.add(item.getMb());
            valueList.add(item.getUp());
            valueList.add(item.getDn());
        }

        // Phase 8-B: keep overlay lines within the visible price range. Only add
        // finite values so a NaN never poisons the min/max computation.
        List<String> overlays = kChartView != null ? kChartView.configManager.mainOverlays : null;
        if (overlays != null && !overlays.isEmpty()) {
            if (overlays.contains("ma") && item.maList != null && item.maList.size() > 0) {
                float maExtreme = item.targetListISMax(item.maList, isMax);
                if (isFinite(maExtreme)) {
                    valueList.add(maExtreme);
                }
            }
            if (overlays.contains("boll")) {
                if (isFinite(item.getUp())) valueList.add(item.getUp());
                if (isFinite(item.getMb())) valueList.add(item.getMb());
                if (isFinite(item.getDn())) valueList.add(item.getDn());
            }
            if (overlays.contains("ichi")) {
                if (isFinite(item.ichiTenkan)) valueList.add(item.ichiTenkan);
                if (isFinite(item.ichiKijun)) valueList.add(item.ichiKijun);
                if (isFinite(item.ichiSpanA)) valueList.add(item.ichiSpanA);
                if (isFinite(item.ichiSpanB)) valueList.add(item.ichiSpanB);
                if (isFinite(item.ichiChikou)) valueList.add(item.ichiChikou);
            }
            if (overlays.contains("ema") && item.emaList != null && item.emaList.size() > 0) {
                float emaExtreme = item.targetListISMax(item.emaList, isMax);
                if (isFinite(emaExtreme)) {
                    valueList.add(emaExtreme);
                }
            }
            if (overlays.contains("avl") && isFinite(item.avl)) {
                valueList.add(item.avl);
            }
            if (overlays.contains("vwap") && isFinite(item.vwap)) {
                valueList.add(item.vwap);
            }
            if (overlays.contains("super") && isFinite(item.superTrend)) {
                valueList.add(item.superTrend);
            }
            if (overlays.contains("sar") && isFinite(item.sar)) {
                valueList.add(item.sar);
            }
            if (overlays.contains("resist")) {
                if (isFinite(item.resistR)) valueList.add(item.resistR);
                if (isFinite(item.resistS)) valueList.add(item.resistS);
            }
        }
        float max = Float.MIN_VALUE;
        float min = Float.MAX_VALUE;
        for (float value: valueList) {
            if (isMax) {
                max = Math.max(max, value);
            } else {
                min = Math.min(min, value);
            }
        }
        if (isMax) {
            return max;
        }
        return min;

    }

    @Override
    public float getMaxValue(final ICandle point) {
        return findIsMaxValue(point, true);
    }

    @Override
    public float getMinValue(ICandle point) {
        return findIsMaxValue(point, false);
    }

    @Override
    public IValueFormatter getValueFormatter() {
        return new ValueFormatter();
    }

    /**
     * 画Candle
     *
     * @param canvas
     * @param x      x轴坐标
     * @param high   最高价
     * @param low    最低价
     * @param open   开盘价
     * @param close  收盘价
     */
    private void drawCandle(BaseKLineChartView view, Canvas canvas, float x, float high, float low, float open, float close) {
        // Direction is decided from prices before converting to screen space so
        // it is independent of the y-axis orientation (linear vs inverted).
        boolean isUp = close >= open;

        float highY = view.yFromValue(high);
        float lowY = view.yFromValue(low);
        float openY = view.yFromValue(open);
        float closeY = view.yFromValue(close);

        float r = mCandleWidth / 2;
        float lineR = mCandleLineWidth / 2;

        Paint paint = isUp ? mGreenPaint : mRedPaint;
        float bodyTop = Math.min(openY, closeY);
        float bodyBottom = Math.max(openY, closeY);
        if (bodyBottom - bodyTop < 1) {
            // Guarantee at least a 1px body so doji candles remain visible.
            bodyBottom = bodyTop + 1;
        }

        String style = view.configManager.candleStyle;
        if (style == null) {
            style = "allSolid";
        }

        if (style.equals("ohlc")) {
            Paint.Style previous = paint.getStyle();
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(mCandleLineWidth);
            canvas.drawLine(x, highY, x, lowY, paint);       // high–low bar
            canvas.drawLine(x - r, openY, x, openY, paint);  // open tick (left)
            canvas.drawLine(x, closeY, x + r, closeY, paint);// close tick (right)
            paint.setStyle(previous);
            return;
        }

        boolean hollow;
        if (style.equals("allHollow")) {
            hollow = true;
        } else if (style.equals("upHollow")) {
            hollow = isUp;
        } else if (style.equals("downHollow")) {
            hollow = !isUp;
        } else {
            hollow = false; // allSolid
        }

        if (hollow) {
            Paint.Style previous = paint.getStyle();
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(mCandleLineWidth);
            // Wick above and below the body.
            canvas.drawLine(x, highY, x, bodyTop, paint);
            canvas.drawLine(x, bodyBottom, x, lowY, paint);
            // Hollow body outline.
            canvas.drawRect(x - r + lineR, bodyTop, x + r - lineR, bodyBottom, paint);
            paint.setStyle(previous);
        } else {
            paint.setStyle(Paint.Style.FILL);
            canvas.drawRect(x - r, bodyTop, x + r, bodyBottom, paint);
            canvas.drawRect(x - lineR, highY, x + lineR, lowY, paint);
        }
    }

    /**
     * draw选择器
     *
     * @param view
     * @param canvas
     */
    public void drawSelector(final BaseKLineChartView view, Canvas canvas) {
        if (view.isMinute) {
            return;
        }
        Paint.FontMetrics metrics = mSelectorTextPaint.getFontMetrics();
        float textHeight = metrics.descent - metrics.ascent;

        final int index = view.getSelectedIndex();
        float padding = ViewUtil.Dp2Px(mContext, 7);
        float lineHeight = ViewUtil.Dp2Px(mContext, 8);
        float margin = ViewUtil.Dp2Px(mContext, 5);
        float width = 0;
        float left;
        float top = margin + view.getTopPadding();
        final KLineEntity point = (KLineEntity) view.getItem(index);


        List<Map<String, Object>> itemList = point.selectedItemList;

        float height = padding * 2 + (textHeight + lineHeight) * itemList.size() - lineHeight;

        for (int i = 0; i < itemList.size(); i ++) {
            Map<String, Object> map = itemList.get(i);
            String leftString = (String) map.get("title");
            String rightString = (String) map.get("detail");
            width = Math.max(width, mSelectorTextPaint.measureText(leftString + rightString));
        }

        width += padding * 2;
        width = Math.max(width, view.configManager.panelMinWidth);

        float x = view.scrollXtoViewX(view.getItemMiddleScrollX(index));
        if (x > view.getChartWidth() / 2) {
            left = margin;
        } else {
            // Keep the hover info panel clear of the right-side y-axis labels.
            String maxAxis = view.formatValue(view.getMainMaxValue());
            String minAxis = view.formatValue(view.getMainMinValue());
            float axisLabelWidth = Math.max(
                    view.getTextPaint().measureText(maxAxis),
                    view.getTextPaint().measureText(minAxis)
            );
            float axisInset = axisLabelWidth + ViewUtil.Dp2Px(mContext, 10);
            left = view.getChartWidth() - width - margin - axisInset;
            if (left < margin) {
                left = margin;
            }
        }

        // Also keep the hover info panel clear of the hover price pill (+ icon) on the right.
        float pillLeft = view.getSelectedPricePillLeft();
        if (pillLeft > 0) {
            float gap = ViewUtil.Dp2Px(mContext, 8);
            float maxLeft = pillLeft - gap - width;
            if (left > maxLeft) {
                left = Math.max(margin, maxLeft);
            }
        }

        RectF r = new RectF(left, top, left + width, top + height);

        mSelectorBackgroundPaint.setStyle(Paint.Style.FILL);
        mSelectorBackgroundPaint.setColor(view.configManager.panelBackgroundColor);
        canvas.drawRoundRect(r, 5, 5, mSelectorBackgroundPaint);

        mSelectorBackgroundPaint.setStyle(Paint.Style.STROKE);
        mSelectorBackgroundPaint.setStrokeWidth(1);
        mSelectorBackgroundPaint.setColor(view.configManager.panelBorderColor);
        canvas.drawRoundRect(r, 5, 5, mSelectorBackgroundPaint);

        float y = top + padding + (textHeight - metrics.bottom - metrics.top) / 2;

        for (int i = 0; i < itemList.size(); i ++) {
            Map<String, Object> map = itemList.get(i);
            String leftString = (String) map.get("title");
            String rightString = (String) map.get("detail");
            mSelectorTextPaint.setTextSize(view.configManager.panelTextFontSize);

            int paintColor = view.configManager.candleTextColor;
            mSelectorTextPaint.setColor(paintColor);
            canvas.drawText(leftString, left + padding, y, mSelectorTextPaint);
            if (map.get("color") != null) {
                paintColor = new Integer(((Number) map.get("color")).intValue());
                mSelectorTextPaint.setColor(paintColor);
            }
            canvas.drawText(rightString, r.right - mSelectorTextPaint.measureText(rightString) - padding, y, mSelectorTextPaint);
            y += textHeight + lineHeight;
        }

    }

    /**
     * 设置蜡烛宽度
     *
     * @param candleWidth
     */
    public void setCandleWidth(float candleWidth) {
        mCandleWidth = candleWidth;
    }

    /**
     * 设置蜡烛线宽度
     *
     * @param candleLineWidth
     */
    public void setCandleLineWidth(float candleLineWidth) {
        mCandleLineWidth = candleLineWidth;
    }

    /**
     * 设置ma5颜色
     *
     * @param color
     */
    public void setMa5Color(int color) {
        this.ma5Paint.setColor(color);
    }

    /**
     * 设置ma10颜色
     *
     * @param color
     */
    public void setMa10Color(int color) {
        this.ma10Paint.setColor(color);
    }

    /**
     * 设置ma30颜色
     *
     * @param color
     */
    public void setMa30Color(int color) {
        this.ma30Paint.setColor(color);
    }

    /**
     * 设置选择器文字颜色
     *
     * @param color
     */
    public void setSelectorTextColor(int color) {
        mSelectorTextPaint.setColor(color);
    }

    /**
     * 设置选择器文字大小
     *
     * @param textSize
     */
    public void setSelectorTextSize(float textSize) {
        mSelectorTextPaint.setTextSize(textSize);
    }

    /**
     * 设置选择器背景
     *
     * @param color
     */
    public void setSelectorBackgroundColor(int color) {
        mSelectorBackgroundPaint.setColor(color);
    }

    /**
     * 设置曲线宽度
     */
    public void setLineWidth(float width) {
        ma30Paint.setStrokeWidth(width);
        ma10Paint.setStrokeWidth(width);
        ma5Paint.setStrokeWidth(width);
        primaryPaint.setStrokeWidth(width);
        overlayPaint.setStrokeWidth(width);
        mLinePaint.setStrokeWidth(width);
    }

    /**
     * 设置文字大小
     */
    public void setTextSize(float textSize) {
        ma30Paint.setTextSize(textSize);
        ma10Paint.setTextSize(textSize);
        ma5Paint.setTextSize(textSize);
        primaryPaint.setTextSize(textSize);
    }

    public void setTextFontFamily(String fontFamily) {
        Typeface typeface = HTKLineConfigManager.findFont(mContext, fontFamily);
        mLinePaint.setTypeface(typeface);
        mRedPaint.setTypeface(typeface);
        mGreenPaint.setTypeface(typeface);
        ma5Paint.setTypeface(typeface);
        ma10Paint.setTypeface(typeface);
        ma30Paint.setTypeface(typeface);
        primaryPaint.setTypeface(typeface);

        minuteGradientPaint.setTypeface(typeface);

        mSelectorTextPaint.setTypeface(typeface);
        mSelectorBackgroundPaint.setTypeface(typeface);
    }

    /**
     * 蜡烛是否实心
     */
    public void setCandleSolid(boolean candleSolid) {
        mCandleSolid = candleSolid;
    }

}
