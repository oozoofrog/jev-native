from pathlib import Path
import subprocess,os,json,time,statistics,signal,hashlib
root=Path(__file__).resolve().parents[3]
out=root/'.build/ax-query-bench'/os.environ.get('BENCH_TAG','bench')
out.mkdir(exist_ok=True)
cli=root/'dist/JevNative.app/Contents/MacOS/jev-native'; fixture=root/'.build/release/jev-native-fixture'
goals={
'small':('Press Confirm small task once. Finish only when Fixture result reads result=small.','result=small'),
'large':('Press Row 719 in the owned fixture. It is in Rows 700 through 719. Explore unscanned AX regions if it is not in the current candidate page. Finish only when Fixture result reads result=row-719.','result=row-719'),
'long':('In the owned long document fixture press Confirm document once. Do not read or rewrite the document. Finish only when Fixture result reads result=confirm.','result=confirm'),
'duplicates':('Press Apply in Right controls. Do not press Apply in Left controls. Finish only when Fixture result reads result=right.','result=right'),
'dialog':('Open details, then press Confirm details in the dialog. Finish only when Fixture result reads result=confirmed-dialog.','result=confirmed-dialog')}
summary=[]
for scenario in goals:
 for mode in ['legacy','query']:
  runout=out/(scenario+'-'+mode);runout.mkdir(exist_ok=True)
  logfile=runout/'events.jsonl'
  with (runout/'fixture.stdout').open('w') as f:
   proc=subprocess.Popen([str(fixture),'--scenario',scenario,'--log',str(logfile)],stdout=f,stderr=subprocess.STDOUT)
   try:
    time.sleep(.8)
    env=os.environ.copy();env['JEV_AX_LEGACY']='1' if mode=='legacy' else '0'
    observations=[]
    for sample in range(3):
     sampleout=runout/f'observe-{sample}'
     r=subprocess.run([str(cli),'observe','--app',f'pid:{proc.pid}','--no-image','--out',str(sampleout)],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=30)
     if r.returncode: raise RuntimeError(r.stderr.decode()[:800])
     obs=json.loads((sampleout/'observation.json').read_text());m=obs.get('axMetrics',{});observations.append({'nodes':len(obs['nodes']),'truncated':obs['truncated'],'coverage':obs.get('axOverview',{}).get('coverage','partial' if obs['truncated'] else 'unreported'),'collectionMS':m.get('collectionMS'),'calls':sum(m.get(k,0) for k in ['attributeCalls','batchCalls','childCountCalls','childPageCalls','actionCalls','textRangeCalls','observerCalls']),'metrics':m})
    goal,expected=goals[scenario];start=time.perf_counter()
    with (runout/'run.stdout').open('w') as stdout,(runout/'run.stderr').open('w') as stderr:
     r=subprocess.run([str(cli),'run','--goal',goal,'--apps',f'pid:{proc.pid}','--expect-text',expected,'--max-steps','12','--no-preview','--out',str(runout/'run')],env=env,stdout=stdout,stderr=stderr,timeout=180)
    wall=(time.perf_counter()-start)*1000
    report=json.loads((runout/'run/report.json').read_text());decisions=[s['decision'] for s in report['steps'] if s.get('decision')]
    events=[json.loads(x) for x in logfile.read_text().splitlines()] if logfile.exists() else []
    row={'scenario':scenario,'mode':mode,'observationSamples':observations,'status':report['status'],'totalMS':wall,'steps':len(report['steps']),'jevCalls':sum(1+(d.get('verificationApiMS') is not None) for d in decisions),'apiMS':sum(d['apiMS']+(d.get('verificationApiMS') or 0) for d in decisions),'inputTokens':sum(d.get('usage',{}).get('input_tokens',0) for d in decisions),'requestBytes':sum((d.get('requestBytes') or 0)+(d.get('verificationRequestBytes') or 0) for d in decisions),'binarySHA256':hashlib.sha256(cli.read_bytes()).hexdigest(),'fixtureSHA256':hashlib.sha256(fixture.read_bytes()).hexdigest(),'queries':[s.get('query') for s in report['steps'] if s.get('query')],'errors':[s['error'] for s in report['steps'] if s.get('error')],'events':events,'exit':r.returncode}
    summary.append(row);(out/'results.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({k:row[k] for k in ['scenario','mode','status','totalMS','jevCalls','inputTokens','queries','errors','events']}),flush=True)
   finally:
    proc.terminate()
    try:proc.wait(timeout=5)
    except subprocess.TimeoutExpired:proc.kill();proc.wait()
