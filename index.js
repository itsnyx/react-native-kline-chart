'use strict';

var React = require('react');
var ReactNative = require('react-native');

var NativeRNKLineView = ReactNative.requireNativeComponent('RNKLineView');

var RNKLineView = React.forwardRef(function (props, ref) {
  var onNewOrder = props.onNewOrder;
  var rest = Object.assign({}, props);
  delete rest.onNewOrder;

  var handleNewOrder = onNewOrder
    ? function (e) { return onNewOrder(e && e.nativeEvent && e.nativeEvent.price); }
    : undefined;

  return React.createElement(NativeRNKLineView, Object.assign({}, rest, { ref: ref, onNewOrder: handleNewOrder }));
});

RNKLineView.displayName = 'RNKLineView';

module.exports = RNKLineView;
module.exports.default = RNKLineView;
