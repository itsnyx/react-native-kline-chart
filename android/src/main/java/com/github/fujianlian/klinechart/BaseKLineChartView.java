package com.github.fujianlian.klinechart;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.*;
import android.graphics.drawable.Drawable;
import android.view.animation.DecelerateInterpolator;
import androidx.core.view.GestureDetectorCompat;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;

import com.airbnb.lottie.*;
import com.github.fujianlian.klinechart.base.IChartDraw;
import com.github.fujianlian.klinechart.base.IDateTimeFormatter;
import com.github.fujianlian.klinechart.base.IValueFormatter;
import com.github.fujianlian.klinechart.container.HTDrawContext;
import com.github.fujianlian.klinechart.container.HTPoint;
import com.github.fujianlian.klinechart.draw.MainDraw;
import com.github.fujianlian.klinechart.draw.PrimaryStatus;
import com.github.fujianlian.klinechart.entity.IKLine;
import com.github.fujianlian.klinechart.formatter.TimeFormatter;
import com.github.fujianlian.klinechart.formatter.ValueFormatter;
import com.github.fujianlian.klinechart.utils.DateUtil;
import com.github.fujianlian.klinechart.utils.ViewUtil;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;

/**
 * k线图
 * Created by tian on 2016/5/3.
 */
public abstract class BaseKLineChartView extends ScrollAndScaleView implements Drawable.Callback {

    public HTKLineConfigManager configManager;

    public HTDrawContext drawContext;



    private int mChildDrawPosition = -1;

    private int mWidth = 0;

    private int mTopPadding;

    private int mChildPadding;

    private int mBottomPadding;

    private float mMainScaleY = 1;

    private float mVolScaleY = 1;

    private float mChildScaleY = 1;

    private float mDataLen = 0;

    private float mMainMaxValue = Float.MAX_VALUE;

    private float mMainMinValue = Float.MIN_VALUE;

    private float mMainHighMaxValue = 0;

    private float mMainLowMinValue = 0;

    private int mMainMaxIndex = 0;

    private int mMainMinIndex = 0;

    private Float mVolMaxValue = Float.MAX_VALUE;

    private Float mVolMinValue = Float.MIN_VALUE;

    private Float mChildMaxValue = Float.MAX_VALUE;

    private Float mChildMinValue = Float.MIN_VALUE;

    // Y-axis zoom factor: 1.0 = 100% (auto-fit), up to 5.0 = 20% (zoomed out).
    // Persists across gestures so the zoom level is retained after finger lift.
    private float mYAxisZoomFactor = 1.0f;

    // --- Right y-axis drag scaling (vertical zoom) ---
    private boolean mIsYAxisScaling = false;
    private boolean mIsYAxisScaleCandidate = false;
    private float mYAxisDownX = Float.NaN;
    private float mYAxisDownY = Float.NaN;
    private float mYAxisScaleStartY = Float.NaN;
    private float mYAxisScaleStartFactor = 1.0f;
    // Defaults: ~64dp hit target and "one screen height drag ~= ~2x zoom"
    private final float mYAxisGestureWidthDp = 64f;
    private final float mYAxisGestureSensitivityFactor = 0.7f;

    private int mStartIndex = 0;

    private int mStopIndex = 0;

    private float mPointWidth = 6;

    private int mGridRows = 4;

    private int mGridColumns = 4;

    private Paint mGridPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    // Background grid drawn behind the candles: horizontal lines aligned with the
    // Y-axis price labels and vertical lines dividing the width into 5 regions.
    private Paint mBackgroundGridPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mTextPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mMaxMinPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mBackgroundPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mSelectedXLinePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mSelectedYLinePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    /**
     * During long-press selection we snap X to the nearest candle (mSelectedIndex),
     * but keep Y free so the user can drag vertically and read arbitrary prices.
     * Stored in view coordinates.
     */
    private float mSelectedY = Float.NaN;

    private Paint mSelectPointPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mSelectCenterPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mSelectCenterBackgroundPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mSelectorFramePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mClosePriceLinePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mClosePricePointPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mClosePriceTrianglePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private Paint mClosePriceRightTextPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private LottieDrawable lottieDrawable = new LottieDrawable();

    private String lastLoadLottieSource = "";

    private int mSelectedIndex;

    // Change-detection for the app-side crosshair readout (hoverInfoMode ==
    // "topLayer"). We only emit onCrosshairChange when the visible/index state
    // actually changes, so this can be polled cheaply from onDraw.
    private int mLastCrosshairIndex = -1;
    private boolean mLastCrosshairVisible = false;

    private IChartDraw mMainDraw;
    private MainDraw mainDraw;
    private IChartDraw mVolDraw;

    public Boolean isMinute = false;

    private Boolean isWR = false;
    private Boolean isShowChild = false;

    //当前点的个数
    private int mItemCount;
    private IChartDraw mChildDraw;
    private List<IChartDraw> mChildDraws = new ArrayList<>();

    // Native N7: stacked sub-panels. mActiveChildDraws holds one draw per panel
    // (top→bottom), each with its own rect / min / max / scale. During drawing
    // the single mChildDraw/mChildRect/mChildMaxValue/... fields are rebound to
    // the current panel so all existing single-panel draw code (getChildY,
    // drawText, axis, selector) works unchanged.
    private List<IChartDraw> mActiveChildDraws = new ArrayList<>();
    private List<Rect> mChildRects = new ArrayList<>();
    private float[] mChildMaxValues = new float[0];
    private float[] mChildMinValues = new float[0];
    private float[] mChildScaleYs = new float[0];
    // For each active panel: its index among generic-oscillator panels, or -1
    // if it is a built-in (MACD/KDJ/RSI/WR) panel. Used to pick the right
    // per-candle subLines from KLineEntity.subLinesList.
    private int[] mChildGenericIndex = new int[0];
    private boolean[] mChildIsWR = new boolean[0];
    private int mCurrentGenericIndex = -1;

    private IValueFormatter mValueFormatter;
    private IDateTimeFormatter mDateTimeFormatter;

    private ValueAnimator mAnimator;

    private long mAnimationDuration = 500;

    private float mOverScrollRange = 0;

    private OnSelectedChangedListener mOnSelectedChangedListener = null;

    private Rect mMainRect;

    private Rect mVolRect;

    private Rect mChildRect;

    private float mLineWidth;

    // Hit target for the right-side hover price pill (used to trigger `onNewOrder`).
    private final RectF mSelectedPricePillRect = new RectF();
    private float mSelectedPriceValue = Float.NaN;

    // Hit target for the close price center pill (shown when scrolled left, tap to scroll to present).
    private final RectF mClosePriceCenterPillRect = new RectF();

    // Timer for candle countdown (fires every second to redraw the remaining time).
    private android.os.Handler mCountdownHandler;
    private Runnable mCountdownRunnable;

    // Animated close price: smoothly interpolate the displayed value.
    private float mDisplayedClosePrice = Float.NaN;
    private float mClosePriceAnimationTarget = Float.NaN;
    private ValueAnimator mClosePriceAnimator;

    public float getDisplayedClosePrice() {
        return mDisplayedClosePrice;
    }

    public int getItemCount() {
        return mItemCount;
    }

    // Animated vertical scale: smoothly interpolate min/max when visible range changes.
    private float mAnimatedMainMaxValue = Float.NaN;
    private float mAnimatedMainMinValue = Float.NaN;
    private float mAnimatedVolMaxValue = Float.NaN;
    private float mAnimatedVolMinValue = Float.NaN;
    private float mAnimatedChildMaxValue = Float.NaN;
    private float mAnimatedChildMinValue = Float.NaN;
    private int mPrevItemCountForAnim = -1;
    // When true, the next calculateValue() snaps the animated min/max to target
    // instead of lerping. notifyChanged() sets this for normal/wholesale updates;
    // notifyChangedAnimated() leaves it false so prepended history rescales smoothly.
    private boolean mForceScaleSnap = false;
    private static final float SCALE_ANIM_LERP = 0.12f;

    public BaseKLineChartView(Context context, HTKLineConfigManager configManager) {
        super(context);
        this.configManager = configManager;
        init();
    }

    private void init() {
        setWillNotDraw(false);
        drawContext = new HTDrawContext(this, configManager);




        mDetector = new GestureDetectorCompat(getContext(), this);
        mScaleDetector = new ScaleGestureDetector(getContext(), this);
//        mTopPadding = (int) getResources().getDimension(R.dimen.chart_top_padding);
//        mChildPadding = (int) getResources().getDimension(R.dimen.child_top_padding);
//        mBottomPadding = (int) getResources().getDimension(R.dimen.chart_bottom_padding);


        mAnimator = ValueAnimator.ofFloat(0f, 1f);
        mAnimator.setDuration(mAnimationDuration);
        mAnimator.addUpdateListener(new ValueAnimator.AnimatorUpdateListener() {
            @Override
            public void onAnimationUpdate(ValueAnimator animation) {
                // invalidate();
            }
        });

        mSelectorFramePaint.setStrokeWidth(ViewUtil.Dp2Px(getContext(), 0.6f));
        mSelectorFramePaint.setStyle(Paint.Style.STROKE);
        mSelectorFramePaint.setColor(Color.WHITE);

        mClosePriceLinePaint.setStyle(Paint.Style.STROKE);
        mClosePriceLinePaint.setAntiAlias(true);
        mClosePriceLinePaint.setStrokeWidth(ViewUtil.Dp2Px(getContext(), 0.5f));
        mClosePriceLinePaint.setPathEffect(new DashPathEffect(new float[]{8, 8}, 0));

        mClosePricePointPaint.setStrokeWidth(1);

        mClosePriceTrianglePaint.setStyle(Paint.Style.FILL);

        mBackgroundGridPaint.setStyle(Paint.Style.STROKE);
        mBackgroundGridPaint.setStrokeWidth(1f);

    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        stopCandleCountdownTimer();
    }

    @Override
    public void invalidateDrawable(Drawable drawable) {
        super.invalidateDrawable(drawable);
        if (isMinute) {
            this.invalidate();
        }
    }

