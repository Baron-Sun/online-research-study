import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("setup and additive migration validate and persist the five v4 demographic fields", async () => {
  const [setup, migration] = await Promise.all([
    read("supabase_advice_transfer_setup.sql"),
    read("supabase_advice_transfer_v4_gist_migration.sql"),
  ]);

  for (const sql of [setup, migration]) {
    for (const column of [
      "gender_identity",
      "age_years",
      "english_proficiency",
      "education_level",
      "employment_status",
    ]) {
      assert.match(sql, new RegExp(`add column if not exists ${column} (?:text|integer)`));
    }
    assert.match(sql, /jsonb_typeof\(p_payload -> 'demographics'\) is distinct from 'object'/);
    assert.match(sql, /\{demographics,ageYears\}'.*'ageYears', 18, 120/s);
    assert.match(sql, /'male', 'female', 'other', 'prefer-not-to-say'/);
    assert.match(sql, /'yes', 'no-fluent', 'no-mostly-fluent', 'no-minimal-fluency'/);
    assert.match(sql, /'graduate-or-professional-training'/);
    assert.match(sql, /'employed', 'self-employed', 'student', 'unemployed', 'other'/);
    assert.match(sql, /gender_identity,\s+age_years,\s+english_proficiency,\s+education_level,\s+employment_status,\s+protocol_version/s);
    assert.match(sql, /v_gender_identity,\s+v_age_years,\s+v_english_proficiency,\s+v_education_level,\s+v_employment_status,\s+v_assignment\.protocol_version/s);
  }
});

test("demographic database columns stay nullable for legacy submissions", async () => {
  const migration = await read("supabase_advice_transfer_v4_gist_migration.sql");
  for (const column of [
    "gender_identity text",
    "age_years integer",
    "english_proficiency text",
    "education_level text",
    "employment_status text",
  ]) {
    assert.doesNotMatch(migration, new RegExp(`${column}\\s+not null`));
  }
  assert.match(migration, /if v_assignment\.protocol_version = 'advice-transfer-v4-gist' then\s+if v_gender_identity/s);
});

test("rollback acceptance test covers missing, malformed, persisted, and legacy demographics", async () => {
  const integration = await read("tests/advice-transfer-v4-integration.sql");
  assert.match(integration, /v_final - 'demographics'.*'Demographic responses'/);
  assert.match(integration, /\{demographics,ageYears\}'.*'121'/s);
  assert.match(integration, /v_submission\.gender_identity <> 'prefer-not-to-say'/);
  assert.match(integration, /v_legacy_submission\.gender_identity is not null/);
  assert.match(integration, /^rollback;/m);
});
