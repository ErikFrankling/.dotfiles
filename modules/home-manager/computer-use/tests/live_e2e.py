"""Opt-in live MCP test. Operates only the dedicated agent-firefox window.

The loopback page records DOM events as an independent input-delivery oracle;
all navigation, typing, pointer actions and screenshots go through MCP.
"""
import base64
import http.server
import json
import os
from pathlib import Path
import selectors
import socket
import statistics
import uuid
import subprocess
import sys
import threading
import time
import urllib.parse

PAGE = '''<!doctype html><meta charset="utf-8"><title>Agent input test</title>
<style>body{font:24px sans-serif;margin:30px}input{font:24px sans-serif;width:700px}button{font:24px sans-serif;margin:20px}#drag{background:#bde;width:350px;height:100px}#scroll{height:150px;width:500px;overflow:auto;background:#ddd}</style>
<h1>Agent input test</h1><input id="text" autocomplete="off"><button id="button">Click test</button>
<button id="menu-toggle" popovertarget="menu">Open menu</button><div id="menu" popover><button id="menu-item">Choose item</button></div>
<div id="drag">Drag inside this area</div><div id="scroll"><div style="height:1500px">Scroll test</div></div><pre id="result"></pre>
<script>
let sequence=0; document.querySelector('#menu-item').addEventListener('click',()=>{document.body.dataset.selected='yes';document.querySelector('#menu').hidePopover();});
function report(type,e){let t=document.querySelector('#text');fetch('/event?'+encodeURIComponent(JSON.stringify({type,target:e?.target?.id,value:t.value,selected:document.body.dataset.selected,seq:++sequence,trusted:e?.isTrusted,meta:e?.metaKey,ctrl:e?.ctrlKey,shift:e?.shiftKey,key:e?.key,buttons:e?.buttons,scroll:document.querySelector('#scroll').scrollTop,chrome:outerHeight-innerHeight,rects:Object.fromEntries(['text','button','drag','scroll','menu-toggle','menu-item'].map(id=>{let r=document.getElementById(id).getBoundingClientRect();return [id,{x:r.x,y:r.y,width:r.width,height:r.height}]}))})));}
for(let type of ['input','keydown','click','pointerdown','pointerup','pointermove','wheel','toggle'])document.addEventListener(type,e=>report(type,e));
document.querySelector('#scroll').addEventListener('scroll',e=>report('scrolled',e));
document.querySelector('#menu').addEventListener('toggle',e=>report('toggle',e));
report('ready');
</script>'''


