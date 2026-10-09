import sys,subprocess,time,json,pathlib,os
root=pathlib.Path(__file__).resolve().parent
trial=sys.argv[1]
out=root/('jev-'+trial)
start_wall=time.time_ns()/1e6
start=time.perf_counter_ns()
r=subprocess.run([os.environ.get('JEV_NATIVE_PATH','jev-native'),'run','--task',str(root/'task.json'),'--out',str(out)],capture_output=True,text=True,timeout=60)
end=time.perf_counter_ns()
end_wall=time.time_ns()/1e6
(root/('jev-'+trial+'-stdout.json')).write_text(r.stdout)
(root/('jev-'+trial+'-stderr.log')).write_text(r.stderr)
report=json.loads((out/'report.json').read_text()) if (out/'report.json').exists() else {}
steps=report.get('steps',[])
obs=[]
for path in out.rglob('observation.json'):
 o=json.loads(path.read_text());obs.append({'path':str(path),'elapsedMS':o.get('elapsedMS')})
final=json.loads(pathlib.Path(report['finalObservation']).read_text()) if report.get('finalObservation') else {}
displays=[n.get('value') for n in final.get('nodes',[]) if n.get('role') in ['AXTextArea','AXTextField','AXStaticText'] and n.get('value')]
result={'tool':'jev_native','trial':trial,'start':start_wall,'end':end_wall,'wallMS':(end-start)/1e6,'exitCode':r.returncode,'status':report.get('status'),'finalNumericValues':displays,'previewEnabled':True,'observations':obs,'steps':[{'index':s.get('index'),'choice':s.get('decision',{}).get('choice'),'action':s.get('action'),'executionMS':s.get('executionMS'),'decision':s.get('decision'),'error':s.get('error')} for s in steps]}
(root/('jev-'+trial+'-timing.json')).write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['observations','steps']},indent=2))
