import React from "react";
import { perceptionItemsFor } from "./advice-transfer-perception.mjs";

export default function PerceptionQuestions({ assignment, answers, onChange, disabled }) {
  return (
    <section className="source-panel transfer-perception-panel" aria-label="Your impressions">
      {perceptionItemsFor(assignment).map(({ key, introduction, question, low, high }) => {
        const value = answers[key];
        const id = `perception-${key}`;
        return (
          <div className="transfer-perception-item" key={key}>
            {introduction && <p className="transfer-perception-introduction">{introduction}</p>}
            <label className="transfer-slider-label" htmlFor={id}>{question}</label>
            <p id={`${id}-help`} className="transfer-slider-help">
              {disabled ? "Your saved answer is shown below." : "Click or move the slider to choose a number from 0 to 100."}
            </p>
            <input id={id} className="transfer-perception-slider" type="range"
              min="0" max="100" step="1" value={value ?? 50} disabled={disabled}
              aria-describedby={`${id}-help ${id}-anchors ${id}-value`}
              aria-valuetext={value === null ? "No answer selected" : String(value)}
              data-unanswered={value === null}
              onChange={(event) => onChange(key, Number(event.target.value))}
              // Clicking the initial midpoint must explicitly record 50 too.
              onPointerUp={(event) => onChange(key, Number(event.currentTarget.value))}
              onKeyDown={(event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  onChange(key, Number(event.currentTarget.value));
                }
              }} />
            <div id={`${id}-anchors`} className="transfer-slider-anchors">
              <span>0 — {low}</span><span>100 — {high}</span>
            </div>
            <p id={`${id}-value`} className="transfer-slider-value" aria-live="polite">
              {value === null ? "No answer selected" : <>Your answer: <strong>{value}</strong></>}
            </p>
          </div>
        );
      })}
    </section>
  );
}
