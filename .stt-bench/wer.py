import re,sys
def norm(s):
    s=re.sub(r'\[[^\]]*\]|\x1b\[[0-9;]*m','',s)
    s=re.sub(r'^.*transcription completed in [0-9.]+s: ".*?"','',s,flags=re.S)
    return [w for w in re.sub(r"[^a-z0-9' ]",' ',s.lower()).split() if w]
def wer(r,h):
    d=[[0]*(len(h)+1) for _ in range(len(r)+1)]
    for i in range(len(r)+1): d[i][0]=i
    for j in range(len(h)+1): d[0][j]=j
    for i in range(1,len(r)+1):
        for j in range(1,len(h)+1):
            d[i][j]=min(d[i-1][j]+1,d[i][j-1]+1,d[i-1][j-1]+(r[i-1]!=h[j-1]))
    return d[len(r)][len(h)]/max(1,len(r))
for n in ['1152f7da','fddef9b5','f30ba90b']:
    r=norm(open(n+'.ref.txt').read())
    for sysname in ['turbo','parakeet']:
        h=norm(open(f'{n}.{sysname}.txt').read())
        print(f'{n}  {sysname:9s} refw={len(r):4d}  WER={wer(r,h)*100:5.1f}%')
