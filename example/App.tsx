/**
 * @itsnyx/react-native-kline-chart — full-feature example.
 *
 * Demonstrates everything the native chart supports:
 *   • Candle styles: solid / hollow / up-hollow / down-hollow / OHLC
 *   • Coordinate types: linear / percentage / logarithmic + inverted (Android)
 *   • Main-chart overlays (multi-select): MA, EMA, BOLL, SAR, AVL, VWAP, SUPER, ICHI
 *   • Sub-chart oscillators: VOL, MACD, KDJ, RSI, WR, ROC, CCI, OBV, StochRSI,
 *     MFI, DMI, DMA, MTM, EMV  (the extra 9 render through the generic panel)
 *   • Drawing tools, light/dark theme, real-time updates
 *
 * All indicator math + the modelArray/optionList pipeline lives in ./indicators.js
 * so this file stays focused on wiring the props.
 */
import React, { useMemo, useRef, useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  StatusBar,
  Pressable,
  processColor,
  Platform,
  PixelRatio,
} from 'react-native';
import RNKLineView from '@itsnyx/react-native-kline-chart';
import {
  processData,
  generateCandles,
  MAIN_INDICATORS,
  SUB_INDICATORS,
} from './indicators';

const CANDLE_STYLES = ['allSolid', 'allHollow', 'upHollow', 'downHollow', 'ohlc'];
const COORD_TYPES = ['linear', 'percentage', 'log'];
const DRAW_TOOLS = [
  { label: 'None', value: 0 },
  { label: 'Line', value: 1 },
  { label: 'Horizontal', value: 2 },
  { label: 'Ray', value: 4 },
  { label: 'Rect', value: 101 },
];

const THEMES = {
  dark: {
    background: '#0b0e11',
    text: '#8b949e',
    mainText: '#eaecef',
    grid: '#1b1f24',
    green: '#22c55e',
    red: '#ef4444',
    panel: '#151a1f',
    accent: '#f0b90b',
  },
  light: {
    background: '#ffffff',
    text: '#707a8a',
    mainText: '#1e2329',
    grid: '#eaecef',
    green: '#16a34a',
    red: '#dc2626',
    panel: '#f5f5f5',
    accent: '#c99400',
  },
};

const pr = Platform.select({ android: PixelRatio.get(), ios: 1 }) || 1;