    private void initLottieView() {
    	String jsonString = configManager.closePriceRightLightLottieSource;
    	if (lastLoadLottieSource == jsonString) {
    		return;
    	}
    	lastLoadLottieSource = jsonString;
        lottieDrawable.setCallback(this);
        
        final float scale = configManager.closePriceRightLightLottieScale;
        if (jsonString.length() > 0) {
            lottieDrawable.setImagesAssetsFolder(configManager.closePriceRightLightLottieFloder);
            LottieCompositionFactory.fromJsonString(jsonString, null).addListener(new LottieListener<LottieComposition>() {
                @Override
                public void onResult(LottieComposition composition) {
                    lottieDrawable.setComposition(composition);
                    lottieDrawable.setRepeatCount(Integer.MAX_VALUE);
                    lottieDrawable.setScale(scale);
                    lottieDrawable.playAnimation();
                }
            });
        }
    }


    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        // "At end" is measured against the resting flush position with the OLD
        // width. On a resize (e.g. rotation to landscape) a chart that was
        // pinned to the newest candle must stay pinned; without this the scroll
        // clamp lands on getMaxScrollX(), exposing the right-padding tail as a
        // blank gap between the last candle and the price axis.
        boolean wasAtEnd = oldw > 0 && getScrollOffset() >= endScrollXForWidth(oldw);
        this.mWidth = w;
        notifyChanged();
        if (wasAtEnd && w != oldw) {
            setScrollX(getEndScrollX());
        }
    }


    private void initRect() {
        mTopPadding = (int) configManager.paddingTop;
        mChildPadding = 50;
        mBottomPadding = (int) configManager.paddingBottom;
        Paint.FontMetrics fm = mTextPaint.getFontMetrics();
        int textHeight = (int)((fm.descent - fm.ascent) / 2.0);


        int allHeight = this.getHeight() - mBottomPadding;
        boolean showVolume = configManager == null || configManager.showVolume;

        // Native N7: stacked fixed-height sub-panels. Each panel (VOL + every
        // oscillator) is `subPanelHeight` px; the main chart takes the rest. The
        // RN container is grown by the JS side so the main area stays readable.
        if (configManager != null && configManager.subPanelHeight > 0 && isMultiPanel()) {
            int panelPx = (int) configManager.subPanelHeight;
            int subPanelCount = (showVolume ? 1 : 0) + mActiveChildDraws.size();
            int mainBottom = allHeight - subPanelCount * panelPx;
            int minMain = mTopPadding + textHeight + 60;
            if (mainBottom < minMain) {
                mainBottom = minMain;
            }
            mMainRect = new Rect(0, mTopPadding - textHeight, mWidth, mainBottom - textHeight);
            int y = mainBottom;
            if (showVolume) {
                mVolRect = new Rect(0, y, mWidth, y + panelPx);
                y += panelPx;
            } else {
                mVolRect = new Rect(0, y, mWidth, y);
            }
            mChildRects = new ArrayList<>();
            for (int i = 0; i < mActiveChildDraws.size(); i++) {
                mChildRects.add(new Rect(0, y, mWidth, y + panelPx));
                y += panelPx;
            }
            mChildRect = mChildRects.isEmpty()
                    ? new Rect(0, y, mWidth, y)
                    : mChildRects.get(mChildRects.size() - 1);
            return;
        }
        mChildRects = new ArrayList<>();

        float childFlex = 1 - configManager.mainFlex - configManager.volumeFlex;
        // When volume is hidden, merge volumeFlex into the main chart so the main area expands
        // and the child area remains the same height.
        int mMainHeight = (int) (allHeight * (configManager.mainFlex + (showVolume ? 0f : configManager.volumeFlex)));
        // When volume is shown but there is NO child oscillator, the child area
        // would sit empty — give its share to the volume panel so volume renders
        // large and fully visible (critical on short landscape viewports where
        // the base volumeFlex alone is too small to be usable).
        boolean mergeChildIntoVol = showVolume && !isShowChild;
        int mVolHeight = showVolume
                ? (int) (allHeight * (configManager.volumeFlex + (mergeChildIntoVol ? childFlex : 0f)))
                : 0;
        int mChildHeight = (int) (allHeight * (mergeChildIntoVol ? 0f : childFlex));

        // Inter-panel gap is a fixed pixel value tuned for tall portrait charts;
        // on short viewports it can exceed a panel's own flex height and invert
        // (clip) the volume rect, so clamp it to leave a usable panel body.
        int volGap = showVolume ? Math.min(mChildPadding, Math.max(0, mVolHeight - 16)) : mChildPadding;

        mMainRect = new Rect(0, mTopPadding - textHeight, mWidth, mMainHeight - textHeight);
        if (showVolume) {
            int volTop = mMainRect.bottom + textHeight + volGap;
            int volBottom = mMainRect.bottom + textHeight + mVolHeight;
            if (volBottom > allHeight) {
                volBottom = allHeight;
            }
            mVolRect = new Rect(0, volTop, mWidth, volBottom);
            mChildRect = new Rect(0, mVolRect.bottom + mChildPadding, mWidth, mVolRect.bottom + mChildHeight);
        } else {
            // Collapse volume rect to a zero-height separator at the end of the main chart.
            int boundaryY = mMainRect.bottom + textHeight;
            mVolRect = new Rect(0, boundaryY, mWidth, boundaryY);
            mChildRect = new Rect(0, boundaryY + mChildPadding, mWidth, boundaryY + mChildPadding + mChildHeight);
        }
        if (!isShowChild) {
            mChildRect.top = mVolRect.bottom;
            mChildRect.bottom = mVolRect.bottom;
        }

    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
//        canvas.drawColor(mBackgroundPaint.getColor());

        if (mWidth == 0 || mMainRect == null || mMainRect.height() == 0) {
            return;
        }
        calculateValue();
        canvas.save();
        canvas.scale(1, 1);
        drawGird(canvas);

        // Draw optional center logo behind candles (if provided from JS via configList.centerLogoSource).
        drawCenterLogo(canvas);

        if (mItemCount > 0) {
            drawK(canvas);
            drawText(canvas);
            drawMaxAndMin(canvas);
            drawValue(canvas, isLongPress ? mSelectedIndex : mStopIndex);
            drawClosePriceLine(canvas);
            drawCandleCountdown(canvas);
        }
        canvas.restore();


//        Path path = new Path();
//        path.addRect(0, mMainRect.top, getMaxScrollX() + getWidth(), mMainRect.bottom, Path.Direction.CW);
//        canvas.clipPath(path);
        // Draw user drawings (lines/labels/etc.) below the hover selector overlays.
        // This ensures the right-side hover price pill is always rendered on top.
        drawContext.onDraw(canvas);

        if (mItemCount > 0) {
            drawSelector(canvas);
        }

        maybeEmitCrosshair();
    }

    /**
     * When hoverInfoMode == "topLayer" the native library does NOT draw a hover
     * info panel — instead it forwards the selected candle to the JS/app side so
     * the app renders the OHLC readout itself (e.g. in its own header). This is
     * polled from onDraw but only fires onCrosshairChange when the selection
     * (visible flag or snapped index) actually changes.
     */
    private void maybeEmitCrosshair() {
        boolean topLayer = configManager != null
                && "topLayer".equals(configManager.hoverInfoMode);

        if (!topLayer) {
            // Mode changed away from topLayer while a selection was reported as
            // visible — emit a single "hidden" so the app clears its readout.
            if (mLastCrosshairVisible) {
                mLastCrosshairVisible = false;
                mLastCrosshairIndex = -1;
                if (configManager != null && configManager.onCrosshairChange != null) {
                    configManager.onCrosshairChange.invoke(Boolean.FALSE, -1, null);
                }
            }
            return;
        }

        boolean visible = isLongPress
                && mSelectedIndex >= 0
                && mSelectedIndex < mItemCount;

        if (visible == mLastCrosshairVisible
                && (!visible || mSelectedIndex == mLastCrosshairIndex)) {
            return;
        }

        mLastCrosshairVisible = visible;
        mLastCrosshairIndex = visible ? mSelectedIndex : -1;

        if (configManager == null || configManager.onCrosshairChange == null) {
            return;
        }
        if (visible) {
            Object point = getItem(mSelectedIndex);
            configManager.onCrosshairChange.invoke(Boolean.TRUE, mSelectedIndex, point);
        } else {
            configManager.onCrosshairChange.invoke(Boolean.FALSE, -1, null);
        }
    }

    /**
     * Draw a semi-transparent bitmap centered in the main chart area, behind candles.
     * The bitmap comes from configManager.centerLogoBitmap (decoded from JS base64).
     */
    private void drawCenterLogo(Canvas canvas) {
        if (configManager == null || configManager.centerLogoBitmap == null) {
            return;
        }
        if (mMainRect == null || mMainRect.height() <= 0 || mWidth <= 0) {
            return;
        }

        Bitmap logo = configManager.centerLogoBitmap;
        int bmpWidth = logo.getWidth();
        int bmpHeight = logo.getHeight();
        if (bmpWidth <= 0 || bmpHeight <= 0) {
            return;
        }

        // Constrain logo to at most ~35% of chart width/height.
        float maxLogoWidth = mWidth * 0.35f;
        float maxLogoHeight = mMainRect.height() * 0.35f;
        float widthScale = maxLogoWidth / bmpWidth;
        float heightScale = maxLogoHeight / bmpHeight;
        float scale = Math.min(Math.min(widthScale, heightScale), 1.0f);

        float drawWidth = bmpWidth * scale;
        float drawHeight = bmpHeight * scale;

        float left = (mWidth - drawWidth) / 2.0f;
        float top = mMainRect.top + (mMainRect.height() - drawHeight) / 2.0f;
        RectF dest = new RectF(left, top, left + drawWidth, top + drawHeight);

        // Use background paint as a holder for alpha; preserve its previous alpha.
        int oldAlpha = mBackgroundPaint.getAlpha();
        mBackgroundPaint.setAlpha((int) (0.10f * 255)); // 10% opacity
        canvas.drawBitmap(logo, null, dest, mBackgroundPaint);
        mBackgroundPaint.setAlpha(oldAlpha);
    }

    // Native N2: coordinate helpers. Percentage view is an affine relabel of the
    // linear axis, so it does not change the mapping (only the label text). Only
    // "log" and inverted change value↔pixel. Everything is guarded so bad input
    // degrades to the linear mapping rather than blanking the chart.
    private boolean isLogCoordinate() {
        return configManager != null && "log".equals(configManager.coordinateType)
                && mMainMaxValue > 0 && mMainMinValue > 0;
    }

    private boolean isInvertedCoordinate() {
        return configManager != null && configManager.invertedView;
    }

    public float yFromValue(float value) {
        if (mItemCount <= 0) {
            return value;
        }
        float h = mMainRect.height();
        if (mMainMaxValue == mMainMinValue) {
            return mMainRect.top + h * 0.5f;
        }
        float frac; // 0 at the top of the main rect, 1 at the bottom.
        if (isLogCoordinate() && value > 0) {
            double lmax = Math.log10(mMainMaxValue);
            double lmin = Math.log10(mMainMinValue);
            double lv = Math.log10(value);
            double denom = lmax - lmin;
            frac = denom == 0 ? 0.5f : (float) ((lmax - lv) / denom);
        } else {
            frac = (mMainMaxValue - value) / (mMainMaxValue - mMainMinValue);
        }
        if (isInvertedCoordinate()) {
            frac = 1f - frac;
        }
        return mMainRect.top + frac * h;
    }

    public float valueFromY(float y) {
        if (mItemCount <= 0) {
            return y;
        }
        float h = mMainRect.height();
        if (mMainMaxValue == mMainMinValue || h == 0) {
            return mMainMinValue;
        }
        float frac = (y - mMainRect.top) / h;
        if (isInvertedCoordinate()) {
            frac = 1f - frac;
        }
        if (isLogCoordinate()) {
            double lmax = Math.log10(mMainMaxValue);
            double lmin = Math.log10(mMainMinValue);
            double lv = lmax - frac * (lmax - lmin);
            return (float) Math.pow(10, lv);
        }
        return mMainMaxValue - frac * (mMainMaxValue - mMainMinValue);
    }

    public float xFromValue(float value) {
        if (mItemCount < 2) {
            return value;
        }
        KLineEntity firstItem = getItem(0);
        KLineEntity lastItem = getItem(mItemCount - 1);
        float scale = (float)(lastItem.id - firstItem.id) / (configManager.itemWidth * (mItemCount - 1));
        // Base scroll-space coordinate (same space as getItemMiddleScrollX)
        float scrollX = (float)(value - firstItem.id) / scale + configManager.itemWidth / 2.0f;
        // Convert scroll-space to view-space, honoring scroll and horizontal zoom
        return scrollXtoViewX(scrollX);
    }

    public float valueFromX(float x) {
        if (mItemCount < 2) {
            return x;
        }
        KLineEntity firstItem = getItem(0);
        KLineEntity lastItem = getItem(mItemCount - 1);
        float scale = (float)(lastItem.id - firstItem.id) / (configManager.itemWidth * (mItemCount - 1));
        // Invert scrollXtoViewX to recover scroll-space from view-space
        float scrollX = x / mScaleX + mScrollX;
        float value = scale * (scrollX - configManager.itemWidth / 2.0f) + (float)firstItem.id;
        return value;
    }

    public HTPoint valuePointFromViewPoint(HTPoint point) {
        return new HTPoint(valueFromX(point.x), valueFromY(point.y));
    }

    public HTPoint viewPointFromValuePoint(HTPoint point) {
        return new HTPoint(xFromValue(point.x), yFromValue(point.y));
    }

    public float getMainBottom() {
        return mMainRect.bottom;
    }

    public float getVolY(float value) {
        return (mVolMaxValue - value) * mVolScaleY + mVolRect.top;
    }

    public float getChildY(float value) {
        return (mChildMaxValue - value) * mChildScaleY + mChildRect.top;
    }

    /**
     * 解决text居中的问题
     */
    public float fixTextY(float y) {
        Paint.FontMetrics fontMetrics = mTextPaint.getFontMetrics();
        return y + fontMetrics.descent - fontMetrics.ascent;
    }

    /**
     * 解决text居中的问题
     */
    public float fixTextY1(float y) {
        Paint.FontMetrics fontMetrics = mTextPaint.getFontMetrics();
        return (y + (fontMetrics.descent - fontMetrics.ascent) / 2 - fontMetrics.descent);
    }

    /**
     * 画表格
     *
     * @param canvas
     */
    private void drawGird(Canvas canvas) {
        if (mMainRect == null) {
            return;
        }

        // Grid color = Y-axis price text color, but with a very low opacity so it is
        // barely noticeable behind the candles.
        int textColor = mTextPaint.getColor();
        int gridColor = Color.argb(
                (int) (0.08f * 255),
                Color.red(textColor),
                Color.green(textColor),
                Color.blue(textColor)
        );
        mBackgroundGridPaint.setColor(gridColor);

        // Horizontal lines aligned with the Y-axis price labels (mGridRows + 1 values).
        float rowSpace = mMainRect.height() / mGridRows;
        for (int i = 0; i <= mGridRows; i++) {
            float y = rowSpace * i + mMainRect.top;
            canvas.drawLine(0, y, mWidth, y, mBackgroundGridPaint);
        }

        // Vertical lines: split the width into 5 regions with 4 lines.
        final int verticalRegions = 5;
        float columnSpace = mWidth / (float) verticalRegions;
        float bottom = getChildAreaBottom();
        for (int i = 1; i < verticalRegions; i++) {
            float x = columnSpace * i;
            canvas.drawLine(x, mMainRect.top, x, bottom, mBackgroundGridPaint);
        }
    }

    private void animateClosePriceTo(float newPrice) {
        if (Float.isNaN(mDisplayedClosePrice)) {
            mDisplayedClosePrice = newPrice;
            mClosePriceAnimationTarget = newPrice;
            return;
        }
        // Only start a new animation when the actual target price changes,
        // not on every onDraw triggered by the animation's own invalidate().
        if (!Float.isNaN(mClosePriceAnimationTarget) && Math.abs(mClosePriceAnimationTarget - newPrice) < 0.000001f) {
            return;
        }
        mClosePriceAnimationTarget = newPrice;
        if (mClosePriceAnimator != null) {
            mClosePriceAnimator.cancel();
        }
        mClosePriceAnimator = ValueAnimator.ofFloat(mDisplayedClosePrice, newPrice);
        mClosePriceAnimator.setDuration(350);
        mClosePriceAnimator.setInterpolator(new DecelerateInterpolator(2f));
        mClosePriceAnimator.addUpdateListener(new ValueAnimator.AnimatorUpdateListener() {
            @Override
            public void onAnimationUpdate(ValueAnimator animation) {
                mDisplayedClosePrice = (float) animation.getAnimatedValue();
                invalidate();
            }
        });
        mClosePriceAnimator.start();
    }

    private void drawClosePriceLine(Canvas canvas) {
        if (mItemCount <= 0) {
            mClosePriceCenterPillRect.setEmpty();
            return;
        }
        float paddingRight = this.configManager.paddingRight;
        IKLine point = (IKLine) getItem(mItemCount - 1);
        float price = point.getClosePrice();
        animateClosePriceTo(price);
        float animatedPrice = Float.isNaN(mDisplayedClosePrice) ? price : mDisplayedClosePrice;
        String text = safeText(mainDraw.getValueFormatter().format(animatedPrice));
        float width = calculateWidth(text);
        Paint.FontMetrics fm = mTextPaint.getFontMetrics();
        float height = fm.descent - fm.ascent;
        float y = yFromValue(animatedPrice);
        float x = scrollXtoViewX(getItemMiddleScrollX(mItemCount - 1) + mPointWidth * 0.5f);



        if (x > mWidth - width) {
            mClosePriceLinePaint.setColor(configManager.closePriceCenterSeparatorColor);
            mClosePriceTrianglePaint.setColor(configManager.closePriceCenterTriangleColor);
            float paddingX = 20;
            float paddingY = 14;
            y = Math.max(mMainRect.top + height / 2 + paddingY, y);
            y = Math.min(getMainBottom() - height / 2 - paddingY, y);

            float triangleWidth = 14;
            float triangleHeight = 20;
            float triangleMarginLeft = 10;
            float containerWidth = paddingX * 2 + width + triangleWidth + triangleMarginLeft;

            float marginRight = paddingRight - containerWidth / 2;
            float textX = mWidth - paddingRight - containerWidth / 2 + paddingX;

            RectF rect = new RectF(textX - paddingX, y - height / 2 - paddingY, mWidth - marginRight, y + height / 2 + paddingY);
            // Save the pill rect for tap-to-scroll-to-present detection.
            mClosePriceCenterPillRect.set(rect);
            canvas.drawLine(0, y, mWidth, y, mClosePriceLinePaint);
            float radius = (paddingY * 2 + height) / 2;
            mClosePricePointPaint.setColor(configManager.closePriceCenterBackgroundColor);
            mClosePricePointPaint.setStyle(Paint.Style.FILL);
            canvas.drawRoundRect(rect,radius,radius, mClosePricePointPaint);
            mClosePricePointPaint.setColor(configManager.closePriceCenterBorderColor);
            mClosePricePointPaint.setStyle(Paint.Style.STROKE);
            canvas.drawRoundRect(rect,radius,radius, mClosePricePointPaint);
            mClosePriceRightTextPaint.setColor(configManager.closePriceRightSeparatorColor);
            canvas.drawText(text, textX, fixTextY1(y), mClosePriceRightTextPaint);
            Path path = new Path();
            float triangleMarginTop = (rect.bottom - rect.top - triangleHeight) / 2;
            path.moveTo(rect.right - paddingX - triangleWidth, triangleMarginTop + rect.top);
            path.lineTo(rect.right - paddingX - triangleWidth, rect.bottom - triangleMarginTop);
            path.lineTo(rect.right - paddingX, (rect.bottom - rect.top) / 2 + rect.top);
            path.close();
            canvas.drawPath(path, mClosePriceTrianglePaint);
        } else {
            // Clear the tap target when viewing the present (center pill not shown).
            mClosePriceCenterPillRect.setEmpty();
            mClosePriceLinePaint.setColor(configManager.closePriceRightSeparatorColor);
            mClosePriceRightTextPaint.setColor(configManager.closePriceRightSeparatorColor);

            // --- Dashed line from last candle to right edge ---
            canvas.drawLine(x, y, mWidth, y, mClosePriceLinePaint);

            // --- Countdown string (may be null) ---
            String countdownText = getCandleCountdownString();
            boolean hasCountdown = countdownText != null;
            float countdownWidth = hasCountdown ? mClosePriceRightTextPaint.measureText(countdownText) : 0;

            // --- Pill dimensions ---
            float paddingH = 14;
            float paddingV = 8;
            float spacing = hasCountdown ? 4 : 0;
            float contentWidth = Math.max(width, countdownWidth);
            float pillWidth = contentWidth + paddingH * 2;
            float pillHeight = height + (hasCountdown ? height + spacing : 0) + paddingV * 2;
            float pillX = mWidth - pillWidth;
            float pillY = y - pillHeight / 2;

            // Clamp within main chart area.
            pillY = Math.max(mMainRect.top, Math.min(getMainBottom() - pillHeight, pillY));

            RectF pillRect = new RectF(pillX, pillY, mWidth, pillY + pillHeight);
            float cornerRadius = 10;

            // --- Draw pill background ---
            mClosePricePointPaint.setColor(configManager.closePriceRightBackgroundColor);
            mClosePricePointPaint.setStyle(Paint.Style.FILL);
            canvas.drawRoundRect(pillRect, cornerRadius, cornerRadius, mClosePricePointPaint);

            // --- Draw pill border ---
            mClosePricePointPaint.setColor(Color.argb(90, 255, 255, 255));
            mClosePricePointPaint.setStyle(Paint.Style.STROKE);
            mClosePricePointPaint.setStrokeWidth(2);
            canvas.drawRoundRect(pillRect, cornerRadius, cornerRadius, mClosePricePointPaint);
            mClosePricePointPaint.setStrokeWidth(1);

            // --- Draw price text (centered in pill) ---
            float priceX = pillRect.left + (pillWidth - width) / 2;
            float priceTextY = pillRect.top + paddingV + height - fm.descent;
            canvas.drawText(text, priceX, priceTextY, mClosePriceRightTextPaint);

            // --- Draw countdown text below price (centered in pill) ---
            if (hasCountdown) {
                float cdX = pillRect.left + (pillWidth - countdownWidth) / 2;
                float cdY = priceTextY + spacing + height - fm.descent;
                canvas.drawText(countdownText, cdX, cdY, mClosePriceRightTextPaint);
            }

            // --- Real-time bid/ask labels (Bitget style), left of the price pill ---
            drawBidAskLabels(canvas, y, pillRect.left - 12);

            if (isMinute) {
                int lottieWidth = lottieDrawable.getIntrinsicWidth();
                int lottieHeight = lottieDrawable.getIntrinsicHeight();
                canvas.save();
                canvas.translate((int)x - lottieWidth / 2, (int)y - lottieHeight / 2);
                lottieDrawable.draw(canvas);
                canvas.restore();
            }

        }

    }

    /**
     * Draws the real-time Ask (above) and Bid (below) outlined labels on the close-price line,
     * right-aligned against {@code anchorRight}. Enabled via the {@code bidAsk} prop.
     */
    private void drawBidAskLabels(Canvas canvas, float lineY, float anchorRight) {
        if (!configManager.showBidAsk || configManager.bidPrice <= 0 || configManager.askPrice <= 0) {
            return;
        }
        Paint.FontMetrics fm = mClosePriceRightTextPaint.getFontMetrics();
        float textHeight = fm.descent - fm.ascent;
        float paddingH = 12;
        float paddingV = 6;
        float gap = 6; // distance between the price line and each label box
        float cornerRadius = 8;

        for (int i = 0; i < 2; i++) {
            boolean isAsk = i == 0;
            float price = isAsk ? configManager.askPrice : configManager.bidPrice;
            String label = isAsk ? configManager.askText : configManager.bidText;
            int color = isAsk ? configManager.decreaseColor : configManager.increaseColor;
            String title = label + "  " + safeText(mainDraw.getValueFormatter().format(price));
            float textWidth = mClosePriceRightTextPaint.measureText(title);
            float boxWidth = textWidth + paddingH * 2;
            float boxHeight = textHeight + paddingV * 2;
            float boxX = anchorRight - boxWidth;
            // Ask sits above the line, Bid below it.
            float boxY = isAsk ? lineY - gap - boxHeight : lineY + gap;
            RectF rect = new RectF(boxX, boxY, boxX + boxWidth, boxY + boxHeight);

            mClosePricePointPaint.setColor(configManager.closePriceRightBackgroundColor);
            mClosePricePointPaint.setStyle(Paint.Style.FILL);
            canvas.drawRoundRect(rect, cornerRadius, cornerRadius, mClosePricePointPaint);

            mClosePricePointPaint.setColor(color);
            mClosePricePointPaint.setStyle(Paint.Style.STROKE);
            mClosePricePointPaint.setStrokeWidth(2);
            canvas.drawRoundRect(rect, cornerRadius, cornerRadius, mClosePricePointPaint);
            mClosePricePointPaint.setStrokeWidth(1);

            int savedColor = mClosePriceRightTextPaint.getColor();
            mClosePriceRightTextPaint.setColor(color);
            canvas.drawText(title, boxX + paddingH, rect.top + paddingV + textHeight - fm.descent, mClosePriceRightTextPaint);
            mClosePriceRightTextPaint.setColor(savedColor);
        }
    }

    /**
     * Returns the countdown string for the current candle, or null if not applicable.
     */
    private String getCandleCountdownString() {
        if (!configManager.showCandleCountdown || configManager.candleIntervalMs <= 0 || mItemCount <= 0) {
            return null;
        }
        if (mStopIndex < mItemCount - 1) {
            return null;
        }

        startCandleCountdownTimer();

        KLineEntity lastEntity = getItem(mItemCount - 1);
        long intervalMs = configManager.candleIntervalMs;
        long candleOpenMs = Math.round(lastEntity.id < 9_999_999_999L ? lastEntity.id * 1000.0 : lastEntity.id);
        long nowMs = System.currentTimeMillis();

        // Compute when the current candle closes. We anchor on the candle's real open time
        // (already aligned by the data source, e.g. UTC vs UTC+8 / Monday-vs-Sunday week start),
        // rather than re-deriving boundaries from the Unix epoch (which would snap weekly candles
        // to Thursdays). Monthly periods use calendar math; weekStartDay is only a fallback for
        // when no usable open time is available.
        long monthThresholdMs = 27L * 86_400_000L; // anything longer than ~27 days is monthly
        long candleCloseMs;
        if (intervalMs > monthThresholdMs) {
            candleCloseMs = nextMonthCloseMs(candleOpenMs > 0 ? candleOpenMs : nowMs);
        } else if (candleOpenMs > 0) {
            candleCloseMs = candleOpenMs + intervalMs;
        } else {
            // No reliable open time to anchor on.
            candleCloseMs = fallbackCloseMs(nowMs, intervalMs);
        }
        long remainingMs = candleCloseMs - nowMs;
        if (remainingMs <= 0) return null;
        long remaining = remainingMs / 1000L;

        // Format based on the actual remaining time, not the selected interval.
        // - >= 1 day left  -> "DD:HH"
        // - < 1 hour left  -> "MM:SS"
        // - otherwise      -> "HH:MM:SS"
        if (remaining >= 86_400L) {
            int days = (int) (remaining / 86_400L);
            int hours = (int) ((remaining % 86_400L) / 3600);
            return String.format("%02dD:%02dH", days, hours);
        } else if (remaining < 3600) {
            return String.format("%02d:%02d", (int)(remaining / 60), (int)(remaining % 60));
        } else {
            return String.format("%02d:%02d:%02d", (int)(remaining / 3600), (int)((remaining % 3600) / 60), (int)(remaining % 60));
        }
    }

    /**
     * First day of the calendar month following {@code openMs} (UTC), preserving the open's
     * time-of-day. Adding a calendar month handles 28-31 day months and works for both UTC- and
     * UTC+8-aligned monthly opens (e.g. "1st 00:00 UTC" or "last-day 16:00 UTC").
     */
    private long nextMonthCloseMs(long openMs) {
        java.util.Calendar cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"));
        cal.setTimeInMillis(openMs);
        cal.add(java.util.Calendar.MONTH, 1);
        return cal.getTimeInMillis();
    }

    /**
     * Fallback close time when no candle open is available to anchor on. Weekly intervals use the
     * configured {@code weekStartDay} (0=Sunday … 6=Saturday); other intervals fall back to
     * epoch-aligned period boundaries.
     */
    private long fallbackCloseMs(long nowMs, long intervalMs) {
        long dayMs = 86_400_000L;
        long weekMs = 7L * dayMs;
        if (intervalMs == weekMs) {
            long daysSinceEpoch = nowMs / dayMs;
            // Unix epoch (1970-01-01) was a Thursday → weekday index 4 with Sunday=0.
            int weekdayNow = (int) ((daysSinceEpoch + 4) % 7);
            int weekStart = ((weekdayNow - configManager.weekStartDay) % 7 + 7) % 7;
            long weekStartMs = (daysSinceEpoch - weekStart) * dayMs;
            return weekStartMs + weekMs;
        }
        return (nowMs / intervalMs) * intervalMs + intervalMs;
    }

    /**
     * Draws the remaining time until the current candle closes.
     * Now handled inside drawClosePriceLine as a combined pill when the right-side label is visible.
     * This method only draws the standalone countdown when the center pill is shown.
     */
    private void drawCandleCountdown(Canvas canvas) {
        if (mItemCount <= 0) {
            stopCandleCountdownTimer();
            return;
        }

        // Check if center pill is showing (countdown already in the right pill otherwise).
        float animatedPrice = Float.isNaN(mDisplayedClosePrice) ? ((IKLine) getItem(mItemCount - 1)).getClosePrice() : mDisplayedClosePrice;
        String priceText = safeText(mainDraw.getValueFormatter().format(animatedPrice));
        float priceWidth = calculateWidth(priceText);
        float xPos = scrollXtoViewX(getItemMiddleScrollX(mItemCount - 1) + mPointWidth * 0.5f);
        boolean isCenterPill = xPos > mWidth - priceWidth;
        if (!isCenterPill) {
            // Right pill handles the countdown already.
            return;
        }

        String countdownTitle = getCandleCountdownString();
        if (countdownTitle == null) {
            stopCandleCountdownTimer();
            return;
        }

        float savedTextSize = mTextPaint.getTextSize();
        mTextPaint.setTextSize(configManager.rightTextFontSize);

        float y = yFromValue(animatedPrice);
        Paint.FontMetrics fm = mTextPaint.getFontMetrics();
        float textHeight = fm.descent - fm.ascent;
        float countdownY = y + textHeight / 2;
        float textWidth = mTextPaint.measureText(countdownTitle);
        float countdownX = mWidth - textWidth;

        if (countdownY + textHeight > mMainRect.bottom + textHeight + 10) {
            mTextPaint.setTextSize(savedTextSize);
            return;
        }

        mClosePricePointPaint.setColor(configManager.closePriceRightBackgroundColor);
        mClosePricePointPaint.setStyle(Paint.Style.FILL);
        canvas.drawRect(countdownX, countdownY, mWidth, countdownY + textHeight, mClosePricePointPaint);

        mClosePriceRightTextPaint.setTextSize(configManager.rightTextFontSize);
        canvas.drawText(countdownTitle, countdownX, countdownY + textHeight - fm.descent, mClosePriceRightTextPaint);

        mTextPaint.setTextSize(savedTextSize);
    }

    /** Starts the 1-second countdown timer if not already running. */
    private void startCandleCountdownTimer() {
        if (mCountdownHandler == null) {
            mCountdownHandler = new android.os.Handler(android.os.Looper.getMainLooper());
        }
        if (mCountdownRunnable == null) {
            mCountdownRunnable = new Runnable() {
                @Override
                public void run() {
                    if (configManager != null && configManager.showCandleCountdown && configManager.candleIntervalMs > 0) {
                        invalidate();
                        mCountdownHandler.postDelayed(this, 1000);
                    }
                }
            };
            mCountdownHandler.postDelayed(mCountdownRunnable, 1000);
        }
    }

    /** Stops the countdown timer. */
    private void stopCandleCountdownTimer() {
        if (mCountdownHandler != null && mCountdownRunnable != null) {
            mCountdownHandler.removeCallbacks(mCountdownRunnable);
            mCountdownRunnable = null;
        }
    }

    /**
     * 画k线图
     *
     * @param canvas
     */
    private void drawK(Canvas canvas) {
        //保存之前的平移，缩放
        canvas.save();
        canvas.translate(-mScrollX * mScaleX, 0);
        canvas.scale(mScaleX, 1);
        mainDraw.drawMinuteMinute(mTopPadding, mStartIndex, getMainBottom(), mStopIndex, canvas, this);
        for (int i = mStartIndex; i <= mStopIndex; i++) {
            if (i < 0 || i >= configManager.modelArray.size()) {
                continue;
            }
            Object currentPoint = getItem(i);
            float currentPointX = getItemMiddleScrollX(i);
            Object lastPoint = i == 0 ? currentPoint : getItem(i - 1);
            float lastX = i == 0 ? currentPointX : getItemMiddleScrollX(i - 1);
            if (mMainDraw != null) {
                mMainDraw.drawTranslated(lastPoint, currentPoint, lastX, currentPointX, canvas, this, i);
            }
            if (mVolDraw != null && (configManager == null || configManager.showVolume)) {
                mVolDraw.drawTranslated(lastPoint, currentPoint, lastX, currentPointX, canvas, this, i);
            }
            // Legacy single sub-panel (multi-panel is drawn in its own loop below).
            if (!isMultiPanel() && mChildDraw != null) {
                mChildDraw.drawTranslated(lastPoint, currentPoint, lastX, currentPointX, canvas, this, i);
            }
        }

        // Ichimoku future kumo: continues past the newest candle into the
        // right-side overscroll space, but only when that edge is on screen.
        if (mStopIndex == mItemCount - 1 && mainDraw != null) {
            mainDraw.drawIchiFuture(canvas, this);
        }

        // Native N7: draw each stacked sub-panel in its own rect. Rebinding the
        // child fields per panel lets the existing draw code scale correctly.
        if (isMultiPanel()) {
            for (int p = 0; p < mActiveChildDraws.size(); p++) {
                setChildPanelContext(p);
                for (int i = mStartIndex; i <= mStopIndex; i++) {
                    if (i < 0 || i >= configManager.modelArray.size()) {
                        continue;
                    }
                    Object currentPoint = getItem(i);
                    float currentPointX = getItemMiddleScrollX(i);
                    Object lastPoint = i == 0 ? currentPoint : getItem(i - 1);
                    float lastX = i == 0 ? currentPointX : getItemMiddleScrollX(i - 1);
                    mChildDraw.drawTranslated(lastPoint, currentPoint, lastX, currentPointX, canvas, this, i);
                }
            }
        }

        //还原 平移缩放
        canvas.restore();
    }

    /**
     * 计算文本长度
     *
     * @return
     */
    private int calculateWidth(String text) {
        Rect rect = new Rect();
        if (text == null) {
            return 0;
        }
        mTextPaint.getTextBounds(text, 0, text.length(), rect);
        return rect.width() + 5;
    }

    /**
     * 计算文本长度
     *
     * @return
     */
    private Rect calculateMaxMin(String text) {
        Rect rect = new Rect();
        if (text == null) {
            return rect;
        }
        mMaxMinPaint.getTextBounds(text, 0, text.length(), rect);
        return rect;
    }

    private static String safeText(String text) {
        return text == null ? "" : text;
    }

    /**
     * 画文字
     *
     * @param canvas
     */
    private void drawText(Canvas canvas) {
        Paint.FontMetrics fm = mTextPaint.getFontMetrics();
        float textHeight = fm.descent - fm.ascent;
        float baseLine = (textHeight - fm.bottom - fm.top) / 2;
        //--------------画上方k线图的值-------------
        if (mMainDraw != null) {
//            canvas.drawText(formatValue(mMainMaxValue), mWidth - calculateWidth(formatValue(mMainMaxValue)), baseLine + mMainRect.top, mTextPaint);
//            canvas.drawText(formatValue(mMainMinValue), mWidth - calculateWidth(formatValue(mMainMinValue)), mMainRect.bottom - textHeight + baseLine, mTextPaint);
            float rowSpace = mMainRect.height() / mGridRows;
            // Native N2: derive each label's price from its pixel via valueFromY so
            // the labels follow the active coordinate mapping (log / inverted).
            boolean pct = configManager != null && "percentage".equals(configManager.coordinateType);
            float pctBase = 0f;
            if (pct) {
                KLineEntity first = mItemCount > 0 ? getItem(0) : null;
                pctBase = first != null ? first.getOpenPrice() : 0f;
                if (pctBase == 0 && configManager != null) {
                    pctBase = configManager.percentageBase;
                }
            }
            for (int i = 0; i < mGridRows + 1; i++) {
                float y = rowSpace * i + mMainRect.top;
                float price = valueFromY(y);
                String text;
                if (pct && pctBase != 0) {
                    text = safeText(String.format("%.2f%%", (price / pctBase - 1f) * 100f));
                } else {
                    text = safeText(formatValue(price));
                }
                float ty = fixTextY1(y);
                canvas.drawText(text, mWidth - calculateWidth(text), ty, mTextPaint);
            }
        }
        //--------------画中间子图的值-------------
        if (mVolDraw != null && (configManager == null || configManager.showVolume)) {
            IValueFormatter formatter = mVolDraw.getValueFormatter();
            if (formatter instanceof ValueFormatter) {
                ValueFormatter valueFormatter = (ValueFormatter)formatter;
                String formatValue = safeText(valueFormatter.formatVolume(mVolMaxValue));
                canvas.drawText(formatValue,
                        mWidth - calculateWidth(formatValue), mVolRect.top + baseLine, mTextPaint);
            }
            /*canvas.drawText(mVolDraw.getValueFormatter().format(mVolMinValue),
                    mWidth - calculateWidth(formatValue(mVolMinValue)), mVolRect.bottom, mTextPaint);*/
        }
        //--------------画下方子图的值-------------
        if (isMultiPanel()) {
            // Native N7: each stacked panel's max value at its own top edge.
            for (int p = 0; p < mActiveChildDraws.size(); p++) {
                IChartDraw d = mActiveChildDraws.get(p);
                IValueFormatter formatter = d.getValueFormatter();
                if (formatter instanceof ValueFormatter) {
                    String formatValue = safeText(((ValueFormatter) formatter).format(mChildMaxValues[p]));
                    canvas.drawText(formatValue,
                            mWidth - calculateWidth(formatValue),
                            mChildRects.get(p).top + baseLine, mTextPaint);
                }
            }
        } else if (mChildDraw != null) {
            IValueFormatter formatter = mChildDraw.getValueFormatter();
            if (formatter instanceof ValueFormatter) {
                ValueFormatter valueFormatter = (ValueFormatter)formatter;
                String formatValue = safeText(valueFormatter.format(mChildMaxValue));
                canvas.drawText(formatValue,
                        mWidth - calculateWidth(formatValue), mVolRect.bottom + baseLine, mTextPaint);
            }
            /*canvas.drawText(mChildDraw.getValueFormatter().format(mChildMinValue),
                    mWidth - calculateWidth(formatValue(mChildMinValue)), mChildRect.bottom, mTextPaint);*/
        }
        //--------------画时间---------------------
        float columnSpace = mWidth / mGridColumns;
        float y = fixTextY1((float) (getChildAreaBottom() + mBottomPadding / 2.0));

        float startX = getItemMiddleScrollX(mStartIndex) - mPointWidth / 2;
        float stopX = getItemMiddleScrollX(mStopIndex) + mPointWidth / 2;

        int timeframe = configManager != null ? configManager.time : 0;
        for (int i = 1; i < mGridColumns; i++) {
            float scrollX = viewXToScrollX(columnSpace * i);
            if (scrollX >= startX && scrollX <= stopX) {
                int index = indexFromScrollX(scrollX);
                KLineEntity entity = getItem(index);
                String text = DateUtil.formatByTimeframe((long) entity.id, timeframe);
                canvas.drawText(text, columnSpace * i - mTextPaint.measureText(text) / 2, y, mTextPaint);
            }
        }

        if (mStartIndex < 0 || mStopIndex <= 0) {
            return;
        }

        float scrollX = viewXToScrollX(0);
        if (scrollX >= startX && scrollX <= stopX) {
            KLineEntity entity = getItem(mStartIndex);
            String text = DateUtil.formatByTimeframe((long) entity.id, timeframe);
            canvas.drawText(text, -mTextPaint.measureText(text) / 2, y, mTextPaint);
        }
        scrollX = viewXToScrollX(mWidth);
        if (scrollX >= startX && scrollX <= stopX) {
            KLineEntity entity = getItem(mStopIndex);
            String text = DateUtil.formatByTimeframe((long) entity.id, timeframe);
            canvas.drawText(text, mWidth - mTextPaint.measureText(text) / 2, y, mTextPaint);
        }

    }

    private void drawSelector(Canvas canvas) {
        if (!isLongPress) {
            mSelectedPricePillRect.setEmpty();
            mSelectedPriceValue = Float.NaN;
            return;
        }
        Paint.FontMetrics fm = mTextPaint.getFontMetrics();
        float textHeight = fm.descent - fm.ascent;
        float baseLine = (textHeight - fm.bottom - fm.top) / 2;

        mSelectPointPaint.setColor(configManager.panelBackgroundColor);
        // 画Y值
        IKLine point = (IKLine) getItem(mSelectedIndex);
        float w1 = ViewUtil.Dp2Px(getContext(), 5);
        float w2 = ViewUtil.Dp2Px(getContext(), 3);
        float r = textHeight / 2 + w2;
        float triangleWidth = 10;
        float y;
        if (Float.isNaN(mSelectedY)) {
            y = yFromValue(point.getClosePrice());
        } else {
            // Clamp to main chart area to keep the right-side label a "price" value.
            y = Math.max(mMainRect.top, Math.min(mMainRect.bottom, mSelectedY));
        }
        float x;
        float startX;
        float endX;
        float selectedValue = valueFromY(y);
        String text = safeText(formatValue(selectedValue));
        float textWidth = mTextPaint.measureText(text);

        // Hover price pill: [ + ] | price (top) + change % (below).
        mSelectedPriceValue = selectedValue;

        boolean showPlus = configManager == null || configManager.showPlusIcon;

        // Change % is the crosshair price relative to the latest live price, so it updates as the
        // finger moves (both vertically and across candles).
        float liveClose = mItemCount > 0 ? ((IKLine) getItem(mItemCount - 1)).getClosePrice() : 0f;
        float changePct = liveClose != 0 ? (selectedValue - liveClose) / liveClose * 100f : 0f;
        String changeText = (changePct >= 0 ? "+" : "") + String.format(java.util.Locale.US, "%.2f", changePct) + "%";

        // Slightly smaller text for the pill (restored after drawing the pill text).
        float pillOldTextSize = mMaxMinPaint.getTextSize();
        mMaxMinPaint.setTextSize(pillOldTextSize * 0.85f);

        Paint.FontMetrics mm = mMaxMinPaint.getFontMetrics();
        float lineH = mm.descent - mm.ascent;
        float priceWidth = mMaxMinPaint.measureText(text);
        float changeWidth = mMaxMinPaint.measureText(changeText);
        float contentTextWidth = Math.max(priceWidth, changeWidth);

        float innerPadV = ViewUtil.Dp2Px(getContext(), 3);
        float lineGap = ViewUtil.Dp2Px(getContext(), 1);
        float textPaddingH = ViewUtil.Dp2Px(getContext(), 6);
        float pillHeight = lineH * 2f + lineGap + innerPadV * 2f;

        // Icon area hugs the (small) circle with minimal padding instead of being a full square.
        float circleRadius = showPlus ? (pillHeight - ViewUtil.Dp2Px(getContext(), 8)) / 2f * 0.5f : 0f;
        float iconLeftPad = ViewUtil.Dp2Px(getContext(), 5);
        float iconRightPad = ViewUtil.Dp2Px(getContext(), 4);
        float iconAreaWidth = showPlus ? (iconLeftPad + circleRadius * 2f + iconRightPad) : 0f;
        float dividerWidth = showPlus ? 1f : 0f;
        float pillWidth = iconAreaWidth + dividerWidth + contentTextWidth + textPaddingH * 2f;

        float rightEdge = mWidth;
        float marginY = 2f;
        float top = Math.max(marginY, Math.min(getHeight() - marginY - pillHeight, y - pillHeight / 2f));
        float bottom = top + pillHeight;
        float left = rightEdge - pillWidth;

        mSelectedPricePillRect.set(left, top, rightEdge, bottom);
        startX = 0;
        endX = Math.max(0, left);

        // White pill background + subtle border.
        RectF whitePillRect = new RectF(left, top, rightEdge, bottom);
        Paint paint = mSelectPointPaint;
        paint.setAntiAlias(true);
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(Color.WHITE);
        float radius = pillHeight / 2f;
        canvas.drawRoundRect(whitePillRect, radius, radius, paint);

        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(1f);
        paint.setColor(Color.argb(255, 217, 217, 217)); // light gray
        canvas.drawRoundRect(whitePillRect, radius, radius, paint);

        float dividerX = left + iconAreaWidth;
        if (showPlus) {
            // "+" button: black circle with a white border ring + white plus glyph.
            float iconCx = left + iconLeftPad + circleRadius;
            float iconCy = (top + bottom) / 2f;
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(Color.BLACK);
            canvas.drawCircle(iconCx, iconCy, circleRadius, paint);

            // White border ring around the black circle.
            paint.setStyle(Paint.Style.STROKE);
            paint.setColor(Color.WHITE);
            paint.setStrokeWidth(Math.max(2f, circleRadius * 0.16f));
            canvas.drawCircle(iconCx, iconCy, circleRadius, paint);

            paint.setColor(Color.WHITE);
            paint.setStrokeWidth(Math.max(2f, circleRadius * 0.22f));
            paint.setStrokeCap(Paint.Cap.ROUND);
            float plusLen = circleRadius;
            canvas.drawLine(iconCx - plusLen / 2f, iconCy, iconCx + plusLen / 2f, iconCy, paint);
            canvas.drawLine(iconCx, iconCy - plusLen / 2f, iconCx, iconCy + plusLen / 2f, paint);

            // Vertical divider between the icon and the text.
            paint.setColor(Color.argb(255, 217, 217, 217));
            paint.setStrokeWidth(dividerWidth);
            paint.setStrokeCap(Paint.Cap.BUTT);
            canvas.drawLine(dividerX, top + ViewUtil.Dp2Px(getContext(), 6), dividerX, bottom - ViewUtil.Dp2Px(getContext(), 6), paint);
        }

        // Price (top, black) + change % (below, colored), left-aligned after the divider.
        int oldTextColor = mMaxMinPaint.getColor();
        Paint.Align oldAlign = mMaxMinPaint.getTextAlign();
        mMaxMinPaint.setTextAlign(Paint.Align.LEFT);
        float textLeft = (showPlus ? dividerX : left) + textPaddingH;
        float priceBaseY = top + innerPadV - mm.ascent;
        float changeBaseY = priceBaseY + lineH + lineGap;
        mMaxMinPaint.setColor(Color.BLACK);
        canvas.drawText(text, textLeft, priceBaseY, mMaxMinPaint);
        canvas.drawText(changeText, textLeft, changeBaseY, mMaxMinPaint);
        mMaxMinPaint.setColor(oldTextColor);
        mMaxMinPaint.setTextAlign(oldAlign);
        mMaxMinPaint.setTextSize(pillOldTextSize);

        // --- Crosshair lines (thin, dashed) ---
        float pointX = scrollXtoViewX(getItemMiddleScrollX(mSelectedIndex));
        mSelectedXLinePaint.setColor(configManager.candleTextColor);
        mSelectedXLinePaint.setStrokeWidth(Math.max(1f, ViewUtil.Dp2Px(getContext(), 0.5f)));
        mSelectedXLinePaint.setPathEffect(new DashPathEffect(new float[]{6, 6}, 0));
        // Horizontal line up to the pill's left edge (so it doesn't cross the white pill).
        canvas.drawLine(startX, y, endX, y, mSelectedXLinePaint);
        // Vertical line through the main + sub chart areas.
        canvas.drawLine(pointX, mMainRect.top, pointX, getChildAreaBottom(), mSelectedXLinePaint);

        // --- Selected point dot (small, ~25% of the original size) ---
        mSelectCenterPaint.setColor(configManager.selectedPointContentColor);
        mSelectCenterBackgroundPaint.setColor(configManager.selectedPointContainerColor);
        float dotOuter = Math.max(ViewUtil.Dp2Px(getContext(), 2), configManager.candleWidth * mScaleX * 0.25f);
        float dotInner = dotOuter * 0.6f;
        RectF backgroundRect = new RectF(pointX - dotOuter, y - dotOuter, pointX + dotOuter, y + dotOuter);
        RectF rect = new RectF(pointX - dotInner, y - dotInner, pointX + dotInner, y + dotInner);
        canvas.drawOval(backgroundRect, mSelectCenterBackgroundPaint);
        canvas.drawOval(rect, mSelectCenterPaint);



        // 画X值
        String date = safeText(DateUtil.formatByTimeframe((long) getItem(mSelectedIndex).id, configManager != null ? configManager.time : 0));
        textWidth = mMaxMinPaint.measureText(date);
        r = textHeight / 2;
        x = scrollXtoViewX(getItemMiddleScrollX(mSelectedIndex));
        y = getChildAreaBottom();

        if (x < textWidth + 2 * w1) {
            x = 1 + textWidth / 2 + w1;
        } else if (mWidth - x < textWidth + 2 * w1) {
            x = mWidth - 1 - textWidth / 2 - w1;
        }

        // Bottom active date (hover mode): pill background (no border), compact height to match x-axis labels.
        float xPaddingH = ViewUtil.Dp2Px(getContext(), 6);
        float xPaddingV = ViewUtil.Dp2Px(getContext(), 3);
        float centerY = y + (mBottomPadding / 2f);
        float rectTop = centerY - (textHeight / 2f + xPaddingV);
        float rectBottom = centerY + (textHeight / 2f + xPaddingV);
        // Clamp inside the bottom time area.
        rectTop = Math.max(y, rectTop);
        rectBottom = Math.min(y + mBottomPadding, rectBottom);

        RectF timeRect = new RectF(
                x - textWidth / 2f - xPaddingH,
                rectTop,
                x + textWidth / 2f + xPaddingH,
                rectBottom
        );
        float cornerRadius = ViewUtil.Dp2Px(getContext(), 5);
        mSelectPointPaint.setAntiAlias(true);
        mSelectPointPaint.setStyle(Paint.Style.FILL);
        // Match the right-side hover price pill background.
        mSelectPointPaint.setColor(Color.WHITE);
        canvas.drawRoundRect(timeRect, cornerRadius, cornerRadius, mSelectPointPaint);

        // Match the pill text color.
        int oldColor = mMaxMinPaint.getColor();
        mMaxMinPaint.setColor(Color.BLACK);
        canvas.drawText(date, x - textWidth / 2, fixTextY1(centerY), mMaxMinPaint);
        mMaxMinPaint.setColor(oldColor);
        mainDraw.drawSelector(this, canvas);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        // If the selector is visible and the user taps the hover price pill,
        // trigger `onNewOrder(price)` and keep the selector visible.
        if ((event.getAction() & MotionEvent.ACTION_MASK) == MotionEvent.ACTION_DOWN && isLongPress) {
            if (!mSelectedPricePillRect.isEmpty() && mSelectedPricePillRect.contains(event.getX(), event.getY())) {
                if (configManager != null && configManager.onNewOrder != null && !Float.isNaN(mSelectedPriceValue)) {
                    configManager.onNewOrder.invoke((double) mSelectedPriceValue);
                }
                return true;
            }
        }
        if (handleRightYAxisScaleTouch(event)) {
            return true;
        }
        return super.onTouchEvent(event);
    }

    @Override
    public boolean onSingleTapUp(MotionEvent e) {
        // If the close price center pill (shown when scrolled left) is tapped, scroll to present.
        if (!mClosePriceCenterPillRect.isEmpty() && mClosePriceCenterPillRect.contains(e.getX(), e.getY())) {
            animateScrollToEnd();
            return true;
        }
        return super.onSingleTapUp(e);
    }

    private ValueAnimator mScrollToEndAnimator;

    private void animateScrollToEnd() {
        if (mScrollToEndAnimator != null) {
            mScrollToEndAnimator.cancel();
        }
        int startX = getScrollOffset();
        int endX = getEndScrollX();
        if (startX == endX) return;

        mScrollToEndAnimator = ValueAnimator.ofInt(startX, endX);
        mScrollToEndAnimator.setDuration(300);
        mScrollToEndAnimator.setInterpolator(new android.view.animation.DecelerateInterpolator());
        mScrollToEndAnimator.addUpdateListener(animation -> {
            int value = (int) animation.getAnimatedValue();
            setScrollX(value);
        });
        mScrollToEndAnimator.start();
    }

    private boolean isInRightYAxisArea(float x, float y) {
        if (mMainRect == null) {
            return false;
        }
        // Only allow scaling in the main chart vertical span (where price axis corresponds to candles).
        if (y < mMainRect.top || y > mMainRect.bottom) {
            return false;
        }
        // Include JS-provided right padding as an additional hit target width.
        float widthPx = ViewUtil.Dp2Px(getContext(), mYAxisGestureWidthDp);
        if (configManager != null) {
            widthPx = Math.max(widthPx, configManager.paddingRight);
        }
        return x >= (mWidth - widthPx);
    }

    @Override
    protected float getYAxisZoomFactor() {
        return mYAxisZoomFactor;
    }

    @Override
    protected void setYAxisZoomFactor(float factor) {
        mYAxisZoomFactor = factor;
        invalidate();
    }

    @Override
    protected boolean isYAxisScaleCandidate() {
        return mIsYAxisScaleCandidate;
    }

    private void startRightYAxisScaling(float startY) {
        mIsYAxisScaling = true;
        mYAxisScaleStartY = startY;
        mYAxisScaleStartFactor = mYAxisZoomFactor;
    }

    private boolean handleRightYAxisScaleTouch(MotionEvent event) {
        if (mItemCount <= 0 || mMainRect == null || mMainRect.height() <= 0) {
            return false;
        }
        // Only single-finger interaction for y-axis scaling.
        if (event.getPointerCount() > 1) {
            if (mIsYAxisScaling) {
                mIsYAxisScaling = false;
            }
            mIsYAxisScaleCandidate = false;
            return false;
        }

        final int action = event.getAction() & MotionEvent.ACTION_MASK;
        switch (action) {
            case MotionEvent.ACTION_DOWN: {
                // Only consider y-axis scaling when touch begins in the right-side y-axis area.
                if (isInRightYAxisArea(event.getX(), event.getY())) {
                    mIsYAxisScaleCandidate = true;
                    mYAxisDownX = event.getX();
                    mYAxisDownY = event.getY();
                    // Prevent long-press selector from activating while finger is on the y-axis.
                    setLongPressEnable(false);
                } else {
                    mIsYAxisScaleCandidate = false;
                    setLongPressEnable(true);
                }
                return false;
            }
            case MotionEvent.ACTION_MOVE: {
                if (!mIsYAxisScaling) {
                    // If we started on the y-axis, decide intent (vertical => scale, horizontal => let scroll handle).
                    if (mIsYAxisScaleCandidate) {
                        float dx = event.getX() - mYAxisDownX;
                        float dy = event.getY() - mYAxisDownY;
                        float slop = ViewUtil.Dp2Px(getContext(), 4);
                        if (Math.abs(dy) > Math.abs(dx) && Math.abs(dy) > slop) {
                            startRightYAxisScaling(mYAxisDownY);
                            // Ensure parent doesn't steal vertical drag while scaling y-axis.
                            getParent().requestDisallowInterceptTouchEvent(true);
                            invalidate();
                            // Continue into scaling branch below by not returning yet.
                        } else {
                            return false;
                        }
                    } else {
                        return false;
                    }
                }
                float dy = event.getY() - mYAxisScaleStartY;
                float denom = Math.max(1f, mMainRect.height() * mYAxisGestureSensitivityFactor);
                float factor = mYAxisScaleStartFactor * (float) Math.exp(dy / denom);
                // Clamp: 1.0 (100% auto-fit) to 5.0 (20% zoom-out)
                mYAxisZoomFactor = Math.max(1.0f, Math.min(5.0f, factor));
                invalidate();
                return true;
            }
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL: {
                if (!mIsYAxisScaling) {
                    mIsYAxisScaleCandidate = false;
                    setLongPressEnable(true);
                    return false;
                }
                mIsYAxisScaling = false;
                mIsYAxisScaleCandidate = false;
                mYAxisScaleStartY = Float.NaN;
                setLongPressEnable(true);
                getParent().requestDisallowInterceptTouchEvent(false);
                invalidate();
                return true;
            }
        }
        return false;
    }

    private void drawMaxMinValue(Canvas canvas, float value, float x, float y) {
        // formatValue lazily creates the default formatter; calling getValueFormatter()
        // directly here NPEs when no draw path has initialized it yet (e.g. percentage
        // coordinate mode skips formatValue in drawText).
        String valueString = safeText(formatValue(value));
        int height = calculateMaxMin(valueString).height();
        y += height / 2;
        String lineString = "---";
        if (x < getWidth() / 2) {
            valueString = lineString + valueString;
        } else {
            valueString = valueString + lineString;
            float width = mMaxMinPaint.measureText(valueString);
            x -= width;
        }
        canvas.drawText(valueString, x, y, mMaxMinPaint);
    }

    /**
     * 画文字
     *
     * @param canvas
     */
    private void drawMaxAndMin(Canvas canvas) {
        if (!isMinute) {
            //绘制最大值和最小值
            float x = scrollXtoViewX(getItemMiddleScrollX(mMainMinIndex));
            float y = yFromValue(mMainLowMinValue);
            drawMaxMinValue(canvas, mMainLowMinValue, x, y);

            x = scrollXtoViewX(getItemMiddleScrollX(mMainMaxIndex));
            y = yFromValue(mMainHighMaxValue);
            drawMaxMinValue(canvas, mMainHighMaxValue, x, y);

        }
    }

    /**
     * 画值
     *
     * @param canvas
     * @param position 显示某个点的值
     */
    private void drawValue(Canvas canvas, int position) {
        Paint.FontMetrics fm = mTextPaint.getFontMetrics();
        float textHeight = fm.descent - fm.ascent;
        float baseLine = (textHeight - fm.bottom - fm.top) / 2;
        float x = 10;
        if (position >= 0 && position < mItemCount) {
            if (mMainDraw != null) {
                float y = textHeight + 15;
                mMainDraw.drawText(canvas, this, position, x, y);
            }
            if (mVolDraw != null && (configManager == null || configManager.showVolume)) {
                // Contiguous stacked panels have no padding gap above VOL, so the
                // legend sits inside the panel top instead of above it.
                float y = isMultiPanel()
                        ? mVolRect.top + textHeight
                        : mVolRect.top - mChildPadding + textHeight;
                mVolDraw.drawText(canvas, this, position, x, y);
            }
            if (isMultiPanel()) {
                // Native N7: each stacked panel's legend at its own top edge.
                for (int p = 0; p < mActiveChildDraws.size(); p++) {
                    setChildPanelContext(p);
                    float y = mChildRects.get(p).top + textHeight;
                    mChildDraw.drawText(canvas, this, position, x, y);
                }
            } else if (mChildDraw != null) {
                float y = mVolRect.bottom + textHeight;
                mChildDraw.drawText(canvas, this, position, x, y);
            }
        }
    }

    public int dp2px(float dp) {
        final float scale = getContext().getResources().getDisplayMetrics().density;
        return (int) (dp * scale + 0.5f);
    }

    public int sp2px(float spValue) {
        final float fontScale = getContext().getResources().getDisplayMetrics().scaledDensity;
        return (int) (spValue * fontScale + 0.5f);
    }

    /**
     * 格式化值
     */
    public String formatValue(float value) {
        if (getValueFormatter() == null) {
            setValueFormatter(new ValueFormatter());
        }
        return getValueFormatter().format(value);
    }

    /**
     * 重新计算并刷新线条
     */
    public void notifyChanged() {
        notifyChangedInternal(true);
    }

    /**
     * Like {@link #notifyChanged()} but lets the vertical min/max rescale animate
     * smoothly instead of snapping. Used when older candles are prepended after
     * onEndReached so the chart height adjusts gradually as the empty left padding
     * is replaced by real candles, rather than jumping to the new range.
     */
    public void notifyChangedAnimated() {
        notifyChangedInternal(false);
    }

    private void notifyChangedInternal(boolean snapScale) {
        if (configManager == null || configManager.modelArray == null) {
            return;
        }
        mItemCount = configManager.modelArray.size();
        mDataLen = mItemCount * mPointWidth;
        if (isShowChild && mChildDrawPosition == -1) {
            mChildDraw = mChildDraws.get(0);
            mChildDrawPosition = 0;
        }
        if (mItemCount != 0) {
            mDataLen = mItemCount * mPointWidth;
            checkAndFixScrollX();
        }
        if (mSelectedIndex >= mItemCount) {
            isLongPress = false;
        }
        // For normal/wholesale updates, force the next calculateValue() to snap.
        // We use a boolean flag rather than resetting animated values to NaN —
        // NaN would cause BigDecimal crashes if onDraw fires before calculateValue()
        // sets real values. When snapScale is false (prepend), leave the flag clear
        // so the min/max lerp smoothly toward the new range.
        // Set explicitly (don't just OR-in) so that when the optionList and modelArray
        // prop updates land in the same frame, the last call wins: an animated prepend
        // update clears a snap requested by a sibling notifyChanged(), and vice versa.
        mForceScaleSnap = snapScale;

        initRect();
        initLottieView();
        invalidate();
    }

    /**
     * MA/BOLL切换及隐藏
     *
     * @param primaryStatus MA/BOLL/NONE
     */
    public void changeMainDrawType(PrimaryStatus primaryStatus) {
        if (mainDraw != null && mainDraw.getPrimaryStatus() != primaryStatus) {
            mainDraw.setPrimaryStatus(primaryStatus);
            // invalidate();
        }
    }

    private void calculateSelectedX(float x) {
        mSelectedIndex = indexFromScrollX(viewXToScrollX(x));
        if (mSelectedIndex < mStartIndex) {
            mSelectedIndex = mStartIndex;
        }
        if (mSelectedIndex > mStopIndex) {
            mSelectedIndex = mStopIndex;
        }
    }

    @Override
    public void onLongPress(MotionEvent e) {
        super.onLongPress(e);
        int lastIndex = mSelectedIndex;
        calculateSelectedX(e.getX());
        mSelectedY = e.getY();
        if (lastIndex != mSelectedIndex) {
            onSelectedChanged(this, getItem(mSelectedIndex), mSelectedIndex);
            // Fire a light haptic whenever the snapped candle changes.
            if (configManager != null && configManager.hapticOnSelection) {
                performHapticFeedback(
                    android.view.HapticFeedbackConstants.CLOCK_TICK,
                    android.view.HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING
                );
            }
        }
        invalidate();
    }

    @Override
    protected void onScrollChanged(int l, int t, int oldl, int oldt) {
        super.onScrollChanged(l, t, oldl, oldt);
    }

    @Override
    protected void onScaleChanged(float scale, float oldScale) {
        checkAndFixScrollX();
        super.onScaleChanged(scale, oldScale);
    }

    /**
     * 计算当前的显示区域
     */
    private void calculateValue() {
        if (!isLongPress()) {
            mSelectedIndex = -1;
        }
        mMainMaxValue = Float.MIN_VALUE;
        mMainMinValue = Float.MAX_VALUE;
        mVolMaxValue = Float.MIN_VALUE;
        mVolMinValue = Float.MAX_VALUE;
        mChildMaxValue = Float.MIN_VALUE;
        mChildMinValue = Float.MAX_VALUE;
        // Native N7: reset per-panel accumulators.
        for (int p = 0; p < mChildMaxValues.length; p++) {
            mChildMaxValues[p] = Float.MIN_VALUE;
            mChildMinValues[p] = Float.MAX_VALUE;
        }
        mStartIndex = Math.min(Math.max(0, indexFromScrollX(viewXToScrollX(0))), mItemCount - 1);
        mStopIndex = Math.max(0, Math.min(indexFromScrollX(viewXToScrollX(mWidth)), mItemCount - 1));
        checkLeftEdge(mStartIndex, mItemCount);
        mMainMaxIndex = mStartIndex;
        mMainMinIndex = mStartIndex;
        mMainHighMaxValue = Float.MIN_VALUE;
        mMainLowMinValue = Float.MAX_VALUE;
        for (int i = mStartIndex; i <= mStopIndex; i++) {
            if (i < 0 || i >= configManager.modelArray.size()) {
                continue;
            }
            IKLine point = (IKLine) getItem(i);
            if (mMainDraw != null) {
                mMainMaxValue = Math.max(mMainMaxValue, mMainDraw.getMaxValue(point));
                mMainMinValue = Math.min(mMainMinValue, mMainDraw.getMinValue(point));
                if (mMainHighMaxValue != Math.max(mMainHighMaxValue, point.getHighPrice())) {
                    mMainHighMaxValue = point.getHighPrice();
                    mMainMaxIndex = i;
                }
                if (mMainLowMinValue != Math.min(mMainLowMinValue, point.getLowPrice())) {
                    mMainLowMinValue = point.getLowPrice();
                    mMainMinIndex = i;
                }
            }
            if (mVolDraw != null && (configManager == null || configManager.showVolume)) {
                mVolMaxValue = Math.max(mVolMaxValue, mVolDraw.getMaxValue(point));
                mVolMinValue = Math.min(mVolMinValue, mVolDraw.getMinValue(point));
                // 成交量最小应该是 0 或者比最小成交量大一点点
                mVolMinValue = mVolMinValue - (mVolMaxValue - mVolMinValue) / 10.0f;
                mVolMinValue = Math.max(0, mVolMinValue);
            }
            if (isMultiPanel()) {
                for (int p = 0; p < mActiveChildDraws.size(); p++) {
                    IChartDraw d = mActiveChildDraws.get(p);
                    // Generic panels read their per-panel subLines by this index.
                    mCurrentGenericIndex = p < mChildGenericIndex.length ? mChildGenericIndex[p] : -1;
                    mChildMaxValues[p] = Math.max(mChildMaxValues[p], d.getMaxValue(point));
                    mChildMinValues[p] = Math.min(mChildMinValues[p], d.getMinValue(point));
                }
            } else if (mChildDraw != null) {
                mChildMaxValue = Math.max(mChildMaxValue, mChildDraw.getMaxValue(point));
                mChildMinValue = Math.min(mChildMinValue, mChildDraw.getMinValue(point));
            }
        }
//        if (mItemCount > 0) {
//            int i = mItemCount - 1;
//            IKLine point = (IKLine)getItem(i);
//            mMainMaxValue = Math.max(mMainMaxValue, mMainDraw.getMaxValue(point));
//            mMainMinValue = Math.min(mMainMinValue, mMainDraw.getMinValue(point));
//            if (mMainHighMaxValue != Math.max(mMainHighMaxValue, point.getHighPrice())) {
//                mMainHighMaxValue = point.getHighPrice();
//                mMainMaxIndex = i;
//            }
//            if (mMainLowMinValue != Math.min(mMainLowMinValue, point.getLowPrice())) {
//                mMainLowMinValue = point.getLowPrice();
//                mMainMinIndex = i;
//            }
//        }

        if (mMainMaxValue != mMainMinValue) {
            // Symmetrize padding around candle high/low so the highest and lowest
            // prices are equally distant from chart edges when indicators (MA/BOLL)
            // extend the range asymmetrically.
            float paddingAbove = mMainMaxValue - mMainHighMaxValue;
            float paddingBelow = mMainLowMinValue - mMainMinValue;
            if (paddingAbove > paddingBelow) {
                mMainMinValue = mMainLowMinValue - paddingAbove;
            } else if (paddingBelow > paddingAbove) {
                mMainMaxValue = mMainHighMaxValue + paddingBelow;
            }
        }

        // Apply persistent y-axis zoom factor (1.0 = auto-fit, >1 = zoomed out).
        if (mYAxisZoomFactor > 1.0f) {
            float center = (mMainMaxValue + mMainMinValue) / 2f;
            float range = (mMainMaxValue - mMainMinValue) * mYAxisZoomFactor;
            mMainMaxValue = center + range / 2f;
            mMainMinValue = center - range / 2f;
        }

        if (Math.abs(mVolMaxValue) < 0.01) {
            mVolMaxValue = 15.00f;
        }

        // big number replace
//        if (Math.abs(mChildMaxValue) < 0.01 && Math.abs(mChildMinValue) < 0.01) {
//            mChildMaxValue = 1f;
//        } else
            if (mChildMaxValue.equals(mChildMinValue)) {
            //当最大值和最小值都相等的时候 分别增大最大值和 减小最小值
            mChildMaxValue += Math.abs(mChildMaxValue * 0.05f);
            mChildMinValue -= Math.abs(mChildMinValue * 0.05f);
            if (mChildMaxValue == 0) {
                mChildMaxValue = 1f;
            }
        }

        if (isWR) {
            mChildMaxValue = 0f;
            if (Math.abs(mChildMinValue) < 0.01)
                mChildMinValue = -10.00f;
        }
        // Animate min/max toward target values for smooth vertical rescaling.
        // Snap on the first frame (no animated value yet) or when a wholesale update
        // requested it via notifyChanged(). Prepends use notifyChangedAnimated(), which
        // leaves mForceScaleSnap clear so the range lerps smoothly to the new min/max.
        boolean snap = Float.isNaN(mAnimatedMainMaxValue) || mForceScaleSnap;
        mForceScaleSnap = false;
        mPrevItemCountForAnim = mItemCount;

        if (snap) {
            mAnimatedMainMaxValue = mMainMaxValue;
            mAnimatedMainMinValue = mMainMinValue;
            mAnimatedVolMaxValue = mVolMaxValue;
            mAnimatedVolMinValue = mVolMinValue;
            mAnimatedChildMaxValue = mChildMaxValue;
            mAnimatedChildMinValue = mChildMinValue;
        } else {
            mAnimatedMainMaxValue += (mMainMaxValue - mAnimatedMainMaxValue) * SCALE_ANIM_LERP;
            mAnimatedMainMinValue += (mMainMinValue - mAnimatedMainMinValue) * SCALE_ANIM_LERP;
            mAnimatedVolMaxValue += (mVolMaxValue - mAnimatedVolMaxValue) * SCALE_ANIM_LERP;
            mAnimatedVolMinValue += (mVolMinValue - mAnimatedVolMinValue) * SCALE_ANIM_LERP;
            mAnimatedChildMaxValue += (mChildMaxValue - mAnimatedChildMaxValue) * SCALE_ANIM_LERP;
            mAnimatedChildMinValue += (mChildMinValue - mAnimatedChildMinValue) * SCALE_ANIM_LERP;
            // Keep redrawing while animating toward target.
            if (Math.abs(mAnimatedMainMaxValue - mMainMaxValue) > 0.0001f
                    || Math.abs(mAnimatedMainMinValue - mMainMinValue) > 0.0001f) {
                invalidate();
            }
        }
        mMainMaxValue = mAnimatedMainMaxValue;
        mMainMinValue = mAnimatedMainMinValue;
        mVolMaxValue = mAnimatedVolMaxValue;
        mVolMinValue = mAnimatedVolMinValue;
        mChildMaxValue = mAnimatedChildMaxValue;
        mChildMinValue = mAnimatedChildMinValue;

        mMainScaleY = mMainRect.height() * 1f / (mMainMaxValue - mMainMinValue);
        mVolScaleY = mVolRect.height() * 1f / (mVolMaxValue - mVolMinValue);
        if (mChildRect != null)
            mChildScaleY = mChildRect.height() * 1f / (mChildMaxValue - mChildMinValue);

        // Native N7: finalize per-panel range + scale (snapped, no animation).
        if (isMultiPanel()) {
            for (int p = 0; p < mActiveChildDraws.size(); p++) {
                float mx = mChildMaxValues[p];
                float mn = mChildMinValues[p];
                if (p < mChildIsWR.length && mChildIsWR[p]) {
                    mx = 0f;
                    if (Math.abs(mn) < 0.01f) {
                        mn = -10f;
                    }
                }
                if (mx == mn) {
                    mx += Math.abs(mx * 0.05f);
                    mn -= Math.abs(mn * 0.05f);
                    if (mx == 0) {
                        mx = 1f;
                    }
                }
                mChildMaxValues[p] = mx;
                mChildMinValues[p] = mn;
                Rect r = p < mChildRects.size() ? mChildRects.get(p) : null;
                mChildScaleYs[p] = (r != null && mx != mn)
                        ? r.height() * 1f / (mx - mn)
                        : 1f;
            }
        }
        if (mAnimator.isRunning()) {
            float value = (float) mAnimator.getAnimatedValue();
            mStopIndex = mStartIndex + Math.round(value * (mStopIndex - mStartIndex));
        }
    }

    @Override
    public int getMinScrollX() {
        return (int) -(mWidth * 0.5f / mScaleX);
    }

    public int getMaxScrollX() {
        // The maximum the user can scroll toward the present: far enough that only
        // `minVisibleCandles` candles remain on screen (Bitget-style overscroll). The legacy
        // `rightPaddingCandles` tail acts as a floor so small datasets keep their old behavior.
        // This extra space is reachable by scrolling but is NOT shown at rest — see
        // getEndScrollX() for the resting "end" position.
        float rightTail = configManager.rightPaddingCandles * mPointWidth;
        int paddedMax = (int) Math.max((mDataLen + rightTail - (mWidth - configManager.paddingRight) / mScaleX), 0);
        int overscrollMax = (int) (mDataLen - configManager.minVisibleCandles * mPointWidth);
        return Math.max(paddedMax, Math.max(overscrollMax, 0));
    }

    /**
     * The resting "end" scroll position: the newest candle sits flush against the right price
     * axis with NO right padding visible. Used for the initial scroll-to-end and live-follow,
     * so the chart always opens on the latest candle without empty space. The user can still
     * scroll further right (up to getMaxScrollX) to reveal the padding.
     */
    public int getEndScrollX() {
        return endScrollXForWidth(mWidth);
    }

    /** getEndScrollX() computed for an arbitrary view width (used across resizes). */
    private int endScrollXForWidth(int width) {
        int contentWidth = (int) Math.max((mDataLen - (width - configManager.paddingRight) / mScaleX), 0);
        return Math.max(contentWidth, 0);
    }

    /**
     * 在主区域画线
     *
     * @param startX    开始点的横坐标
     * @param stopX     开始点的值
     * @param stopX     结束点的横坐标
     * @param stopValue 结束点的值
     */
    public void drawMainLine(Canvas canvas, Paint paint, float startX, float startValue, float stopX, float stopValue) {
        canvas.drawLine(startX, yFromValue(startValue), stopX, yFromValue(stopValue), paint);
    }

    /**
     * 在子区域画线
     *
     * @param startX     开始点的横坐标
     * @param startValue 开始点的值
     * @param stopX      结束点的横坐标
     * @param stopValue  结束点的值
     */
    public void drawChildLine(Canvas canvas, Paint paint, float startX, float startValue, float stopX, float stopValue) {
        canvas.drawLine(startX, getChildY(startValue), stopX, getChildY(stopValue), paint);
    }

    /**
     * 在子区域画线
     *
     * @param startX     开始点的横坐标
     * @param startValue 开始点的值
     * @param stopX      结束点的横坐标
     * @param stopValue  结束点的值
     */
    public void drawVolLine(Canvas canvas, Paint paint, float startX, float startValue, float stopX, float stopValue) {
        canvas.drawLine(startX, getVolY(startValue), stopX, getVolY(stopValue), paint);
    }

    /**
     * 根据索引获取实体
     *
     * @param position 索引值
     * @return
     */
    public KLineEntity getItem(int position) {
        // Defensive: JS can update modelArray size asynchronously relative to our cached
        // indices (mStartIndex, mStopIndex, mSelectedIndex), which can briefly point
        // past the end of the new list. Clamp the requested index into the valid range
        // so we never crash with IndexOutOfBoundsException during draw.
        int size = configManager.modelArray != null ? configManager.modelArray.size() : 0;
        if (size == 0) {
            // Return a dummy entity to avoid hard crashes when data is momentarily empty.
            // Callers typically only read fields for drawing; a zeroed entity is safe.
            return new KLineEntity();
        }
        int clamped = Math.max(0, Math.min(position, size - 1));
        return configManager.modelArray.get(clamped);
    }

    /**
     * 根据索引索取x坐标
     *
     * @param position 索引值
     * @return
     */
    public float getItemMiddleScrollX(int position) {
        return position * mPointWidth + mPointWidth * 0.5f;
    }


    /**
     * 设置当前子图
     *
     * @param position
     */
    public void setChildDraw(int position) {
        if (mChildDrawPosition != position) {
            if (!isShowChild) {
                isShowChild = true;
                // initRect();
            }
            mChildDraw = mChildDraws.get(position);
            mChildDrawPosition = position;
            isWR = position == 5;
            // invalidate();
        }
    }

    /**
     * 隐藏子图
     */
    public void hideChildDraw() {
        mChildDrawPosition = -1;
        isShowChild = false;
        mChildDraw = null;
        // initRect();
        // invalidate();
    }

    /**
     * 给子区域添加画图方法
     *
     * @param childDraw IChartDraw
     */
    public void addChildDraw(IChartDraw childDraw) {
        mChildDraws.add(childDraw);
    }

    // mChildDraws registry order (see KLineChartView.initView).
    private static final int DRAW_MACD = 0;
    private static final int DRAW_KDJ = 1;
    private static final int DRAW_RSI = 2;
    private static final int DRAW_WR = 3;
    private static final int DRAW_GENERIC = 4;

    /** Registry index for a JS sub code (3=MACD..6=WR, >=100=generic), or -1. */
    private int childDrawIndexForCode(int code) {
        switch (code) {
            case 3: return DRAW_MACD;
            case 4: return DRAW_KDJ;
            case 5: return DRAW_RSI;
            case 6: return DRAW_WR;
            default: return code >= 100 ? DRAW_GENERIC : -1;
        }
    }

    /**
     * Native N7: build the stacked panel list from configManager.secondList. When
     * the list is empty we fall back to the legacy single mChildDraw path.
     */
    public void applySecondList() {
        mActiveChildDraws = new ArrayList<>();
        List<Boolean> wr = new ArrayList<>();
        List<Integer> generic = new ArrayList<>();
        int genericCount = 0;
        List<Integer> codes = configManager != null ? configManager.secondList : null;
        if (codes != null) {
            for (int code : codes) {
                int idx = childDrawIndexForCode(code);
                if (idx < 0 || idx >= mChildDraws.size()) {
                    continue;
                }
                mActiveChildDraws.add(mChildDraws.get(idx));
                wr.add(idx == DRAW_WR);
                if (idx == DRAW_GENERIC) {
                    generic.add(genericCount++);
                } else {
                    generic.add(-1);
                }
            }
        }
        int n = mActiveChildDraws.size();
        mChildGenericIndex = new int[n];
        mChildIsWR = new boolean[n];
        for (int i = 0; i < n; i++) {
            mChildGenericIndex[i] = generic.get(i);
            mChildIsWR[i] = wr.get(i);
        }
        mChildMaxValues = new float[n];
        mChildMinValues = new float[n];
        mChildScaleYs = new float[n];
        // Only take over the child area when the stacked list is populated; an
        // empty list means an old JS bundle, so keep the legacy single-panel
        // state set by changeSecondDrawType().
        if (n > 0) {
            isShowChild = true;
            mChildDraw = mActiveChildDraws.get(0);
            mChildDrawPosition = 0;
        }
    }

    /** True when the stacked multi-panel path is active. */
    private boolean isMultiPanel() {
        return mActiveChildDraws != null && !mActiveChildDraws.isEmpty();
    }

    /**
     * Rebind the single mChildDraw/mChildRect/mChild*Value/mChildScaleY fields to
     * stacked panel `p` so all existing single-panel draw code (getChildY,
     * drawText, axis, selector) renders that panel.
     */
    private void setChildPanelContext(int p) {
        mChildDraw = mActiveChildDraws.get(p);
        mChildRect = mChildRects.get(p);
        mChildMaxValue = mChildMaxValues[p];
        mChildMinValue = mChildMinValues[p];
        mChildScaleY = mChildScaleYs[p];
        mCurrentGenericIndex = p < mChildGenericIndex.length ? mChildGenericIndex[p] : -1;
    }

    /**
     * Native N7: per-candle subLines for the current generic panel (set while
     * drawing). Falls back to the legacy single subLines for old payloads.
     */
    public List<HTKLineTargetItem> getCurrentSubLines(KLineEntity entity) {
        if (entity == null) {
            return null;
        }
        if (mCurrentGenericIndex >= 0
                && entity.subLinesList != null
                && mCurrentGenericIndex < entity.subLinesList.size()) {
            return entity.subLinesList.get(mCurrentGenericIndex);
        }
        return entity.subLines;
    }

    /** Bottom of the lowest sub-panel (or vol/main when there is none). */
    private int getChildAreaBottom() {
        if (!mChildRects.isEmpty()) {
            return mChildRects.get(mChildRects.size() - 1).bottom;
        }
        if (mChildRect != null && isShowChild) {
            return mChildRect.bottom;
        }
        return mVolRect != null ? mVolRect.bottom : mMainRect.bottom;
    }

    /**
     * 获取ValueFormatter
     *
     * @return
     */
    public IValueFormatter getValueFormatter() {
        return mValueFormatter;
    }

    /**
     * 设置ValueFormatter
     *
     * @param valueFormatter value格式化器
     */
    public void setValueFormatter(IValueFormatter valueFormatter) {
        this.mValueFormatter = valueFormatter;
    }

    /**
     * 获取DatetimeFormatter
     *
     * @return 时间格式化器
     */
    public IDateTimeFormatter getDateTimeFormatter() {
        return mDateTimeFormatter;
    }

    /**
     * 设置dateTimeFormatter
     *
     * @param dateTimeFormatter 时间格式化器
     */
    public void setDateTimeFormatter(IDateTimeFormatter dateTimeFormatter) {
        mDateTimeFormatter = dateTimeFormatter;
    }

    /**
     * 格式化时间
     *
     * @param date
     */
    public String formatDateTime(Date date) {
        if (getDateTimeFormatter() == null) {
            setDateTimeFormatter(new TimeFormatter());
        }
        return getDateTimeFormatter().format(date);
    }

    /**
     * 获取主区域的 IChartDraw
     *
     * @return IChartDraw
     */
    public IChartDraw getMainDraw() {
        return mMainDraw;
    }

    /**
     * 设置主区域的 IChartDraw
     *
     * @param mainDraw IChartDraw
     */
    public void setMainDraw(IChartDraw mainDraw) {
        mMainDraw = mainDraw;
        this.mainDraw = (MainDraw) mMainDraw;
    }

    public IChartDraw getVolDraw() {
        return mVolDraw;
    }

    public void setVolDraw(IChartDraw mVolDraw) {
        this.mVolDraw = mVolDraw;
    }

    /**
     * 二分查找当前值的index
     *
     * @return
     */
    public int indexFromScrollX(float scrollX) {
        return Math.max(0, Math.min((int)Math.floor(scrollX / mPointWidth), mItemCount - 1));
    }

    /**
     * 开始动画
     */
    public void startAnimation() {
        if (mAnimator != null) {
            mAnimator.start();
        }
    }

    /**
     * 设置动画时间
     */
    public void setAnimationDuration(long duration) {
        if (mAnimator != null) {
            mAnimator.setDuration(duration);
        }
    }

    /**
     * 设置表格行数
     */
    public void setGridRows(int gridRows) {
        if (gridRows < 1) {
            gridRows = 1;
        }
        mGridRows = gridRows;
    }

    /**
     * 设置表格列数
     */
    public void setGridColumns(int gridColumns) {
        if (gridColumns < 1) {
            gridColumns = 1;
        }
        mGridColumns = gridColumns;
    }

    /**
     * view中的x转化为scrollX
     *
     * @param x
     * @return
     */
    public float viewXToScrollX(float x) {
        return mScrollX +  x / mScaleX;
    }

    /**
     * scrollX转化为view中的x
     *
     * @param viewx
     * @return
     */
    public float scrollXtoViewX(float viewx) {
        return (viewx - mScrollX) * mScaleX;
    }

    /**
     * 获取上方padding
     */
    public float getTopPadding() {
        return mTopPadding;
    }

    /**
     * 获取上方padding
     */
    public float getChildPadding() {
        return mChildPadding;
    }

    /**
     * 获取子试图上方padding
     */
    public float getmChildScaleYPadding() {
        return mChildPadding;
    }

    /**
     * 获取图的宽度
     *
     * @return
     */
    public int getChartWidth() {
        return mWidth;
    }

    public int getScrollOffset() {
        return mScrollX;
    }

    /**
     * 是否长按
     */
    public boolean isLongPress() {
        return isLongPress;
    }

    /**
     * 获取选择索引
     */
    public int getSelectedIndex() {
        return mSelectedIndex;
    }

    public Rect getChildRect() {
        return mChildRect;
    }

    /**
     * Expose the main (price) chart rect so overlays (e.g. drawing tools) can clip
     * themselves and avoid rendering into the volume/child panes.
     */
    public Rect getMainRect() {
        return mMainRect;
    }

    public Rect getVolRect() {
        return mVolRect;
    }

    /**
     * 设置选择监听
     */
    public void setOnSelectedChangedListener(OnSelectedChangedListener l) {
        this.mOnSelectedChangedListener = l;
    }

    public void onSelectedChanged(BaseKLineChartView view, Object point, int index) {
        if (this.mOnSelectedChangedListener != null) {
            mOnSelectedChangedListener.onSelectedChanged(view, point, index);
        }
    }

    /**
     * 数据是否充满屏幕
     *
     * @return
     */
    public boolean isFullScreen() {
        return mDataLen >= mWidth / mScaleX;
    }

    /**
     * 设置超出右方后可滑动的范围
     */
    public void setOverScrollRange(float overScrollRange) {
        if (overScrollRange < 0) {
            overScrollRange = 0;
        }
        mOverScrollRange = overScrollRange;
    }

    /**
     * 设置上方padding
     *
     * @param topPadding
     */
    public void setTopPadding(int topPadding) {
        mTopPadding = topPadding;
    }

    /**
     * 设置下方padding
     *
     * @param bottomPadding
     */
    public void setBottomPadding(int bottomPadding) {
        mBottomPadding = bottomPadding;
    }

    /**
     * 设置表格线宽度
     */
    public void setGridLineWidth(float width) {
        mGridPaint.setStrokeWidth(width);
    }

    /**
     * 设置表格线颜色
     */
    public void setGridLineColor(int color) {
        mGridPaint.setColor(color);
    }

    /**
     * 设置选择器横线宽度
     */
    public void setSelectedXLineWidth(float width) {
        mSelectedXLinePaint.setStrokeWidth(width);
    }

    /**
     * 设置选择器横线颜色
     */
    public void setSelectedXLineColor(int color) {
        mSelectedXLinePaint.setColor(color);
    }

    /**
     * 设置选择器竖线宽度
     */
    public void setSelectedYLineWidth(float width) {
        mSelectedYLinePaint.setStrokeWidth(width);
    }

    /**
     * 设置选择器竖线颜色
     */
    public void setSelectedYLineColor(int color) {
        mSelectedYLinePaint.setColor(color);
    }

    /**
     * 设置文字颜色
     */
    public void setTextColor(int color) {
        mTextPaint.setColor(color);
    }

    public void setTextFontFamily(String fontFamily) {
        Typeface typeface = HTKLineConfigManager.findFont(getContext(), fontFamily);
        mGridPaint.setTypeface(typeface);

        mTextPaint.setTypeface(typeface);

        mMaxMinPaint.setTypeface(typeface);

        mBackgroundPaint.setTypeface(typeface);

        mSelectedXLinePaint.setTypeface(typeface);

        mSelectedYLinePaint.setTypeface(typeface);

        mSelectPointPaint.setTypeface(typeface);

        mSelectCenterPaint.setTypeface(typeface);

        mSelectCenterBackgroundPaint.setTypeface(typeface);

        mSelectorFramePaint.setTypeface(typeface);

        mClosePriceLinePaint.setTypeface(typeface);

        mClosePricePointPaint.setTypeface(typeface);

        mClosePriceTrianglePaint.setTypeface(typeface);

        mClosePriceRightTextPaint.setTypeface(typeface);
    }

    /**
     * 设置文字大小
     */
    public void setTextSize(float textSize) {
        mTextPaint.setTextSize(textSize);
        mClosePriceRightTextPaint.setTextSize(textSize);
    }

    /**
     * 设置最大值/最小值文字颜色
     */
    public void setMTextColor(int color) {
        mMaxMinPaint.setColor(color);
        mSelectedXLinePaint.setColor(color);
        mSelectorFramePaint.setColor(color);
    }

    /**
     * 设置最大值/最小值文字大小
     */
    public void setMTextSize(float textSize) {
        mMaxMinPaint.setTextSize(textSize);
    }

    /**
     * 设置背景颜色
     */
    public void setBackgroundColor(int color) {
        mBackgroundPaint.setColor(color);
    }

    /**
     * 设置选中point 值显示背景
     */
    public void setSelectPointColor(int color) {
        mSelectPointPaint.setColor(color);
    }

    /**
     * 选中点变化时的监听
     */
    public interface OnSelectedChangedListener {
        /**
         * 当选点中变化时
         *
         * @param view  当前view
         * @param point 选中的点
         * @param index 选中点的索引
         */
        void onSelectedChanged(BaseKLineChartView view, Object point, int index);
    }

    /**
     * 获取文字大小
     */
    public float getTextSize() {
        return mTextPaint.getTextSize();
    }

    /**
     * 获取曲线宽度
     */
    public float getLineWidth() {
        return mLineWidth;
    }

    /**
     * 设置曲线的宽度
     */
    public void setLineWidth(float lineWidth) {
        mLineWidth = lineWidth;
    }

    /**
     * 设置每个点的宽度
     */
    public void setPointWidth(float pointWidth) {
        mPointWidth = pointWidth;
    }

    public Paint getGridPaint() {
        return mGridPaint;
    }

    public Paint getTextPaint() {
        return mTextPaint;
    }

    // Left edge of the hover price pill (right side). Used so selector panels can avoid it.
    public float getSelectedPricePillLeft() {
        return mSelectedPricePillRect.isEmpty() ? -1f : mSelectedPricePillRect.left;
    }

    // Expose y-axis range so selector panels can keep clear of the y-axis labels.
    public float getMainMaxValue() {
        return mMainMaxValue;
    }

    public float getMainMinValue() {
        return mMainMinValue;
    }

    public Paint getBackgroundPaint() {
        return mBackgroundPaint;
    }

}
