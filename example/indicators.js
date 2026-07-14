/**
 * Self-contained technical-indicator math + data pipeline for the example app.
 *
 * Mirrors the field-name contract the native library expects:
 *   MA -> maList, EMA -> emaList, BOLL -> bollUp/bollMb/bollDn,
 *   SAR -> sar, AVL -> avl, VWAP -> vwap, SUPER -> superTrend/superTrendUp,
 *   ICHI -> ichiTenkan/ichiKijun/ichiSpanA/ichiSpanB/ichiChikou,
 *   MACD -> macdDif/macdDea/macdValue, KDJ -> kdjK/kdjD/kdjJ,
 *   RSI -> rsiList, WR -> wrList, VOL MA -> maVolumeList,
 *   and every extra oscillator -> a generic `subLines` [{value,title}] list.
 */

// --- series helpers ---------------------------------------------------------
const sma = (v, p) => {
  const out = new Array(v.length).fill(NaN);
  if (p <= 0) return out;
  let s = 0;
  for (let i = 0; i < v.length; i++) {
    s += v[i];
    if (i >= p) s -= v[i - p];
    if (i >= p - 1) out[i] = s / p;
  }
  return out;
};
const ema = (v, p) => {
  const out = new Array(v.length).fill(NaN);
  if (!v.length || p <= 0) return out;
  const k = 2 / (p + 1);
  let prev = v[0];
  out[0] = prev;
  for (let i = 1; i < v.length; i++) {
    prev = v[i] * k + prev * (1 - k);
    out[i] = prev;
  }
  return out;
};
const wilder = (v, p) => {
  const out = new Array(v.length).fill(NaN);
  if (v.length < p || p <= 0) return out;
  let s = 0;
  for (let i = 0; i < p; i++) s += v[i];
  let prev = s / p;
  out[p - 1] = prev;
  for (let i = p; i < v.length; i++) {
    prev = (prev * (p - 1) + v[i]) / p;
    out[i] = prev;
  }
  return out;
};
const closes = d => d.map(x => x.close);
const highs = d => d.map(x => x.high);
const lows = d => d.map(x => x.low);
const vols = d => d.map(x => x.vol);
const typicals = d => d.map(x => (x.high + x.low + x.close) / 3);

// --- main-chart overlays ----------------------------------------------------
const MA_PERIODS = [5, 10, 20];
const EMA_PERIODS = [5, 10, 20];

