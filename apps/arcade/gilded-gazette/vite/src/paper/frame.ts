import { useEffect, useRef, useState, type CSSProperties, type RefObject } from 'react';
import { setPlate, usePlate, useView } from '../state/paperStore';

/*
 * &viewport -> phones resize without a `resize` event when the URL bar slides,
 *              so visualViewport has to be listened to as well or the canvas
 *              keeps flying to where the plate used to be.
 */
function observeViewportChanges(onChange: () => void): () => void {
  window.addEventListener('resize', onChange);
  window.addEventListener('orientationchange', onChange);
  window.visualViewport?.addEventListener('resize', onChange);
  return () => {
    window.removeEventListener('resize', onChange);
    window.removeEventListener('orientationchange', onChange);
    window.visualViewport?.removeEventListener('resize', onChange);
  };
}

export function usePlateMeasure<T extends HTMLElement>() {
  const plateElementRef = useRef<T>(null);

  useEffect(() => {
    const plateElement = plateElementRef.current;
    if (!plateElement) return;

    const measurePlate = () => {
      const bounds = plateElement.getBoundingClientRect();
      setPlate({ x: bounds.x, y: bounds.y, w: bounds.width, h: bounds.height });
    };

    measurePlate();
    const plateResizeObserver = new ResizeObserver(measurePlate);
    plateResizeObserver.observe(plateElement);
    const stopViewportObserver = observeViewportChanges(measurePlate);
    return () => {
      plateResizeObserver.disconnect();
      stopViewportObserver();
    };
  }, []);

  return plateElementRef;
}

export function useFrameStyle(layerRef: RefObject<HTMLElement | null>): CSSProperties {
  const view = useView();
  const plate = usePlate();
  const [layerSize, setLayerSize] = useState({ width: 0, height: 0 });

  useEffect(() => {
    const layerElement = layerRef.current;
    if (!layerElement) return;

    // &layout -> offset sizes are the untransformed box, so reading them here
    //            cannot feed back into the transform this hook writes
    const measureLayer = () => {
      const width = layerElement.offsetWidth;
      const height = layerElement.offsetHeight;
      setLayerSize({ width, height });
      // &shape -> the plate can size itself to the canvas instead of letterboxing it
      if (height > 0) {
        document.documentElement.style.setProperty('--viewport-aspect', `${width} / ${height}`);
      }
    };

    measureLayer();
    const layerResizeObserver = new ResizeObserver(measureLayer);
    layerResizeObserver.observe(layerElement);
    const stopViewportObserver = observeViewportChanges(measureLayer);
    return () => {
      layerResizeObserver.disconnect();
      stopViewportObserver();
    };
  }, [layerRef]);

  const canFrame =
    view === 'paper' && plate && plate.w > 0 && plate.h > 0 &&
    layerSize.width > 0 && layerSize.height > 0;

  if (!canFrame) return { transform: 'translate3d(0px, 0px, 0) scale(1)' };

  const scale = Math.min(plate.w / layerSize.width, plate.h / layerSize.height);
  const offsetX = plate.x + (plate.w - layerSize.width * scale) / 2;
  const offsetY = plate.y + (plate.h - layerSize.height * scale) / 2;

  return { transform: `translate3d(${offsetX}px, ${offsetY}px, 0) scale(${scale})` };
}
