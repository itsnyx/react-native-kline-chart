package com.github.fujianlian.klinechart;

import android.animation.ValueAnimator;
import android.graphics.Color;
import android.os.Build;
import android.view.View;
import android.view.animation.DecelerateInterpolator;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.common.MapBuilder;
import com.facebook.react.uimanager.SimpleViewManager;
import com.facebook.react.uimanager.ThemedReactContext;
import com.facebook.react.uimanager.annotations.ReactProp;
import com.github.fujianlian.klinechart.container.HTDrawItem;
import com.github.fujianlian.klinechart.container.HTDrawType;
import com.github.fujianlian.klinechart.container.HTKLineContainerView;
import com.github.fujianlian.klinechart.container.HTPoint;
import com.github.fujianlian.klinechart.draw.PrimaryStatus;
import com.github.fujianlian.klinechart.draw.SecondStatus;
import com.github.fujianlian.klinechart.formatter.DateFormatter;
import com.github.fujianlian.klinechart.formatter.ValueFormatter;

import javax.annotation.Nonnull;
import javax.annotation.Nullable;
import java.text.SimpleDateFormat;
import java.util.*;
import com.alibaba.fastjson.JSON;
import com.alibaba.fastjson.parser.Feature;

public class RNKLineView extends SimpleViewManager<HTKLineContainerView> {

	public static String onDrawItemDidTouchKey = "onDrawItemDidTouch";

	public static String onDrawItemCompleteKey = "onDrawItemComplete";

    public static String onDrawItemMoveKey = "onDrawItemMove";

	public static String onDrawPointCompleteKey = "onDrawPointComplete";

    // Fired when user scrolls to the left edge (older candles requested)
    public static String onEndReachedKey = "onEndReached";

    // Fired when the user taps the hover price pill (long-press selector)
    public static String onNewOrderKey = "onNewOrder";

    // Fired (in "topLayer" hover mode) when the crosshair selection changes, so
    // the app can render the selected candle's OHLC readout itself.
    public static String onCrosshairChangeKey = "onCrosshairChange";

    @Nonnull
    @Override
    public String getName() {
        return "RNKLineView";
    }

    @Nonnull
    @Override
    protected HTKLineContainerView createViewInstance(@Nonnull ThemedReactContext reactContext) {
    	HTKLineContainerView containerView = new HTKLineContainerView(reactContext);
    	return containerView;
    }

	@Override
	public Map getExportedCustomDirectEventTypeConstants() {
        MapBuilder.Builder builder = MapBuilder.builder();
        builder.put(onDrawItemDidTouchKey, MapBuilder.of("registrationName", onDrawItemDidTouchKey));
        builder.put(onDrawItemCompleteKey, MapBuilder.of("registrationName", onDrawItemCompleteKey));
        builder.put(onDrawPointCompleteKey, MapBuilder.of("registrationName", onDrawPointCompleteKey));
        builder.put(onEndReachedKey, MapBuilder.of("registrationName", onEndReachedKey));
        builder.put(onDrawItemMoveKey, MapBuilder.of("registrationName", onDrawItemMoveKey));
        builder.put(onNewOrderKey, MapBuilder.of("registrationName", onNewOrderKey));
        builder.put(onCrosshairChangeKey, MapBuilder.of("registrationName", onCrosshairChangeKey));
        return builder.build();
	}

    // Expose imperative commands so JS can control the loading lifecycle (e.g. unlock scroll
    // after older candles have been loaded).
    @Override
    public Map<String, Integer> getCommandsMap() {
        return MapBuilder.of(
                "refreshComplete", 1
        );
    }

