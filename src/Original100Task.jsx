import React, {useEffect,useRef,useState} from 'react';
import {ADVICE_TRANSFER_CONSENT_TEXT} from './advice-transfer-consent';
import {requestSession,verifyMaterial,validComment} from './original100-protocol.mjs';
import {CHECK_VERSION,CHECK_QUESTION,CHECK_OPTIONS,PRIVATE_STUDY_INFORMATION,SESSION_NAMESPACE} from './private100-content.mjs';
import {countWords,RESPONSE_WORD_LIMIT,WORD_LIMIT_INSTRUCTION} from './private100-word-limit.mjs';

const consentText = ADVICE_TRANSFER_CONSENT_TEXT
  .replace('We expect that you will be in this research study for around 10–12 minutes.', 'You will read three interpersonal situations and write your judgment and reasoning for each. Please refer to the Prolific study description for the estimated duration.')
  .replace('You will receive $1.50 for your participation in this 10–12-minute study.', 'Compensation and the estimated duration will be stated in the Prolific study description before recruitment begins.')
  .replace('Data will be collected anonymously and will not be labeled with any identifying information.', 'Your Prolific participant ID will be stored separately from the response text for assignment, duplicate prevention, and study administration. Research exports will use coded participant identifiers.')
  .replace('If you agree to participate, you will complete a research survey. The survey asks about your agreement or disagreement with various statements, along with free-response items. The topics include your attitudes and opinions about various topics, including your personal relationships and your political views. It includes some comprehension questions intended to make sure you understand information you have read.', 'If you agree to participate, you will read three descriptions of interpersonal situations. For each situation, you will read the provided instructions and write a response expressing your judgment and reasoning.');

function readJson(key) { try { return JSON.parse(localStorage.getItem(key)); } catch { return null; } }
function getIdentity() {
  const q=new URLSearchParams(location.search);
  let pid=q.get('PROLIFIC_PID') || '';
  const preview=q.get('preview')==='1' || /^(test|qa|preview)-/.test(pid);
  const slot=/^S\d{3}$/.test(q.get('slot')||'') ? q.get('slot') : 'S001';
  if (preview && !pid) {
    pid=`preview-${crypto.randomUUID()}`;
    q.set('PROLIFIC_PID',pid);
    history.replaceState(null,'',`${location.pathname}?${q.toString()}`);
  }
  const studyId=q.get('STUDY_ID') || (preview ? 'matched100-preview' : '');
  const sessionId=q.get('SESSION_ID') || (preview ? pid : '');
  const key=`${SESSION_NAMESPACE}:${preview?'preview':'formal'}:${pid}:${studyId}:${sessionId}`;
  const saved=readJson(key);
  const token=saved?.token || [...crypto.getRandomValues(new Uint8Array(32))].map(n=>n.toString(16).padStart(2,'0')).join('');
  return {pid,preview,studyId,sessionId,slot,key,token,consented:saved?.consented || false};
}
const Primary=({children,...props})=><button type="button" className="source-primary-button" {...props}>{children}</button>;
const Secondary=({children,...props})=><button type="button" className="source-secondary-button" {...props}>{children}</button>;

