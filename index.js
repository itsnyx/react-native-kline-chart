'use strict';

var React = require('react');
var ReactNative = require('react-native');

var NativeRNKLineView = ReactNative.requireNativeComponent('RNKLineView');

var RNKLineView = React.forwardRef(function (props, ref) {
  var onNewOrder = props.onNewOrder;
  var onCrosshairChange = props.onCrosshairChange;
  var rest = Object.assign({}, props);
  delete rest.onNewOrder;
  delete rest.onCrosshairChange;

  var handleNewOrder = onNewOrder
    ? function (e) { return onNewOrder(e && e.nativeEvent && e.nativeEvent.price); }
    : undefined;

  // In "topLayer" hover mode the native side draws no panel and instead reports
  // the selected candle here so the app can render the OHLC readout itself.
  // Payload: { visible, index, time, id, open, high, low, close, volume }.
  var handleCrosshairChange = onCrosshairChange
    ? function (e) { return onCrosshairChange(e && e.nativeEvent); }
    : undefined;

  return React.createElement(NativeRNKLineView, Object.assign({}, rest, { ref: ref, onNewOrder: handleNewOrder, onCrosshairChange: handleCrosshairChange }));
});

RNKLineView.displayName = 'RNKLineView';

module.exports = RNKLineView;
module.exports.default = RNKLineView;