const computeMA = d => {
  const c = closes(d);
  const series = MA_PERIODS.map(p => sma(c, p));
  d.forEach((x, i) => {
    x.maList = MA_PERIODS.map((p, k) => ({
      value: Number.isNaN(series[k][i]) ? x.close : series[k][i],
      title: `${p}`,
    }));
  });
};
const computeEMA = d => {
  const c = closes(d);
  const series = EMA_PERIODS.map(p => ema(c, p));
  d.forEach((x, i) => {
    x.emaList = EMA_PERIODS.map((p, k) => ({ value: series[k][i], title: `${p}` }));
  });
};
const computeBOLL = (d, n = 20, p = 2) => {
  const c = closes(d);
  for (let i = 0; i < d.length; i++) {
    if (i < n - 1) {
      d[i].bollMb = d[i].bollUp = d[i].bollDn = d[i].close;
      continue;
    }
    let sum = 0;
    for (let j = i - n + 1; j <= i; j++) sum += c[j];
    const ma = sum / n;
    let v = 0;
    for (let j = i - n + 1; j <= i; j++) v += (c[j] - ma) ** 2;
    const std = Math.sqrt(v / n);
    d[i].bollMb = ma;
    d[i].bollUp = ma + p * std;
    d[i].bollDn = ma - p * std;
  }
};
const computeSAR = (d, start = 0.02, step = 0.02, max = 0.2) => {
  if (d.length < 2) return d.forEach(x => (x.sar = x.close));
  const h = highs(d);
  const l = lows(d);
  let isUp = h[1] >= h[0];
  let af = start;
  let ep = isUp ? h[0] : l[0];
  let sar = isUp ? l[0] : h[0];
  d[0].sar = sar;
  for (let i = 1; i < d.length; i++) {
    sar = sar + af * (ep - sar);
    if (isUp) {
      sar = Math.min(sar, l[i - 1], i >= 2 ? l[i - 2] : l[i - 1]);
      if (h[i] > ep) (ep = h[i]), (af = Math.min(af + step, max));
      if (l[i] < sar) (isUp = false), (sar = ep), (ep = l[i]), (af = start);
    } else {
      sar = Math.max(sar, h[i - 1], i >= 2 ? h[i - 2] : h[i - 1]);
      if (l[i] < ep) (ep = l[i]), (af = Math.min(af + step, max));
      if (h[i] > sar) (isUp = true), (sar = ep), (ep = h[i]), (af = start);
    }
    d[i].sar = sar;
  }
};
const cumAvg = (d, field) => {
  let pv = 0;
  let vv = 0;
  const tp = typicals(d);
  const v = vols(d);
  for (let i = 0; i < d.length; i++) {
    pv += tp[i] * v[i];
    vv += v[i];
    d[i][field] = vv > 0 ? pv / vv : d[i].close;
  }
};
const computeSUPER = (d, period = 10, mult = 3) => {
  const h = highs(d);
  const l = lows(d);
  const c = closes(d);
  const tr = d.map((_, i) =>
    i === 0
      ? h[i] - l[i]
      : Math.max(h[i] - l[i], Math.abs(h[i] - c[i - 1]), Math.abs(l[i] - c[i - 1])),
  );
  const atr = wilder(tr, period);
  let fu = 0;
  let fl = 0;
  let up = true;
  for (let i = 0; i < d.length; i++) {
    const mid = (h[i] + l[i]) / 2;
    const a = Number.isNaN(atr[i]) ? tr[i] : atr[i];
    const bu = mid + mult * a;
    const bl = mid - mult * a;
    if (i === 0) {
      fu = bu;
      fl = bl;
      d[i].superTrend = bl;
      d[i].superTrendUp = true;
      continue;
    }
    fu = bu < fu || c[i - 1] > fu ? bu : fu;
    fl = bl > fl || c[i - 1] < fl ? bl : fl;
    up = up ? c[i] >= fl : c[i] > fu;
    d[i].superTrend = up ? fl : fu;
    d[i].superTrendUp = up;
  }
};
const computeICHI = (d, tk = 9, kj = 26, sb = 52, disp = 26) => {
  const h = highs(d);
  const l = lows(d);
  const mid = (i, p) => {
    if (i < p - 1) return NaN;
    let hi = -Infinity;
    let lo = Infinity;
    for (let j = i - p + 1; j <= i; j++) (hi = Math.max(hi, h[j])), (lo = Math.min(lo, l[j]));
    return (hi + lo) / 2;
  };
  // Raw (undisplaced) spans first; the kumo is then plotted `disp` bars ahead.
  const spanA = new Array(d.length).fill(NaN);
  const spanB = new Array(d.length).fill(NaN);
  d.forEach((x, i) => {
    const t = mid(i, tk);
    const k = mid(i, kj);
    x.ichiTenkan = t;
    x.ichiKijun = k;
    spanA[i] = (t + k) / 2;
    spanB[i] = mid(i, sb);
  });
  d.forEach((x, i) => {
    // Senkou Span A/B displaced forward: the cloud over candle i was computed
    // `disp` bars earlier. Chikou is the close displaced backward `disp` bars.
    x.ichiSpanA = i - disp >= 0 ? spanA[i - disp] : NaN;
    x.ichiSpanB = i - disp >= 0 ? spanB[i - disp] : NaN;
    x.ichiChikou = i + disp < d.length ? d[i + disp].close : NaN;
  });
  // Future kumo: the raw spans of the last `disp` bars project past the newest
  // candle. Delivered to native via configList.ichiFuture (null = no value);
  // entry k is drawn k+1 bars after the last candle.
  const futureStart = Math.max(0, d.length - disp);
  d.ichiFuture = [];
  for (let i = futureStart; i < d.length; i++) {
    d.ichiFuture.push({
      a: Number.isNaN(spanA[i]) ? null : spanA[i],
      b: Number.isNaN(spanB[i]) ? null : spanB[i],
    });
  }
};

