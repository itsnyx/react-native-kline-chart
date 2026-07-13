package com.github.fujianlian.klinechart;

import java.util.List;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.Map;

public class HTKLineTargetItem {

    private boolean selected = false;
    public int index = 0;
    public String title = "";
    public float value = 0.0f;
    // Native N6 (0.4.3): explicit per-line color. When present it wins over the
    // shared targetColorList slot lookup, so the exact color the user picked in
    // the indicator settings is drawn regardless of what else is on screen.
    public boolean hasColor = false;
    public int color = 0;


    public HTKLineTargetItem(Map valueList) {
        String title = valueList.get("title").toString();
        Object object = valueList.get("value");
        if (object == null) {
            object = new Double(0);
        }
        float value = ((Number) object).floatValue();
        object = valueList.get("selected");
        if (object == null) {
            object = new Boolean(true);
        }
        boolean selected = ((Boolean) object).booleanValue();
        object = valueList.get("index");
        if (object == null) {
            object = new Double(0);
        }
        int index = ((Number) object).intValue();
        // `color` arrives as a processColor int (optionList target items) or a
        // "#RRGGBB" string (per-candle items computed on the JS side).
        object = valueList.get("color");
        if (object instanceof Number) {
            this.color = ((Number) object).intValue();
            this.hasColor = true;
        } else if (object instanceof String) {
            try {
                this.color = android.graphics.Color.parseColor((String) object);
                this.hasColor = true;
            } catch (Exception ignored) {
            }
        }
        this.title = title;
        this.value = value;
        this.selected = selected;
        this.index = index;
    }

    public static ArrayList<HTKLineTargetItem> packModelArray(List<Map> valueList) {
        ArrayList<HTKLineTargetItem> modelArray = new ArrayList();
        // JS may omit an indicator's list (e.g. maList/rsiList/wrList/maVolumeList)
        // from the targetList payload, in which case the caller passes null here.
        // Iterating null crashes with "List.iterator() on a null object reference".
        if (valueList == null) {
            return modelArray;
        }
        for (Object object: valueList) {
            HTKLineTargetItem item = new HTKLineTargetItem((Map) object);
            if (item.selected) {
                modelArray.add(item);
            }
        }
        return modelArray;
    }

}
