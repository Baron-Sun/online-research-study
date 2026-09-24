import React, { useId } from "react";
import { RATING_SCALE_100 } from "./advice-transfer-protocol.mjs";

export default function RatingScaleQuestion({ legend, value, onChange, low, middle, high, disabled = false, version }) {
  const id = useId();
  if (version === RATING_SCALE_100) {
    return <fieldset className="transfer-scale-fieldset" disabled={disabled}>
      <legend id={`${id}-label`}>{legend}</legend>
      <p id={`${id}-help`} className="transfer-slider-help">
        {disabled ? "Your saved answer is shown below." : "Click or move the slider to choose a number from 0 to 100."}
      </p>
      <input className="transfer-perception-slider" type="range" min="0" max="100" step="1"
        value={value ?? 50} disabled={disabled} aria-labelledby={`${id}-label`}
        aria-describedby={`${id}-help ${id}-anchors ${id}-value`}
        aria-valuetext={value == null ? "No answer selected" : String(value)} data-unanswered={value == null}
        onChange={(event) => onChange(Number(event.target.value))}
        // Choosing the initial midpoint is an explicit answer, not a default.
        onPointerUp={(event) => { if (!disabled) onChange(Number(event.currentTarget.value)); }}
        onKeyDown={(event) => {
          if (!disabled && (event.key === "Enter" || event.key === " ")) {
            event.preventDefault();
            onChange(Number(event.currentTarget.value));
          }
        }} />
      <div id={`${id}-anchors`} className="transfer-slider-anchors">
        <span>0 — {low}</span><span>100 — {high}</span>
      </div>
      <p id={`${id}-value`} className="transfer-slider-value" aria-live="polite">
        {value == null ? "No answer selected" : <>Your answer: <strong>{value}</strong></>}
      </p>
    </fieldset>;
  }
  // Assignments created before the scale change retain their original units.
  return <fieldset className="transfer-scale-fieldset" disabled={disabled}>
    <legend>{legend}</legend>
    <div className="source-rating-options transfer-rating-options">
      {[1, 2, 3, 4, 5, 6, 7].map((number) => <label
        className={`source-rating-option ${value === number ? "selected" : ""}`} key={number}>
        <input type="radio" name={id} value={number} checked={value === number} onChange={() => onChange(number)} />
        <span>{number}</span>
      </label>)}
    </div>
    <div className="source-rating-anchors transfer-rating-anchors">
      <span><b>1</b> — {low}</span><span><b>4</b> — {middle}</span><span><b>7</b> — {high}</span>
    </div>
  </fieldset>;
}