// --- sub-chart oscillators --------------------------------------------------
const computeVOLMA = d => {
  const v = vols(d);
  const series = [5, 10].map(p => sma(v, p));
  d.forEach((x, i) => {
    x.maVolumeList = [5, 10].map((p, k) => ({
      value: Number.isNaN(series[k][i]) ? x.vol : series[k][i],
      title: `${p}`,
    }));
  });
};
const computeMACD = (d, s = 12, l = 26, m = 9) => {
  const c = closes(d);
  const eS = ema(c, s);
  const eL = ema(c, l);
  const dif = c.map((_, i) => eS[i] - eL[i]);
  const dea = ema(dif, m);
  d.forEach((x, i) => {
    x.macdDif = dif[i];
    x.macdDea = dea[i];
    x.macdValue = 2 * (dif[i] - dea[i]);
  });
};
const computeKDJ = (d, n = 9, m1 = 3, m2 = 3) => {
  const h = highs(d);
  const l = lows(d);
  const c = closes(d);
  let k = 50;
  let dd = 50;
  for (let i = 0; i < d.length; i++) {
    let hi = -Infinity;
    let lo = Infinity;
    for (let j = Math.max(0, i - n + 1); j <= i; j++) (hi = Math.max(hi, h[j])), (lo = Math.min(lo, l[j]));
    const rsv = hi === lo ? 50 : ((c[i] - lo) / (hi - lo)) * 100;
    k = (rsv + (m1 - 1) * k) / m1;
    dd = (k + (m2 - 1) * dd) / m2;
    d[i].kdjK = k;
    d[i].kdjD = dd;
    d[i].kdjJ = 3 * k - 2 * dd;
  }
};
const rsiSeries = (c, period) => {
  const out = new Array(c.length).fill(50);
  let g = 0;
  let ls = 0;
  for (let i = 1; i < c.length; i++) {
    const ch = c[i] - c[i - 1];
    const gg = ch > 0 ? ch : 0;
    const ll = ch < 0 ? -ch : 0;
    if (i <= period) {
      g += gg;
      ls += ll;
      if (i === period) {
        g /= period;
        ls /= period;
        out[i] = ls === 0 ? 100 : 100 - 100 / (1 + g / ls);
      }
    } else {
      g = (g * (period - 1) + gg) / period;
      ls = (ls * (period - 1) + ll) / period;
      out[i] = ls === 0 ? 100 : 100 - 100 / (1 + g / ls);
    }
  }
  return out;
};
const RSI_PERIODS = [6, 12, 24];
const computeRSI = d => {
  const c = closes(d);
  const series = RSI_PERIODS.map(p => rsiSeries(c, p));
  d.forEach((x, i) => {
    x.rsiList = RSI_PERIODS.map((p, k) => ({ value: series[k][i], index: k, title: `${p}` }));
  });
};
const computeWR = (d, period = 14) => {
  const h = highs(d);
  const l = lows(d);
  const c = closes(d);
  d.forEach((x, i) => {
    if (i < period - 1) return (x.wrList = [{ value: -50, index: 0, title: `${period}` }]);
    let hi = -Infinity;
    let lo = Infinity;
    for (let j = i - period + 1; j <= i; j++) (hi = Math.max(hi, h[j])), (lo = Math.min(lo, l[j]));
    x.wrList = [{ value: hi === lo ? -50 : -((hi - c[i]) / (hi - lo)) * 100, index: 0, title: `${period}` }];
  });
};
const computeROC = (d, n = 12, maP = 6) => {
  const c = closes(d);
  const roc = c.map((v, i) => (i < n || c[i - n] === 0 ? NaN : ((v - c[i - n]) / c[i - n]) * 100));
  const rocma = sma(roc.map(x => (Number.isNaN(x) ? 0 : x)), maP);
  d.forEach((x, i) => ((x.roc = roc[i]), (x.rocma = i < n ? NaN : rocma[i])));
};
const computeCCI = (d, n = 14) => {
  const tp = typicals(d);
  const s = sma(tp, n);
  for (let i = 0; i < d.length; i++) {
    if (i < n - 1) (d[i].cci = 0);
    else {
      let md = 0;
      for (let j = i - n + 1; j <= i; j++) md += Math.abs(tp[j] - s[i]);
      md /= n;
      d[i].cci = md === 0 ? 0 : (tp[i] - s[i]) / (0.015 * md);
    }
  }
};
const computeOBV = (d, maP = 30) => {
  const c = closes(d);
  const v = vols(d);
  const obv = new Array(d.length).fill(0);
  for (let i = 1; i < d.length; i++) obv[i] = obv[i - 1] + (c[i] > c[i - 1] ? v[i] : c[i] < c[i - 1] ? -v[i] : 0);
  const obvma = sma(obv, maP);
  d.forEach((x, i) => ((x.obv = obv[i]), (x.obvma = obvma[i])));
};
const computeStochRSI = (d, rsiP = 14, stochP = 14, kP = 3, dP = 3) => {
  const c = closes(d);
  const rsi = rsiSeries(c, rsiP);
  const stoch = new Array(d.length).fill(NaN);
  for (let i = 0; i < d.length; i++) {
    if (i < rsiP + stochP - 1) continue;
    let hi = -Infinity;
    let lo = Infinity;
    for (let j = i - stochP + 1; j <= i; j++) (hi = Math.max(hi, rsi[j])), (lo = Math.min(lo, rsi[j]));
    stoch[i] = hi === lo ? 0 : ((rsi[i] - lo) / (hi - lo)) * 100;
  }
  const kS = sma(stoch.map(x => (Number.isNaN(x) ? 0 : x)), kP);
  const dS = sma(kS, dP);
  d.forEach((x, i) => {
    x.stochK = i < rsiP + stochP - 1 ? NaN : kS[i];
    x.stochD = i < rsiP + stochP - 1 ? NaN : dS[i];
  });
};
const computeMFI = (d, n = 14) => {
  const tp = typicals(d);
  const v = vols(d);
  for (let i = 0; i < d.length; i++) {
    if (i < n) (d[i].mfi = 50);
    else {
      let pos = 0;
      let neg = 0;
      for (let j = i - n + 1; j <= i; j++) {
        const f = tp[j] * v[j];
        if (tp[j] > tp[j - 1]) pos += f;
        else if (tp[j] < tp[j - 1]) neg += f;
      }
      d[i].mfi = neg === 0 ? 100 : 100 - 100 / (1 + pos / neg);
    }
  }
};
const computeDMI = (d, period = 14, adxP = 6) => {
  const h = highs(d);
  const l = lows(d);
  const c = closes(d);
  const tr = new Array(d.length).fill(0);
  const pDM = new Array(d.length).fill(0);
  const mDM = new Array(d.length).fill(0);
  for (let i = 1; i < d.length; i++) {
    const up = h[i] - h[i - 1];
    const dn = l[i - 1] - l[i];
    pDM[i] = up > dn && up > 0 ? up : 0;
    mDM[i] = dn > up && dn > 0 ? dn : 0;
    tr[i] = Math.max(h[i] - l[i], Math.abs(h[i] - c[i - 1]), Math.abs(l[i] - c[i - 1]));
  }
  const trS = wilder(tr, period);
  const pS = wilder(pDM, period);
  const mS = wilder(mDM, period);
  const dx = new Array(d.length).fill(NaN);
  const pdi = new Array(d.length).fill(NaN);
  const mdi = new Array(d.length).fill(NaN);
  for (let i = 0; i < d.length; i++) {
    if (Number.isNaN(trS[i]) || trS[i] === 0) continue;
    pdi[i] = (pS[i] / trS[i]) * 100;
    mdi[i] = (mS[i] / trS[i]) * 100;
    const sum = pdi[i] + mdi[i];
    dx[i] = sum === 0 ? 0 : (Math.abs(pdi[i] - mdi[i]) / sum) * 100;
  }
  const adx = wilder(dx.map(x => (Number.isNaN(x) ? 0 : x)), adxP);
  d.forEach((x, i) => ((x.dmiPdi = pdi[i]), (x.dmiMdi = mdi[i]), (x.dmiAdx = adx[i])));
};
const computeDMA = (d, sP = 10, lP = 50, m = 10) => {
  const c = closes(d);
  const sMa = sma(c, sP);
  const lMa = sma(c, lP);
  const dma = c.map((_, i) => (Number.isNaN(sMa[i]) || Number.isNaN(lMa[i]) ? NaN : sMa[i] - lMa[i]));
  const ama = sma(dma.map(x => (Number.isNaN(x) ? 0 : x)), m);
  d.forEach((x, i) => ((x.dma = dma[i]), (x.ama = i < lP - 1 + m - 1 ? NaN : ama[i])));
};
const computeMTM = (d, n = 12, maP = 6) => {
  const c = closes(d);
  const mtm = c.map((v, i) => (i < n ? NaN : v - c[i - n]));
  const mtmma = sma(mtm.map(x => (Number.isNaN(x) ? 0 : x)), maP);
  d.forEach((x, i) => ((x.mtm = mtm[i]), (x.mtmma = i < n + maP - 1 ? NaN : mtmma[i])));
};
const computeEMV = (d, n = 14, maP = 9) => {
  const h = highs(d);
  const l = lows(d);
  const v = vols(d);
  const e1 = new Array(d.length).fill(0);
  for (let i = 1; i < d.length; i++) {
    const dm = (h[i] + l[i]) / 2 - (h[i - 1] + l[i - 1]) / 2;
    const range = h[i] - l[i];
    const box = range === 0 || v[i] === 0 ? 0 : v[i] / range;
    e1[i] = box === 0 ? 0 : dm / box;
  }
  const emv = sma(e1, n);
  const emvma = sma(emv.map(x => (Number.isNaN(x) ? 0 : x)), maP);
  d.forEach((x, i) => ((x.emv = emv[i]), (x.emvma = i < n + maP - 1 ? NaN : emvma[i])));
};

