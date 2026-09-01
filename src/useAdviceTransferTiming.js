import { useEffect, useRef } from "react";
import { activeRegion, addActiveTime, emptyActiveTimings, normalizeActiveTimings } from "./advice-transfer-protocol.mjs";

export const useAdviceTransferTiming = (context) => {
  const totals = useRef(emptyActiveTimings());
  const contextRef = useRef(context);
  const segment = useRef({ at: performance.now(), region: null });

  const read = () => {
    const time = performance.now();
    totals.current = addActiveTime(totals.current, segment.current.region, time - segment.current.at);
    segment.current.at = time;
    return { ...totals.current };
  };
  const restore = (value) => {
    totals.current = normalizeActiveTimings(value);
    segment.current.at = performance.now();
  };
  const pause = () => {
    read();
    segment.current.region = null;
    return { ...totals.current };
  };
  const setRegion = () => {
    read();
    segment.current.region = activeRegion({ ...contextRef.current, visible: document.visibilityState === "visible" });
  };

  useEffect(() => {
    contextRef.current = context;
    setRegion();
  }, [context.screen, context.phase1Locked, context.phase2Locked, context.pending, context.gistFocused]);

  useEffect(() => {
    const onVisibility = () => setRegion();
    const onPageHide = () => pause();
    const onPageShow = () => setRegion();
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("pagehide", onPageHide);
    window.addEventListener("pageshow", onPageShow);
    return () => {
      pause();
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("pagehide", onPageHide);
      window.removeEventListener("pageshow", onPageShow);
    };
  }, []);

  return { read, restore, pause };
};