def main():
    output = Path(sys.argv[1] if len(sys.argv)>1 else 'output/agent-live-e2e')
    output.mkdir(parents=True, exist_ok=True)
    events=[]
    token=uuid.uuid4().hex
    failures=[]
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path.startswith('/event?') and self.headers.get('Referer','').endswith('/'+token):
                events.append(json.loads(urllib.parse.unquote(self.path.split('?',1)[1])))
                data=b'ok'
            elif self.path == '/'+token: data=PAGE.encode()
            else:
                self.send_error(404);return
            self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.end_headers();self.wfile.write(data)
        def log_message(self,*args): pass
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    proc=subprocess.Popen(['agent-computer-use','mcp'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=(output/'mcp-stderr.log').open('wb'))
    selector=selectors.DefaultSelector();selector.register(proc.stdout,selectors.EVENT_READ)
    buffer=b''; sequence=0; timings=[]
    def rpc(method,params):
        nonlocal sequence,buffer
        sequence+=1; start=time.monotonic()
        proc.stdin.write(json.dumps(dict(jsonrpc='2.0',id=sequence,method=method,params=params)).encode()+b'\n');proc.stdin.flush()
        deadline=start+65
        while time.monotonic()<deadline:
            if b'\n' not in buffer:
                if not selector.select(max(0,deadline-time.monotonic())):raise TimeoutError(method)
                chunk=os.read(proc.stdout.fileno(),65536)
                if not chunk:raise RuntimeError('MCP disconnected')
                buffer+=chunk
            while b'\n' in buffer:
                line,buffer=buffer.split(b'\n',1);r=json.loads(line)
                if r.get('id')==sequence:
                    if 'error' in r:raise RuntimeError(r)
                    timings.append({'method':params.get('name',method),'ms':round((time.monotonic()-start)*1000,1)})
                    return r['result']
        raise TimeoutError(method)
    def call(name,args=None,allow_error=False):
        result=rpc('tools/call',{'name':name,'arguments':args or {}})
        if result.get('isError') and not allow_error:raise RuntimeError(result)
        for item in result.get('content',[]):
            if item['type']=='image':
                (output/f'capture-{sequence}.png').write_bytes(base64.b64decode(item['data']))
        if result.get('isError'):return result
        if 'structuredContent' in result:return result['structuredContent']
        return json.loads(next(c['text'] for c in result['content'] if c['type']=='text'))
    def wait_event(predicate,timeout=8,after=0):
        end=time.monotonic()+timeout
        while time.monotonic()<end:
            found=next((e for e in reversed(events) if e['seq']>after and predicate(e)),None)
            if found:return found
            time.sleep(.05)
        raise AssertionError('Expected browser event was not received; events='+json.dumps(events[-5:]))
    def focus():
        result=subprocess.run(['hyprctl','-i','0','-j','activewindow'],stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=3,check=True)
        devices=subprocess.run(['hyprctl','-i','0','-j','devices'],stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=3,check=True)
        return {'address':json.loads(result.stdout).get('address'),'main_keyboards':sorted(k['name'] for k in json.loads(devices.stdout)['keyboards'] if k.get('main'))}
    focus_checks=[]
    try:
        rpc('initialize',{'protocolVersion':'2025-03-26','capabilities':{},'clientInfo':{'name':'agent-live-e2e','version':'1'}})
        proc.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n');proc.stdin.flush()
        state=call('computer_status');assert state['input_mode']=='independent-seat' and not state['paused']
        windows=call('list_windows')['windows']
        targets=[w for w in windows if w['class']=='agent-firefox' and w['workspace']['name']=='agent']
        assert len(targets)==1,targets
        w=targets[0];wid=w['id']
        permission=call('request_permission',{'capability':'control','scope':{'kind':'window','id':wid},'reason':'Local end-to-end input regression test'})
        if permission['status']=='approval_required':
            assert call('wait_for_permission',{'request_id':permission['request_id'],'seconds':10})['status']=='granted'
        call('view_window',{'window_id':wid})
        def act(actions,**extra):
            nonlocal w
            w=next(v for v in call('list_windows')['windows'] if v['id']==wid)
            assert w['class']=='agent-firefox' and w['workspace']['name']=='agent'
            before=focus()
            result=call('input_window',{'window_id':wid,'revision':w['revision'],'actions':actions,**extra})
            after=focus()
            focus_checks.append({'before':before,'after':after})
            assert before['main_keyboards']==after['main_keyboards'], 'Native main keyboard changed during agent input'
            assert after['address']!=w.get('address'), 'Agent input activated the agent window on the native seat'
            return result
        act([{'type':'key','key':'CTRL+T'},{'type':'key','key':'CTRL+L'},{'type':'text','text':f'http://127.0.0.1:{server.server_port}/{token}'},{'type':'key','key':'ENTER'}])
        ready=wait_event(lambda e:e['type']=='ready')
        call('view_window',{'window_id':wid})
        def point(name,dx=20,dy=20):
            current=max(events,key=lambda e:e['seq'])
            r=current['rects'][name];return {'x':r['x']+dx,'y':r['y']+ready['chrome']+dy}
        act([{'type':'click',**point('text')},{'type':'text','text':'Agent åäö 漢字 ✓ 123'}],then='screenshot',observation={'delay_ms':200})
        wait_event(lambda e:e['type']=='input' and e['target']=='text' and e['trusted'] and e['value']=='Agent åäö 漢字 ✓ 123')
        act([{'type':'key','key':'CTRL+A'},{'type':'text','text':'replacement'}])
        wait_event(lambda e:e['type']=='input' and e['target']=='text' and e['trusted'] and e['value']=='replacement')
        marker=max(e['seq'] for e in events)
        act([{'type':'click',**point('button')}])
        wait_event(lambda e:e['type']=='click' and e['target']=='button' and e['trusted'],after=marker)
        marker=max(e['seq'] for e in events)
        act([{'type':'click',**point('menu-toggle')}])
        wait_event(lambda e:e['type']=='click' and e['target']=='menu-toggle',after=marker)
        # HTML top-layer popover: this does not claim native xdg_popup support.
        wait_event(lambda e:e['type']=='toggle' and e['rects']['menu-item']['width']>0,after=marker)
        marker=max(e['seq'] for e in events)
        act([{'type':'click',**point('menu-item')}])
        wait_event(lambda e:e['type']=='click' and e['target']=='menu-item' and e['selected']=='yes' and e['trusted'],after=marker)
        act([{'type':'drag',**point('drag'),'to_x':point('drag')['x']+180,'to_y':point('drag')['y']+30}])
        wait_event(lambda e:e['type']=='pointermove' and e['target']=='drag' and e['buttons']==1 and e['trusted'])
        act([{'type':'scroll',**point('scroll'),'delta_x':0,'delta_y':4,'unit':'wheel_steps'}])
        wait_event(lambda e:e['type']=='scrolled' and e['target']=='scroll' and e['scroll']>0)
        for args in [dict(revision='stale',actions=[{'type':'text','text':'MUST_NOT_TYPE'}]),dict(actions=[{'type':'focus'}])]:
            request={'window_id':wid,'revision':w['revision'],**args}
            refused=call('input_window',request,True);assert refused.get('isError'),refused
        assert not any('MUST_NOT_TYPE' in e.get('value','') for e in events)
        # Request only; never send even a supposedly refused input to a human window.
        human=next((v for v in windows if v['workspace']['name']!='agent'),None)
        assert human is not None, 'No human window available for permission boundary test'
        refused=call('request_permission',{'capability':'control','scope':{'kind':'window','id':human['id']},'reason':'Regression test: must not auto-grant human window'})
        assert refused['status']=='approval_required',refused
        decision=call('wait_for_permission',{'request_id':refused['request_id'],'seconds':2})
        assert decision['status']!='granted',decision
        assert not any(e.get('meta') for e in events),'Agent unexpectedly received Super modifier'
        call('view_window',{'window_id':wid,'region':{'x':0,'y':0,'width':600,'height':400},'max_width':600})
        with socket.create_connection(('127.0.0.1',5903),timeout=3) as vnc:assert vnc.recv(12).startswith(b'RFB ')
        # Close only the disposable tab created by this run, after all checks pass.
        act([{'type':'key','key':'CTRL+W'}])
        print(json.dumps({'status':'passed','checks':['stdio MCP','permission supervisor','navigation','screenshot','Unicode text','keyboard chords','target-verified click','HTML popover menu','human permission not auto-granted','native keyboard unchanged and agent never activated','drag','scroll','stale geometry refusal','focus refusal','cropped screenshot','VNC handshake'],'native_focus_unchanged':all(c['before']==c['after'] for c in focus_checks),'timings':timings,'latency_ms':{'median':statistics.median(t['ms'] for t in timings),'max':max(t['ms'] for t in timings)},'limitations':['Native popup protocol and concurrent held human modifiers require separate tests']},indent=2))
    except BaseException as error:
        failures.append(str(error))
        raise
    finally:
        (output/'focus-checks.json').write_text(json.dumps(focus_checks,indent=2))
        (output/'failures.json').write_text(json.dumps(failures,indent=2))
        (output/'events.json').write_text(json.dumps(events,indent=2))
        (output/'timings.json').write_text(json.dumps(timings,indent=2))
        proc.terminate()
        try:proc.wait(timeout=5)
        except subprocess.TimeoutExpired:proc.kill();proc.wait(timeout=5)
        selector.close()
        proc.stdin.close();proc.stdout.close()
        server.shutdown();server.server_close()

if __name__=='__main__':main()
