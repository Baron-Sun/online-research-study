import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {emptyDemographics,normalizeDemographics,demographicsComplete,taskScreenFor,sameDemographics} from '../src/original100-demographics.mjs';
const read=path=>readFile(new URL('../'+path,import.meta.url),'utf8');

test('the five demographic questions, choices and field markup are copied from the reference survey',async()=>{
 const [reference,copy]=await Promise.all([read('src/AdviceTransferTask.jsx'),read('src/Original100Demographics.jsx')]);
 const options=text=>text.match(/const DEMOGRAPHIC_OPTIONS = Object\.freeze\([\s\S]*?\n\}\);/)[0];
 assert.equal(options(copy),options(reference));
 const originalSection=reference.slice(reference.indexOf('        <section className="source-panel transfer-question-panel transfer-demographics-panel">'),reference.indexOf('          <SaveStatus state={saveState} />',reference.indexOf('if (screen === "demographics")')));
 const copiedSection=copy.slice(copy.indexOf('        <section className="source-panel transfer-question-panel transfer-demographics-panel">'),copy.indexOf('          {children}'));
 assert.equal(copiedSection,originalSection.replaceAll('demographicsLocked','disabled').replaceAll('updateDemographic(','onChange('));
});

test('passed understanding checks route directly to the task; demographics restore to their own screen',()=>{
 const active={status:'active',position:1,comprehensionCheck:{passed:false}};
 assert.equal(taskScreenFor(active),'instructions');
 assert.equal(taskScreenFor({...active,comprehensionCheck:{passed:true}}),'task');
 assert.equal(taskScreenFor({...active,position:4,comprehensionCheck:{passed:true}}),'review');
 assert.equal(taskScreenFor({...active,position:5,comprehensionCheck:{passed:true}}),'demographics');
 assert.equal(taskScreenFor({...active,status:'screened_out'}),'screened-out');
 assert.equal(taskScreenFor({...active,status:'completed'}),'complete');
});

test('demographics use the same five fields and age boundaries as the reference survey',()=>{
 const completed={genderIdentity:'prefer-not-to-say',ageYears:35,englishProficiency:'no-fluent',educationLevel:'graduate-or-professional-training',employmentStatus:'student'};
 assert.equal(demographicsComplete(emptyDemographics()),false);
 assert.equal(demographicsComplete(completed),true);
 for(const key of Object.keys(completed)) assert.equal(demographicsComplete({...completed,[key]:null}),false,key);
 for(const ageYears of [17,121,20.5,'invalid']) assert.equal(demographicsComplete({...completed,ageYears}),false);
 for(const ageYears of [18,120]) assert.equal(demographicsComplete({...completed,ageYears}),true);
 assert.equal(demographicsComplete({...completed,genderIdentity:'unexpected'}),false);
 assert.equal(sameDemographics(completed,normalizeDemographics(completed)),true);
 assert.equal(sameDemographics(completed,{...completed,ageYears:36}),false);
});