// --- registries -------------------------------------------------------------
export const MAIN_INDICATORS = ['ma', 'ema', 'boll', 'sar', 'avl', 'vwap', 'super', 'ichi'];
export const SUB_INDICATORS = ['vol', 'macd', 'kdj', 'rsi', 'wr', 'roc', 'cci', 'obv', 'stochrsi', 'mfi', 'dmi', 'dma', 'mtm', 'emv'];

// second codes for the native chart (built-ins 3-6, generic oscillators 100+).
const SECOND_CODE = {
  macd: 3, kdj: 4, rsi: 5, wr: 6,
  roc: 100, cci: 101, obv: 102, stochrsi: 103, mfi: 104, dmi: 105, dma: 106, mtm: 107, emv: 108,
};
export const GENERIC_SUBS = ['roc', 'cci', 'obv', 'stochrsi', 'mfi', 'dmi', 'dma', 'mtm', 'emv'];

// native "primary" main codes (MA=1, BOLL=2); everything else rides mainOverlays.
const PRIMARY_CODE = { ma: 1, boll: 2 };

const SUB_LINES = {
  roc: x => [{ value: x.roc, title: 'ROC' }, { value: x.rocma, title: 'MA' }],
  cci: x => [{ value: x.cci, title: 'CCI' }],
  obv: x => [{ value: x.obv, title: 'OBV' }],
  stochrsi: x => [{ value: x.stochK, title: 'K' }, { value: x.stochD, title: 'D' }],
  mfi: x => [{ value: x.mfi, title: 'MFI' }],
  dmi: x => [{ value: x.dmiPdi, title: '+DI' }, { value: x.dmiMdi, title: '-DI' }, { value: x.dmiAdx, title: 'ADX' }],
  dma: x => [{ value: x.dma, title: 'DMA' }, { value: x.ama, title: 'AMA' }],
  mtm: x => [{ value: x.mtm, title: 'MTM' }, { value: x.mtmma, title: 'MA' }],
  emv: x => [{ value: x.emv, title: 'EMV' }, { value: x.emvma, title: 'MA' }],
};