export default function App() {
  const [candles, setCandles] = useState(() => generateCandles(200));
  const [main, setMain] = useState(['ma']);
  const [sub, setSub] = useState(['vol', 'macd']);
  const [candleStyle, setCandleStyle] = useState('allSolid');
  const [coord, setCoord] = useState('linear');
  const [inverted, setInverted] = useState(false);
  const [dark, setDark] = useState(true);
  const [drawTool, setDrawTool] = useState(0);
  const theme = dark ? THEMES.dark : THEMES.light;

  // Real-time: nudge the latest candle every 2s.
  useEffect(() => {
    const id = setInterval(() => {
      setCandles(prev => {
        const next = prev.slice();
        const last = { ...next[next.length - 1] };
        const delta = (Math.random() - 0.5) * 1.5;
        last.close = Math.max(1, last.close + delta);
        last.high = Math.max(last.high, last.close);
        last.low = Math.min(last.low, last.close);
        next[next.length - 1] = last;
        return next;
      });
    }, 2000);
    return () => clearInterval(id);
  }, []);

  const toggle = (list, setList, id, single) =>
    setList(prev =>
      single
        ? prev.includes(id)
          ? prev
          : [id]
        : prev.includes(id)
        ? prev.filter(x => x !== id)
        : [...prev, id],
    );

  const { model, primary, second, secondLabel, mainOverlays, showVolume } =
    useMemo(() => processData(candles, main, sub), [candles, main, sub]);

  // The chart reads candle data from the separate `modelArray` prop.
  const modelArrayJson = useMemo(() => JSON.stringify(model), [model]);

  const optionList = useMemo(() => {
    const gridC = processColor(theme.grid);
    const mainC = processColor(theme.mainText);
    const bgC = processColor(theme.background);
    const configList = {
      colorList: {
        increaseColor: processColor(theme.green),
        decreaseColor: processColor(theme.red),
      },
      targetColorList: [
        processColor(theme.accent),
        processColor('#4c9aff'),
        processColor('#a855f7'),
        processColor(theme.red),
        processColor(theme.green),
        processColor('#06b6d4'),
      ],
      minuteLineColor: processColor('#4c9aff'),
      minuteGradientColorList: [
        processColor('rgba(76,154,255,0.15)'),
        processColor('rgba(76,154,255,0.05)'),
        processColor('rgba(76,154,255,0)'),
        processColor('rgba(76,154,255,0)'),
      ],
      minuteGradientLocationList: [0, 0.3, 0.6, 1],
      backgroundColor: bgC,
      textColor: processColor(theme.text),
      gridColor: gridC,
      candleTextColor: mainC,
      panelBackgroundColor: processColor(theme.panel),
      panelBorderColor: gridC,
      panelTextColor: mainC,
      selectedPointContainerColor: mainC,
      selectedPointContentColor: mainC,
      closePriceCenterBackgroundColor: bgC,
      closePriceCenterBorderColor: mainC,
      closePriceCenterTriangleColor: mainC,
      closePriceCenterSeparatorColor: processColor(theme.text),
      closePriceRightBackgroundColor: bgC,
      closePriceRightSeparatorColor: mainC,
      closePriceRightLightLottieSource: '',
      closePriceRightLightLottieFloder: 'images',
      closePriceRightLightLottieScale: 0.4,
      panelGradientColorList: [
        processColor('rgba(129,140,180,0.2)'),
        processColor('rgba(129,140,180,0.1)'),
        processColor('rgba(129,140,180,0.2)'),
        processColor('rgba(129,140,180,0.1)'),
        processColor('rgba(129,140,180,0.2)'),
      ],
      panelGradientLocationList: [0, 0.25, 0.5, 0.75, 1],
      minuteVolumeCandleColor: processColor('rgba(255,255,212,0.5)'),
      minuteVolumeCandleWidth: 2 * pr,
      macdCandleWidth: 1 * pr,
      mainFlex: second !== 0 ? 0.6 : showVolume ? 0.75 : 0.9,
      volumeFlex: 0.18,
      showVolume,
      showCandleCountdown: false,
      itemWidth: 8 * pr,
      candleWidth: 6 * pr,
      paddingLeft: 0,
      paddingTop: 20 * pr,
      paddingBottom: 20 * pr,
      paddingRight: 70 * pr,
      headerTextFontSize: 10 * pr,
      rightTextFontSize: 10 * pr,
      candleTextFontSize: 10 * pr,
      panelTextFontSize: 10 * pr,
      panelMinWidth: 120 * pr,
      drawingsEditable: true,
      hoverInfoEnabled: true,
      showPlusIcon: false,
      // New capabilities:
      mainOverlays,
      candleStyle,
      coordinateType: coord,
      invertedView: inverted,
    };
    const targetList = {
      maList: [
        { title: '5', index: 0, selected: true },
        { title: '10', index: 1, selected: true },
        { title: '20', index: 2, selected: true },
      ],
      maVolumeList: [
        { title: '5', index: 0, selected: true },
        { title: '10', index: 1, selected: true },
      ],
      rsiList: [
        { title: '6', index: 0, selected: true },
        { title: '12', index: 1, selected: true },
        { title: '24', index: 2, selected: true },
      ],
      wrList: [{ title: '14', index: 0, selected: true }],
      bollN: '20',
      bollP: '2',
      macdS: '12',
      macdL: '26',
      macdM: '9',
      kdjN: '9',
      kdjM1: '3',
      kdjM2: '3',
    };
    return JSON.stringify({
      shouldScrollToEnd: true,
      modelArray: model,
      targetList,
      primary,
      second,
      secondLabel,
      price: 2,
      volume: 0,
      // time !== -1 renders candlesticks (−1 would be minute/line mode). 2 = 1m.
      time: 2,
      configList,
      drawList: { drawType: drawTool },
    });
  }, [
    model,
    primary,
    second,
    secondLabel,
    mainOverlays,
    showVolume,
    candleStyle,
    coord,
    inverted,
    theme,
    drawTool,
  ]);

  const Chip = ({ label, active, onPress, color }) => (
    <Pressable
      onPress={onPress}
      style={[
        styles.chip,
        { borderColor: active ? (color || theme.accent) : theme.grid },
        active && { backgroundColor: (color || theme.accent) + '22' },
      ]}
    >
      <Text style={[styles.chipText, { color: active ? theme.mainText : theme.text }]}>
        {label}
      </Text>
    </Pressable>
  );

  const Section = ({ title, children }) => (
    <View style={styles.section}>
      <Text style={[styles.sectionTitle, { color: theme.text }]}>{title}</Text>
      <View style={styles.row}>{children}</View>
    </View>
  );

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <StatusBar barStyle={dark ? 'light-content' : 'dark-content'} />
      <View style={styles.header}>
        <Text style={[styles.title, { color: theme.mainText }]}>
          react-native-kline-chart
        </Text>
        <Chip label={dark ? '🌙 Dark' : '☀️ Light'} active onPress={() => setDark(d => !d)} />
      </View>

      <View style={styles.chart}>
        <RNKLineView
          style={{ flex: 1 }}
          optionList={optionList}
          modelArray={modelArrayJson}
        />
      </View>

      <ScrollView style={styles.controls} contentContainerStyle={{ paddingBottom: 30 }}>
        <Section title="MAIN OVERLAYS (multi-select)">
          {MAIN_INDICATORS.map(id => (
            <Chip
              key={id}
              label={id.toUpperCase()}
              active={main.includes(id)}
              onPress={() => toggle(main, setMain, id)}
            />
          ))}
        </Section>

        <Section title="SUB PANEL (VOL + one oscillator)">
          {SUB_INDICATORS.map(id => (
            <Chip
              key={id}
              label={id.toUpperCase()}
              active={sub.includes(id)}
              color="#4c9aff"
              onPress={() => toggle(sub, setSub, id)}
            />
          ))}
        </Section>

        <Section title="CANDLE STYLE">
          {CANDLE_STYLES.map(s => (
            <Chip key={s} label={s} active={candleStyle === s} onPress={() => setCandleStyle(s)} />
          ))}
        </Section>

        <Section title="COORDINATE TYPE (Android)">
          {COORD_TYPES.map(c => (
            <Chip key={c} label={c} active={coord === c} onPress={() => setCoord(c)} />
          ))}
          <Chip label="Inverted" active={inverted} onPress={() => setInverted(v => !v)} />
        </Section>

        <Section title="DRAWING TOOL">
          {DRAW_TOOLS.map(t => (
            <Chip key={t.value} label={t.label} active={drawTool === t.value} onPress={() => setDrawTool(t.value)} />
          ))}
        </Section>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 14,
    paddingTop: Platform.OS === 'ios' ? 54 : 14,
    paddingBottom: 8,
  },
  title: { fontSize: 16, fontWeight: '700' },
  chart: { height: 420 },
  controls: { flex: 1, paddingHorizontal: 12 },
  section: { marginTop: 14 },
  sectionTitle: { fontSize: 11, fontWeight: '700', letterSpacing: 0.5, marginBottom: 8 },
  row: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: {
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 8,
    borderWidth: 1,
  },
  chipText: { fontSize: 12, fontWeight: '600' },
});