    @Override
    public void receiveCommand(@Nonnull HTKLineContainerView root, int commandId, @Nullable ReadableArray args) {
        switch (commandId) {
            case 1:
                // Finish the "load more" state and re-enable scrolling/zooming.
                if (root.klineView != null) {
                    root.klineView.refreshComplete();
                }
                root.configManager.loadingMoreFromLeft = false;
                break;
            default:
                break;
        }
    }
    @ReactProp(name = "optionList")
    public void setOptionList(final HTKLineContainerView containerView, String optionList) {
        if (optionList == null) {
            return;
        }
        
        // Mark the reload in flight for as long as the parse + apply takes. A
        // container resize can ride the same React commit (adding a sub-panel
        // grows the chart AND changes the panel list) and is applied
        // synchronously, so onSizeChanged needs to know the panel list it can
        // see is about to be replaced.
        final HTKLineConfigManager configManager = containerView.configManager;
        configManager.pendingOptionListReloads.incrementAndGet();
        new Thread(new Runnable() {
            @Override
            public void run() {
                boolean posted = false;
                try {
                    int disableDecimalFeature = JSON.DEFAULT_PARSER_FEATURE & ~Feature.UseBigDecimal.getMask();
                    Map optionMap = (Map)JSON.parse(optionList, disableDecimalFeature);
                    configManager.reloadOptionList(optionMap);
                    posted = containerView.post(new Runnable() {
                        @Override
                        public void run() {
                            try {
                                containerView.reloadConfigManager();
                            } finally {
                                configManager.pendingOptionListReloads.decrementAndGet();
                            }
                        }
                    });
                } finally {
                    // Parse threw, or the view is gone and will never run the
                    // runnable — either way no reload is coming, so the flag must
                    // not stay raised and freeze onSizeChanged's relayout.
                    if (!posted) {
                        configManager.pendingOptionListReloads.decrementAndGet();
                    }
                }
            }
        }).start();
    }

    /**
     * Lightweight real-time bid/ask update: JSON string like
     * {"show":true,"bid":62035.0,"ask":62035.01,"bidText":"Bid","askText":"Ask"}.
     * Kept separate from optionList so per-tick updates don't reload the full config.
     */
    @ReactProp(name = "bidAsk")
    public void setBidAsk(final HTKLineContainerView containerView, @Nullable String bidAskJson) {
        HTKLineConfigManager configManager = containerView.configManager;
        if (bidAskJson == null || bidAskJson.isEmpty()) {
            configManager.showBidAsk = false;
        } else {
            try {
                Map map = (Map) JSON.parse(bidAskJson);
                Object show = map.get("show");
                Object bid = map.get("bid");
                Object ask = map.get("ask");
                Object bidText = map.get("bidText");
                Object askText = map.get("askText");
                configManager.showBidAsk = Boolean.TRUE.equals(show);
                configManager.bidPrice = bid instanceof Number ? ((Number) bid).floatValue() : 0;
                configManager.askPrice = ask instanceof Number ? ((Number) ask).floatValue() : 0;
                configManager.bidText = bidText instanceof String ? (String) bidText : "Bid";
                configManager.askText = askText instanceof String ? (String) askText : "Ask";
            } catch (Exception e) {
                configManager.showBidAsk = false;
            }
        }
        if (containerView.klineView != null) {
            containerView.klineView.invalidate();
        }
    }

