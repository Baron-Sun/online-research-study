import React, {useEffect,useRef,useState} from 'react';
import {ADVICE_TRANSFER_CONSENT_TEXT} from './advice-transfer-consent';
import {requestSession,verifyMaterial,validComment} from './original100-protocol.mjs';

const consentText = ADVICE_TRANSFER_CONSENT_TEXT
  .replace('We expect that you will be in this research study for around 10–12 minutes.', 'You will read three online posts and write one comment about each. Please refer to the Prolific study description for the estimated duration.')
  .replace('You will receive $1.50 for your participation in this 10–12-minute study.', 'Compensation and the estimated duration will be stated in the Prolific study description before recruitment begins.')
  .replace('Data will be collected anonymously and will not be labeled with any identifying information.', 'Your Prolific participant ID will be stored separately from the response text for assignment, duplicate prevention, and study administration. Research exports will use coded participant identifiers.')
  .replace('If you agree to participate, you will complete a research survey. The survey asks about your agreement or disagreement with various statements, along with free-response items. The topics include your attitudes and opinions about various topics, including your personal relationships and your political views. It includes some comprehension questions intended to make sure you understand information you have read.', 'If you agree to participate, you will read three public online posts about social dilemmas. For each post, you will read the provided instructions and write a comment expressing a judgment and your reasoning.');

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
  const studyId=q.get('STUDY_ID') || (preview ? 'original100-preview' : '');
  const sessionId=q.get('SESSION_ID') || (preview ? pid : '');
  const key=`original100:${preview?'preview':'formal'}:${pid}:${studyId}:${sessionId}`;
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
  const [attentionChoice,setAttentionChoice]=useState(()=>readJson(identity.key+':attention-pending')?.choice||'');
  const [attentionFeedback,setAttentionFeedback]=useState('');
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
      setScreen(value.status==='completed'?'complete':!value.attentionCheck?.passed||action==='claim'?'instructions':value.position===4?'review':'task');
      if(value.attentionCheck?.attempts>0&&!value.attentionCheck.passed) setAttentionFeedback('Please reread the question below and try again.');
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
  const checkAttention=async()=>{
    setBusy(true);setError('');setAttentionFeedback('');
    try {
      const pending=readJson(identity.key+':attention-pending') || {event_id:crypto.randomUUID(),choice:attentionChoice,version:'attention-v1-blue'};
      localStorage.setItem(identity.key+':attention-pending',JSON.stringify(pending));
      const result=await rpc('attention_check',pending);adopt(result);
      localStorage.removeItem(identity.key+':attention-pending');
      if(result.attentionCheck.passed) setAttentionFeedback('Thank you. You can now begin.');
      else {setAttentionChoice('');setAttentionFeedback('Please reread the question below and try again.');}
    } catch(e){setError(e.message);} finally{setBusy(false);}
  };
  const withdraw=async()=>{
    setBusy(true);setError('');
    try {await queue.current.catch(()=>{});await rpc('withdraw');adopt({...remote.current,status:'withdrawn'});setScreen('declined');setShowWithdraw(false);}
    catch(e){setError(e.message);}finally{setBusy(false);}
  };
  const index=(session?.position || 1)-1;
  const post=session?.posts[Math.min(index,2)];
  const wide=['task','consent'].includes(screen);
  return <main className="source-study-page transfer-study-page original100-page">
    <div className={`source-page-wrap ${wide?'source-wide-wrap':'source-narrow-wrap'}`}>
      <header className="source-study-header">
        <div><p className="source-institution">Northwestern University Research Study</p><h1>Study About Online Opinions</h1></div>
        <div className="source-session-card"><strong>{identity.preview?'Researcher preview':'Research session'}</strong><span>{screen==='task'?`Post ${index+1} of 3`:screen==='complete'?'Responses submitted':'Three-post response task'}</span></div>
      </header>
      {identity.preview&&<div className="original100-preview">Preview · Responses are saved as test data and do not use recruitment places. Consent duration and payment will be finalized before launch.
        <details className="original100-preview-tools"><summary>Preview controls</summary><label>Assignment <select value={identity.slot} disabled={busy} onChange={e=>{location.href=`?preview=1&slot=${e.target.value}`;}}>{Array.from({length:100},(_,i)=>`S${String(i+1).padStart(3,'0')}`).map(slot=><option key={slot}>{slot}</option>)}</select></label> <button type="button" disabled={busy} onClick={()=>{location.href=`?preview=1&slot=${identity.slot}&PROLIFIC_PID=preview-${crypto.randomUUID()}`;}}>Start a fresh preview</button><p>100 fixed assignments · 3 posts per assignment · each post appears in 3 assignments.</p></details>
      </div>}
      {error&&<div className="original100-error" role="alert">{error}</div>}
      {recovered.length>0&&<details className="original100-error"><summary>A newer version was saved in another tab. The saved version is shown; your local draft is preserved here for review.</summary>{recovered.map(d=><div key={d.position}><h3>Local draft for post {d.position}</h3><pre>{d.answer}</pre></div>)}</details>}
      {screen==='loading'&&<section className="source-panel source-intro-panel"><h2>Restoring your session…</h2></section>}
      {screen==='overview'&&<section className="source-panel source-intro-panel">
        <p className="source-eyebrow">Study overview</p><h2>Read three online posts and give your opinion</h2>
        <p className="source-intro-copy">In this task, you will read three public online posts from Reddit. The posts describe social dilemmas and ask for people’s opinions. For each post, you will read the instructions and write one comment.</p>
        <div className="source-overview-grid"><div><span>Task</span><strong>Three posts, one comment per post</strong></div><div><span>Progress</span><strong>Responses save as you write</strong></div></div>
        <div className="source-intro-action"><h3>Ready to review the consent form?</h3><Primary onClick={()=>setScreen('consent')}>Review consent</Primary></div>
      </section>}
      {screen==='consent'&&<div className="source-consent-layout">
        <section className="source-panel source-consent-panel"><p className="source-eyebrow">Participant information</p><h2>Informed Consent</h2><div className="source-consent-text">{consentText}</div></section>
        <aside className="source-panel source-consent-confirmation"><h3>Consent Confirmation</h3><label className="source-consent-checkbox"><input type="checkbox" checked={agreed} onChange={e=>setAgreed(e.target.checked)} /><span>I am at least 18 years old, I have read the consent information, and I voluntarily agree to participate.</span></label><div className="source-button-row"><Secondary disabled={busy} onClick={()=>setScreen('declined')}>I Disagree</Secondary><Secondary disabled={busy} onClick={()=>setScreen('overview')}>Back</Secondary><Primary disabled={!agreed||busy} onClick={()=>{remember();openSession('claim');}}>{busy?'Preparing…':'I Agree'}</Primary></div></aside>
      </div>}
      {screen==='instructions'&&<section className="source-panel source-intro-panel"><p className="source-eyebrow">Instructions</p><h2>Write one comment for each post</h2><div className="source-intro-copy"><p>You will see three posts, one at a time. Read the instructions accompanying each post and enter your response in the comment box.</p><p>Your responses are saved automatically. Use Continue to move to the next post. You can review and edit all three comments before the final submission.</p></div>
        <fieldset className="original100-attention" disabled={busy||session?.attentionCheck?.passed}><legend>Attention check</legend><p>To confirm that you are reading carefully, please select <strong>Blue</strong> for this question.</p><div className="original100-attention-options">{['Green','Blue','Yellow'].map(color=><label key={color}><input type="radio" name="attention-check" value={color.toLowerCase()} checked={session?.attentionCheck?.passed?color==='Blue':attentionChoice===color.toLowerCase()} onChange={e=>setAttentionChoice(e.target.value)} />{color}</label>)}</div></fieldset>
        <p role="status" className="original100-check-feedback">{session?.attentionCheck?.passed?'Attention check completed. You can begin.':attentionFeedback}</p>
        {session?.attentionCheck?.passed?<Primary disabled={busy} onClick={()=>move(1)}>Begin</Primary>:<Primary disabled={busy||!attentionChoice} onClick={checkAttention}>{busy?'Saving…':'Check answer'}</Primary>}
      </section>}
      {screen==='task'&&post&&<>
        <div className="source-task-heading"><h2>Read the post and write your comment</h2><span>Post {index+1} of 3</span></div>
        <div className="original100-task-grid">
          <article className="source-panel source-post-panel"><div className="source-panel-heading"><h3>Instructions and post</h3></div><div className="source-post-text original100-prompt" data-testid="exact-prompt">{post.prompt}</div></article>
          <section className="source-panel original100-response"><label htmlFor="original100-answer">Your comment</label><textarea id="original100-answer" value={answers[index]} readOnly={busy} onChange={e=>edit(index,e.target.value)} placeholder="Write your response here." spellCheck="true" aria-describedby="comment-save" /><p id="comment-save" className="original100-save" role="status">{saveState}</p><div className="source-button-row"><Secondary disabled={busy} onClick={()=>index===0?setScreen('instructions'):move(index)}>{index===0?'Instructions':'Back'}</Secondary><Primary disabled={busy||!validComment(answers[index])} onClick={()=>move(index+2)}>{busy?'Saving…':index===2?'Review answers':'Continue'}</Primary></div><p className="original100-help">Follow the format in the instructions. A judgment abbreviation and reasoning on the next line are required.</p></section>
        </div>
      </>}
      {screen==='review'&&<section className="source-panel source-intro-panel"><p className="source-eyebrow">Final review</p><h2>Review your three comments</h2><p className="source-intro-copy">You can return to any post to make changes. After submission, your responses will be locked.</p>{session.posts.map((p,i)=><article className="original100-review" key={p.stimulusId}><div><h3>Post {i+1}</h3><Secondary disabled={busy} onClick={()=>move(i+1)}>Review post {i+1}</Secondary></div><p>{answers[i]}</p></article>)}<div className="source-button-row"><Secondary disabled={busy} onClick={()=>move(3)}>Back</Secondary><Primary disabled={busy||!answers.every(validComment)} onClick={submit}>{busy?'Submitting…':'Submit all three comments'}</Primary></div></section>}
      {screen==='complete'&&<section className="source-panel source-completion-panel"><div className="source-completion-mark" aria-hidden="true">✓</div><p className="source-eyebrow">Submission complete</p><h2>Thank you for participating</h2><p>All three comments have been saved.</p><p>This study examines how people respond to social dilemmas. The responses will be used for research on written opinions and comparisons with language-model responses.</p>{identity.preview?<p className="original100-preview">Preview completed. These responses are recorded only as test data. No Prolific completion is issued.</p>:session?.completionCode?<a className="source-primary-button" href={`https://app.prolific.com/submissions/complete?cc=${encodeURIComponent(session.completionCode)}`}>Return to Prolific</a>:null}</section>}
      {screen==='declined'&&<section className="source-panel source-completion-panel"><h2>Your participation has ended</h2><p>No completed response was submitted. You may close this page.</p></section>}
      {screen==='error'&&<section className="source-panel source-error-panel"><h2>This session could not be opened</h2><p>Check your connection and reopen the same study link in this browser.</p><Primary disabled={busy} onClick={()=>openSession('claim')}>Try again</Primary></section>}
      {session?.status==='active'&&!['declined','complete','error'].includes(screen)&&<footer className="original100-footer">{showWithdraw?<div><p>End this session and withdraw from the study? Your comments will not count as a completed response.</p><Secondary disabled={busy} onClick={()=>setShowWithdraw(false)}>Keep participating</Secondary> <Secondary disabled={busy} onClick={withdraw}>Confirm withdrawal</Secondary></div>:<button type="button" onClick={()=>setShowWithdraw(true)}>Withdraw from this study</button>}</footer>}
    </div>
  </main>;
}
