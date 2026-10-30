import React from 'react';

// Questions, options, ordering and field markup copied verbatim from AdviceTransferTask.
const DEMOGRAPHIC_OPTIONS = Object.freeze({
  genderIdentity: [
    ["male", "Male"],
    ["female", "Female"],
    ["other", "Other"],
    ["prefer-not-to-say", "Prefer not to say"],
  ],
  englishProficiency: [
    ["yes", "Yes"],
    ["no-fluent", "No, but fluent"],
    ["no-mostly-fluent", "No, mostly fluent"],
    ["no-minimal-fluency", "No, minimal fluency"],
  ],
  educationLevel: [
    ["no-school", "No school"],
    ["eighth-grade-or-less", "Eighth grade or less"],
    ["more-than-eighth-less-than-high-school", "More than eighth grade, but less than high school degree"],
    ["high-school-degree-or-equivalent", "High school degree or equivalent"],
    ["some-college", "Some college"],
    ["four-year-college-degree", "4-year college degree"],
    ["graduate-or-professional-training", "Graduate or professional training"],
  ],
  employmentStatus: [
    ["employed", "Employed"],
    ["self-employed", "Self-employed"],
    ["student", "A student"],
    ["unemployed", "Unemployed"],
    ["other", "Other"],
  ],
});
const DemographicChoice = ({ legend, name, options, value, onChange, disabled = false }) => (
  <fieldset className="transfer-demographic-fieldset" disabled={disabled}>
    <legend>{legend}</legend>
    <div className="transfer-demographic-options">
      {options.map(([optionValue, label]) => (
        <label
          key={optionValue}
          className={`transfer-demographic-option ${value === optionValue ? "selected" : ""}`}
        >
          <input
            type="radio"
            name={name}
            value={optionValue}
            checked={value === optionValue}
            onChange={() => onChange(optionValue)}
          />
          <span>{label}</span>
        </label>
      ))}
    </div>
  </fieldset>
);

export default function Original100Demographics({demographics,onChange,disabled=false,children}) {
  return (
        <section className="source-panel transfer-question-panel transfer-demographics-panel">
          <p className="source-eyebrow">Part 5 of 5</p>
          <h2>About you</h2>
          <p className="transfer-section-copy">
            To complete the task, please answer a few questions about yourself.
          </p>

          <DemographicChoice
            legend="With which gender identity do you mostly identify?"
            name="gender-identity"
            options={DEMOGRAPHIC_OPTIONS.genderIdentity}
            value={demographics.genderIdentity}
            onChange={(value) => onChange("genderIdentity", value)}
            disabled={disabled}
          />

          <div className="transfer-demographic-fieldset transfer-age-field">
            <label htmlFor="participant-age">What is your age?</label>
            <input
              id="participant-age"
              type="number"
              min="18"
              max="120"
              step="1"
              inputMode="numeric"
              value={demographics.ageYears ?? ""}
              readOnly={disabled}
              onChange={(event) => onChange(
                "ageYears",
                event.target.value === "" ? null : Number(event.target.value),
              )}
            />
          </div>

          <DemographicChoice
            legend="Is English your first language?"
            name="english-proficiency"
            options={DEMOGRAPHIC_OPTIONS.englishProficiency}
            value={demographics.englishProficiency}
            onChange={(value) => onChange("englishProficiency", value)}
            disabled={disabled}
          />

          <DemographicChoice
            legend="Please indicate your education level"
            name="education-level"
            options={DEMOGRAPHIC_OPTIONS.educationLevel}
            value={demographics.educationLevel}
            onChange={(value) => onChange("educationLevel", value)}
            disabled={disabled}
          />

          <DemographicChoice
            legend="Are you currently...?"
            name="employment-status"
            options={DEMOGRAPHIC_OPTIONS.employmentStatus}
            value={demographics.employmentStatus}
            onChange={(value) => onChange("employmentStatus", value)}
            disabled={disabled}
          />

          {children}
        </section>
  );
}