    /**
     * Lightweight data-only update: replace modelArray without reloading full optionList.
     * Accepts the same modelArray JSON you normally embed inside optionList.
     */
    @ReactProp(name = "modelArray")
    public void setModelArray(final HTKLineContainerView containerView, String modelArrayJson) {
        if (modelArrayJson == null) {
            return;
        }

        new Thread(new Runnable() {
            @Override
            public void run() {
                int disableDecimalFeature = JSON.DEFAULT_PARSER_FEATURE & ~Feature.UseBigDecimal.getMask();
                Object parsed = JSON.parse(modelArrayJson, disableDecimalFeature);
                if (!(parsed instanceof List)) {
                    return;
                }
                List modelArray = (List) parsed;

                // Pack on background thread but do NOT assign to configManager yet —
                // assigning here would let onDraw see new data before mItemCount/mScrollX
                // are updated, causing a visible scroll jump.
                final List<KLineEntity> packedList =
                        containerView.configManager.packModelList(modelArray);
                containerView.post(new Runnable() {
                    @Override
                    public void run() {
                        // Atomically assign data + adjust scroll on the UI thread.
                        int oldScrollOffset = containerView.klineView.getScrollOffset();
                        // "At end" is measured against the resting flush position (newest candle
                        // against the axis), not the padded max — so live ticks keep following
                        // whether or not the user has scrolled into the right padding.
                        int oldEndScrollX = containerView.klineView.getEndScrollX();
                        boolean wasAtEnd = oldScrollOffset >= oldEndScrollX;

                        // Detect prepend by finding where the current first candle
                        // appears in the new data. This is robust against intermediate
                        // live-tick updates that would corrupt a count-based comparison.
                        //
                        // NOTE: detection deliberately does NOT depend on the
                        // loadingMoreFromLeft flag. That flag is cleared synchronously by
                        // the refreshComplete command (which JS calls right after prepending)
                        // while this data update is still being parsed on a background
                        // thread — so by the time we get here the flag is usually already
                        // false. Finding the old first candle at index > 0 in the new array
                        // is itself an unambiguous signal of a prepend, so we rely on that
                        // alone and stay correct regardless of flag/prop-update timing.
                        int prependedCount = 0;
                        boolean dataReplaced = false;
                        List<KLineEntity> currentArray = containerView.configManager.modelArray;
                        if (currentArray != null && !currentArray.isEmpty() && !packedList.isEmpty()) {
                            double oldFirstId = currentArray.get(0).id;
                            boolean found = false;
                            for (int i = 0; i < packedList.size(); i++) {
                                if (packedList.get(i).id == oldFirstId) {
                                    prependedCount = i;
                                    found = true;
                                    break;
                                }
                            }
                            if (!found) {
                                // Old first candle is gone → data was replaced wholesale
                                // (e.g. timeframe switch), not prepended.
                                dataReplaced = true;
                            }
                        }

                        // Assign the new data right before notifyChanged so both happen
                        // in the same UI frame — no stale-data draw in between.
                        containerView.configManager.modelArray = packedList;

                        // Recalculate candleMarker Y positions from the new candle data
                        // so markers track the correct high/low after timeframe changes.
                        if (!packedList.isEmpty()) {
                            for (HTDrawItem drawItem : containerView.klineView.drawContext.drawItemList) {
                                if (drawItem.drawType == HTDrawType.candleMarker && !drawItem.pointList.isEmpty()) {
                                    float x = drawItem.pointList.get(0).x;
                                    boolean isTop = "top".equalsIgnoreCase(drawItem.position);
                                    float newY = containerView.candleMarkerBodyValueForX(x, isTop);
                                    HTPoint pt = drawItem.pointList.get(0);
                                    pt.x = x;
                                    pt.y = newY;
                                }
                            }
                        }

                        if (prependedCount > 0) {
                            // Shift scroll so the previously visible candles stay anchored,
                            // regardless of where the user scrolled while waiting for data.
                            int shiftPx = Math.round(prependedCount * containerView.configManager.itemWidth);
                            int targetScrollX = oldScrollOffset + shiftPx;
                            // Animated rescale: as the empty left padding is replaced by real
                            // candles the visible min/max changes — lerp to it instead of snapping.
                            containerView.klineView.notifyChangedAnimated();
                            containerView.klineView.setScrollX(targetScrollX);
                            containerView.configManager.loadingMoreFromLeft = false;
                            // The sibling optionList update (same React commit) must not snap
                            // the chart back to the right edge and undo this anchor.
                            containerView.configManager.suppressScrollToEndOnce = true;
                        } else {
                            containerView.klineView.notifyChanged();
                            if (wasAtEnd) {
                                // Preserve any overscroll into the right tail (Bitget-style
                                // "3 candles visible" view): keep the same distance past the
                                // flush end so live ticks don't yank the chart back.
                                int overscroll = Math.max(oldScrollOffset - oldEndScrollX, 0);
                                int target = containerView.klineView.getEndScrollX() + overscroll;
                                containerView.klineView.setScrollX(Math.min(target, containerView.klineView.getMaxScrollX()));
                            }
                            if (dataReplaced) {
                                // Data replaced entirely (e.g. timeframe switch) — clear the
                                // flag so a stale "loading" state can't suppress later updates.
                                containerView.configManager.loadingMoreFromLeft = false;
                            }
                            // Otherwise (a live-tick append where the first candle is
                            // unchanged) leave loadingMoreFromLeft as-is — the flag stays
                            // active until the actual prepend arrives.
                        }
                    }
                });
            }
        }).start();
    }

}