const COMPUTE = {
  ma: computeMA, ema: computeEMA, boll: computeBOLL, sar: computeSAR,
  avl: d => cumAvg(d, 'avl'), vwap: d => cumAvg(d, 'vwap'), super: computeSUPER, ichi: computeICHI,
  vol: computeVOLMA, macd: computeMACD, kdj: computeKDJ, rsi: computeRSI, wr: computeWR,
  roc: computeROC, cci: computeCCI, obv: computeOBV, stochrsi: computeStochRSI, mfi: computeMFI,
  dmi: computeDMI, dma: computeDMA, mtm: computeMTM, emv: computeEMV,
};

const fmt = (v, p = 2) => (v == null || Number.isNaN(v) ? '--' : Number(v).toFixed(p));
const fmtTime = t => {
  const d = new Date(t);
  const pad = n => String(n).padStart(2, '0');
  return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

/**
 * Runs every selected indicator's math and returns the modelArray the native
 * chart consumes, plus the derived native codes (primary / second / overlays).
 */
export const processData = (rawCandles, mainSelected, subSelected) => {
  const data = rawCandles.map(c => ({ ...c, id: c.time, vol: c.volume }));
  [...mainSelected, ...subSelected].forEach(id => COMPUTE[id] && COMPUTE[id](data));

  // Native codes.
  let primary = 0;
  let primaryId = null;
  for (const id of mainSelected) {
    if (PRIMARY_CODE[id]) { primary = PRIMARY_CODE[id]; primaryId = id; break; }
  }
  let second = 0;
  let secondId = null;
  for (const id of subSelected) {
    if (id !== 'vol' && SECOND_CODE[id]) { second = SECOND_CODE[id]; secondId = id; break; }
  }
  const mainOverlays = mainSelected.filter(id => id !== primaryId && id !== 'resist');
  const subLineBuilder = secondId ? SUB_LINES[secondId] : null;

  const model = data.map(x => {
    x.dateString = fmtTime(x.id);
    x.selectedItemList = [
      { title: 'Time', detail: x.dateString },
      { title: 'Open', detail: fmt(x.open) },
      { title: 'High', detail: fmt(x.high) },
      { title: 'Low', detail: fmt(x.low) },
      { title: 'Close', detail: fmt(x.close) },
      { title: 'Vol', detail: fmt(x.vol, 0) },
    ];
    if (subLineBuilder) x.subLines = subLineBuilder(x);
    return x;
  });

  return {
    model,
    primary,
    second,
    secondLabel: secondId ? secondId.toUpperCase() : '',
    mainOverlays,
    // Future kumo points for the native ichi overlay (empty when ichi is off).
    ichiFuture: mainSelected.includes('ichi') ? data.ichiFuture || [] : [],
    showVolume: subSelected.includes('vol'),
  };
};

/** Deterministic sample OHLC series so the demo needs no network. */
export const generateCandles = (count = 200) => {
  const out = [];
  let price = 100;
  let t = Date.now() - count * 60000;
  for (let i = 0; i < count; i++) {
    const drift = Math.sin(i / 12) * 1.5 + (Math.random() - 0.5) * 2;
    const open = price;
    const close = Math.max(1, open + drift);
    const high = Math.max(open, close) + Math.random() * 1.2;
    const low = Math.min(open, close) - Math.random() * 1.2;
    out.push({ time: t, open, high, low, close, volume: 500 + Math.random() * 1500 });
    price = close;
    t += 60000;
  }
  return out;
};
