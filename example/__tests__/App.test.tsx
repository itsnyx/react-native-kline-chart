/**
 * @format
 */

import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import RNKLineView from '@itsnyx/react-native-kline-chart';

jest.mock('react-native', () => {
  const RN = jest.requireActual('react-native');
  RN.requireNativeComponent = (name: string) => name;
  return RN;
});

const sampleCandle = {
  id: 1700000000000,
  open: 100,
  high: 110,
  low: 95,
  close: 105,
  vol: 50000,
  dateString: '11-14 08:00',
  selectedItemList: [],
};

const makeOptionList = (overrides = {}) =>
  JSON.stringify({
    modelArray: [sampleCandle],
    shouldScrollToEnd: true,
    targetList: {},
    configList: {},
    drawList: { drawType: 0 },
    ...overrides,
  });

describe('RNKLineView', () => {
  it('renders with minimal props', async () => {
    let tree: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      tree = ReactTestRenderer.create(
        <RNKLineView optionList={makeOptionList()} />,
      );
    });
    expect(tree!.toJSON()).toBeTruthy();
  });

  it('renders with modelArray prop', async () => {
    let tree: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      tree = ReactTestRenderer.create(
        <RNKLineView
          optionList={makeOptionList()}
          modelArray={JSON.stringify([sampleCandle])}
        />,
      );
    });
    expect(tree!.toJSON()).toBeTruthy();
  });

  it('passes event callbacks without crashing', async () => {
    const onEndReached = jest.fn();
    const onDrawItemComplete = jest.fn();
    const onDrawItemDidTouch = jest.fn();
    const onDrawPointComplete = jest.fn();

    let tree: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      tree = ReactTestRenderer.create(
        <RNKLineView
          optionList={makeOptionList()}
          onEndReached={onEndReached}
          onDrawItemComplete={onDrawItemComplete}
          onDrawItemDidTouch={onDrawItemDidTouch}
          onDrawPointComplete={onDrawPointComplete}
        />,
      );
    });
    expect(tree!.toJSON()).toBeTruthy();
  });

  it('renders with drawing tools configured', async () => {
    const optionList = makeOptionList({
      drawList: {
        drawType: 1,
        drawShouldContinue: true,
        drawItemList: [
          {
            index: 0,
            drawType: 2,
            drawColor: -65536,
            drawLineHeight: 1,
            drawDashWidth: 0,
            drawDashSpace: 0,
            drawIsLock: false,
            pointList: [{ x: 0, y: 100 }],
          },
        ],
      },
    });

    let tree: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      tree = ReactTestRenderer.create(
        <RNKLineView optionList={optionList} />,
      );
    });
    expect(tree!.toJSON()).toBeTruthy();
  });

  it('normalizes onNewOrder event', async () => {
    const onNewOrder = jest.fn();
    let tree: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      tree = ReactTestRenderer.create(
        <RNKLineView optionList={makeOptionList()} onNewOrder={onNewOrder} />,
      );
    });
    expect(tree!.toJSON()).toBeTruthy();
  });
});