export default function Original100Task() {
  const [identity]=useState(getIdentity);
  const [screen,setScreen]=useState(identity.consented?'loading':'overview');
  const [agreed,setAgreed]=useState(false);
  const [session,setSession]=useState(null);
  const [answers,setAnswers]=useState(['','','']);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState('');
  const [saveState,setSaveState]=useState('');
  const [recovered,setRecovered]=useState([]);
  const [showWithdraw,setShowWithdraw]=useState(false);
  const [checkChoice,setCheckChoice]=useState(()=>readJson(identity.key+':comprehension-pending-v1')?.choice||'');
  const [checkFeedback,setCheckFeedback]=useState('');
  const remote=useRef(null), latest=useRef(answers), queue=useRef(Promise.resolve());
  const config={url:import.meta.env.VITE_SUPABASE_URL,anonKey:import.meta.env.VITE_SUPABASE_ANON_KEY};
  const remember=(consented=true)=>localStorage.setItem(identity.key,JSON.stringify({...identity,consented}));
  const cache=()=>localStorage.setItem(identity.key+':draft',JSON.stringify(latest.current.map((answer,i)=>({answer,revision:remote.current?.posts[i].revision || 0}))));
  const rpc=(action,payload)=>{
    if (!config.url || !config.anonKey) throw new Error('The database connection is not configured. Please contact the researcher.');
    return requestSession(config,identity,action,payload);
  };
  const adopt=(value)=>{remote.current=value;setSession(value);};
  const openSession=async(action)=>{
    setBusy(true);setError('');
    try {
      const value=await verifyMaterial(await rpc(action,{consent:true,slot:identity.slot}));
      adopt(value);remember();
      const drafts=readJson(identity.key+':draft');const conflicts=[];
      const restored=value.posts.map((p,i)=>{
        const draft=drafts?.[i];
        if (value.status==='active' && draft && draft.answer!==p.answer) {
          if (draft.revision===p.revision) return draft.answer;
          conflicts.push({position:i+1,answer:draft.answer});
        }
        return p.answer;
      });
      setRecovered(conflicts);latest.current=restored;setAnswers(restored);
      setScreen(value.status==='screened_out'?'screened-out':value.status==='completed'?'complete':!value.comprehensionCheck?.passed||action==='claim'?'instructions':value.position===4?'review':'task');
      if(value.comprehensionCheck?.attempts>0&&!value.comprehensionCheck.passed) setCheckFeedback('That answer does not match the task. Please reread the instructions above. You have one attempt remaining.');
      setSaveState(restored.some((a,i)=>a!==value.posts[i].answer)?'Draft restored on this device':'All changes saved');
    } catch(e) { setError(e.message);setScreen('error'); } finally {setBusy(false);}
  };
  useEffect(()=>{if(identity.consented) openSession('resume');},[]);

  const saveAll=()=>{
    const work=queue.current.catch(()=>{}).then(async()=>{
      if (!remote.current || remote.current.status!=='active') return;
      setSaveState('Saving…');
      for(let i=0;i<3;i++) {
        const answer=latest.current[i], previous=remote.current.posts[i];
        if(answer!==previous.answer) {
          const result=await rpc('save',{position:i+1,answer,revision:previous.revision});
          adopt(result);cache();
        }
      }
      setSaveState(latest.current.every((a,i)=>a===remote.current.posts[i].answer)?'All changes saved':'Saving…');
    });
    queue.current=work;
    return work;
  };
  useEffect(()=>{
    if(!session || session.status!=='active' || busy) return;
    if(answers.every((a,i)=>a===remote.current.posts[i].answer)) return;
    const timer=setTimeout(()=>saveAll().catch(e=>{setError(e.message);setSaveState('Not saved — retry before continuing');}),800);
    return ()=>clearTimeout(timer);
  },[answers,busy,session?.id]);
  useEffect(()=>{
    const warn=e=>{
      if(remote.current?.status==='active' && latest.current.some((a,i)=>a!==remote.current.posts[i].answer)) {e.preventDefault();e.returnValue='';}
    };
    window.addEventListener('beforeunload',warn);
    return ()=>window.removeEventListener('beforeunload',warn);
  },[]);
  const edit=(index,text)=>{
    const next=[...latest.current];next[index]=text;latest.current=next;setAnswers(next);cache();setSaveState('Unsaved changes');setError('');
  };
  const move=async(position)=>{
    setBusy(true);setError('');
    try {await saveAll();adopt(await rpc('navigate',{position}));setScreen(position===4?'review':'task');window.scrollTo(0,0);}
    catch(e){setError(e.message);}finally{setBusy(false);}
  };
  const submit=async()=>{
    setBusy(true);setError('');
    try {await saveAll();const result=await rpc('complete',{revisions:remote.current.posts.map(p=>p.revision)});adopt(result);setScreen('complete');localStorage.removeItem(identity.key+':draft');window.scrollTo(0,0);}
    catch(e){setError(e.message);}finally{setBusy(false);}
  };
  const checkTaskUnderstanding=async()=>{
    setBusy(true);setError('');setCheckFeedback('');
    try {
      const pending=readJson(identity.key+':comprehension-pending-v1') || {event_id:crypto.randomUUID(),choice:checkChoice,version:CHECK_VERSION};
      localStorage.setItem(identity.key+':comprehension-pending-v1',JSON.stringify(pending));
      const result=await rpc('comprehension_check',pending);adopt(result);
      localStorage.removeItem(identity.key+':comprehension-pending-v1');
      if(result.status==='screened_out') {setScreen('screened-out');window.scrollTo(0,0);}
      else if(result.comprehensionCheck.passed) setCheckFeedback('Thank you. You can now begin.');
      else {setCheckChoice('');setCheckFeedback('That answer does not match the task. Please reread the instructions above. You have one attempt remaining.');}
    } catch(e){setError(e.message);} finally{setBusy(false);}
  };
  const withdraw=async()=>{
    setBusy(true);setError('');
    try {await queue.current.catch(()=>{});await rpc('withdraw');adopt({...remote.current,status:'withdrawn'});setScreen('declined');setShowWithdraw(false);}
    catch(e){setError(e.message);}finally{setBusy(false);}
  };
  const index=(session?.position || 1)-1;
  const post=session?.posts[Math.min(index,2)];
  const wordCount=countWords(answers[index] || '');
  const overLimit=wordCount>RESPONSE_WORD_LIMIT;
  const wide=['task','consent'].includes(screen);
  return <main className="source-study-page transfer-study-page original100-page">
    <div className={`source-page-wrap ${wide?'source-wide-wrap':'source-narrow-wrap'}`}>
      <header className="source-study-header">
        <div><p className="source-institution">Northwestern University Research Study</p><h1>Study About Online Opinions</h1></div>
        <div className="source-session-card"><strong>Research session</strong><span>{screen==='task'?`Situation ${index+1} of 3`:screen==='complete'?'Responses submitted':'Three-situation response task'}</span></div>
      </header>
      {error&&<div className="original100-error" role="alert">{error}</div>}
      {recovered.length>0&&<details className="original100-error"><summary>A newer version was saved in another tab. The saved version is shown; your local draft is preserved here for review.</summary>{recovered.map(d=><div key={d.position}><h3>Local draft for post {d.position}</h3><pre>{d.answer}</pre></div>)}</details>}
      {screen==='loading'&&<section className="source-panel source-intro-panel"><h2>Restoring your session…</h2></section>}
      {screen==='overview'&&<section className="source-panel source-intro-panel">
        <p className="source-eyebrow">Study overview</p><h2>Read three situations and give your judgment</h2>
        <p className="source-intro-copy">In this task, you will read three descriptions of interpersonal situations. For each situation, you will give your own judgment and explain the reasons for it. You will choose a judgment label and write an explanation.</p>
        <div className="source-overview-grid"><div><span>Task</span><strong>Three situations, one response per situation</strong></div><div><span>Progress</span><strong>Responses save as you write</strong></div></div>
        <div className="source-intro-action"><h3>Ready to review the consent form?</h3><Primary onClick={()=>setScreen('consent')}>Review consent</Primary></div>
      </section>}
      {screen==='consent'&&<div className="source-consent-layout">
        <section className="source-panel source-consent-panel"><p className="source-eyebrow">Participant information</p><h2>Informed Consent</h2><div className="source-consent-text">{consentText}</div></section>
        <aside className="source-panel source-consent-confirmation"><h3>Consent Confirmation</h3><label className="source-consent-checkbox"><input type="checkbox" checked={agreed} onChange={e=>setAgreed(e.target.checked)} /><span>I am at least 18 years old, I have read the consent information, and I voluntarily agree to participate.</span></label><div className="source-button-row"><Secondary disabled={busy} onClick={()=>setScreen('declined')}>I Disagree</Secondary><Secondary disabled={busy} onClick={()=>setScreen('overview')}>Back</Secondary><Primary disabled={!agreed||busy} onClick={()=>{remember();openSession('claim');}}>{busy?'Preparing…':'I Agree'}</Primary></div></aside>
      </div>}
      {screen==='instructions'&&<section className="source-panel source-intro-panel"><p className="source-eyebrow">Instructions</p><h2>Give your judgment and explain your reasoning</h2><div className="source-intro-copy"><p>You will read three descriptions of interpersonal situations, one at a time. For each situation, choose a judgment label and explain the reasons for your own judgment. Enter the label on the first line and your reasoning on the next line.</p><p><strong>For each response: </strong>{WORD_LIMIT_INSTRUCTION}</p><p>{PRIVATE_STUDY_INFORMATION}</p><p>Please complete the task independently, without using AI tools or looking up other people’s responses.</p><p>Your responses are saved automatically. You can review and edit all three responses before the final submission.</p></div>
        <fieldset className="original100-attention original100-comprehension" disabled={busy||session?.comprehensionCheck?.passed}><legend>Task understanding check</legend><p>{CHECK_QUESTION}</p><p className="original100-check-help">You can refer to the instructions above. You have two attempts to answer this question.</p><div className="original100-attention-options">{CHECK_OPTIONS.map((option,i)=><label key={option.value}><input type="radio" name="task-understanding" value={option.value} checked={session?.comprehensionCheck?.passed?option.value==='judgment_reasons':checkChoice===option.value} onChange={e=>setCheckChoice(e.target.value)} /><span><strong>{String.fromCharCode(65+i)}.</strong> {option.text}</span></label>)}</div></fieldset>
        <p role="status" className="original100-check-feedback">{session?.comprehensionCheck?.passed?'Task understanding check completed. You can begin.':checkFeedback}</p>
        {session?.comprehensionCheck?.passed?<Primary disabled={busy} onClick={()=>move(1)}>Begin</Primary>:<Primary disabled={busy||!checkChoice} onClick={checkTaskUnderstanding}>{busy?'Saving…':'Check answer'}</Primary>}
      </section>}
      {screen==='task'&&post&&<>
        <div className="source-task-heading"><h2>Read the situation and write your response</h2><span>Situation {index+1} of 3</span></div>
        <div className="original100-task-grid">
          <article className="source-panel source-post-panel"><div className="source-panel-heading"><h3>Instructions and situation</h3></div><div className="source-post-text original100-prompt" data-testid="exact-prompt">{post.prompt}</div></article>
          <section className="source-panel original100-response"><label htmlFor="original100-answer">Your response</label><p className="original100-help">{WORD_LIMIT_INSTRUCTION}</p><textarea id="original100-answer" value={answers[index]} readOnly={busy} onChange={e=>edit(index,e.target.value)} placeholder="Write your response here." spellCheck="true" aria-describedby="comment-word-count comment-save" aria-invalid={overLimit||undefined} /><p id="comment-word-count" className={`original100-word-count${overLimit?' is-over-limit':''}`} role="status">{wordCount} / {RESPONSE_WORD_LIMIT} words · includes the judgment label{overLimit&&<span>Remove at least {wordCount-RESPONSE_WORD_LIMIT} {wordCount-RESPONSE_WORD_LIMIT===1?'word':'words'} to continue.</span>}</p><p id="comment-save" className="original100-save" role="status">{saveState}</p><div className="source-button-row"><Secondary disabled={busy} onClick={()=>index===0?setScreen('instructions'):move(index)}>{index===0?'Instructions':'Back'}</Secondary><Primary disabled={busy||!validComment(answers[index])} onClick={()=>move(index+2)}>{busy?'Saving…':index===2?'Review answers':'Continue'}</Primary></div><p className="original100-help">Follow the format in the instructions. A judgment abbreviation and reasoning on the next line are required.</p></section>
        </div>
      </>}
      {screen==='review'&&<section className="source-panel source-intro-panel"><p className="source-eyebrow">Final review</p><h2>Review your three responses</h2><p className="source-intro-copy">You can return to any situation to make changes. After submission, your responses will be locked.</p>{session.posts.map((p,i)=><article className="original100-review" key={p.stimulusId}><div><h3>Situation {i+1}</h3><Secondary disabled={busy} onClick={()=>move(i+1)}>Review situation {i+1}</Secondary></div><p>{answers[i]}</p></article>)}<div className="source-button-row"><Secondary disabled={busy} onClick={()=>move(3)}>Back</Secondary><Primary disabled={busy||!answers.every(validComment)} onClick={submit}>{busy?'Submitting…':'Submit all three responses'}</Primary></div></section>}
      {screen==='complete'&&<section className="source-panel source-completion-panel"><div className="source-completion-mark" aria-hidden="true">✓</div><p className="source-eyebrow">Submission complete</p><h2>Thank you for participating</h2><p>All three responses have been saved.</p><p>This study examines how people respond to social dilemmas. The responses will be used for research on written opinions and comparisons with language-model responses.</p>{!identity.preview&&session?.completionCode?<a className="source-primary-button" href={`https://app.prolific.com/submissions/complete?cc=${encodeURIComponent(session.completionCode)}`}>Return to Prolific</a>:null}</section>}
      {screen==='screened-out'&&<section className="source-panel source-completion-panel"><p className="source-eyebrow">Session ended</p><h2>The task understanding check was not completed successfully</h2><p>After two incorrect answers, this session has ended. No completed response has been submitted.</p>{identity.preview?<><p>You can start again to review the task.</p><Primary onClick={()=>{location.href='?preview=1';}}>Start again</Primary></>:<p>Please return to Prolific and select “Cancel participation” to return this study.</p>}</section>}
      {screen==='declined'&&<section className="source-panel source-completion-panel"><h2>Your participation has ended</h2><p>No completed response was submitted. You may close this page.</p></section>}
      {screen==='error'&&<section className="source-panel source-error-panel"><h2>This session could not be opened</h2><p>Check your connection and reopen the same study link in this browser.</p>{identity.preview&&<Secondary onClick={()=>{location.href="?preview=1";}}>Start again</Secondary>}<Primary disabled={busy} onClick={()=>openSession('claim')}>Try again</Primary></section>}
      {session?.status==='active'&&!['declined','complete','error','screened-out'].includes(screen)&&<footer className="original100-footer">{showWithdraw?<div><p>End this session and withdraw from the study? Your responses will not count as a completed response.</p><Secondary disabled={busy} onClick={()=>setShowWithdraw(false)}>Keep participating</Secondary> <Secondary disabled={busy} onClick={withdraw}>Confirm withdrawal</Secondary></div>:<button type="button" onClick={()=>setShowWithdraw(true)}>Withdraw from this study</button>}</footer>}
    </div>
  </main>;
}
