import re,glob,os
def norm(s):
    s=re.sub(r'\x1b\[[0-9;]*m','',s)
    return [w for w in re.sub(r"[^a-z0-9' ]",' ',s.lower()).split() if w]
def wer(r,h):
    d=[[0]*(len(h)+1) for _ in range(len(r)+1)]
    for i in range(len(r)+1): d[i][0]=i
    for j in range(len(h)+1): d[0][j]=j
    for i in range(1,len(r)+1):
        for j in range(1,len(h)+1):
            d[i][j]=min(d[i-1][j]+1,d[i][j-1]+1,d[i-1][j-1]+(r[i-1]!=h[j-1]))
    return d[len(r)][len(h)]/max(1,len(r))
labels={'g_P1':'P1 plain','g_P2':'P2 +punct','g_P3':'P3 +12kw','g_P4':'P4 +100kw'}
tot={k:[0,0] for k in labels}
for n in ['1152f7da','fddef9b5','f30ba90b']:
    r=norm(open(n+'.ref.txt').read())
    row=[]
    for k in labels:
        h=norm(open(f'{n}.{k}.txt').read())
        e=wer(r,h); row.append(f'{labels[k]}={e*100:5.1f}%')
        tot[k][0]+=e*len(r); tot[k][1]+=len(r)
    print(f'{n}  '+'  '.join(row))
print('\nweighted overall:')
for k in labels: print(f'  {labels[k]:12s} {tot[k][0]/tot[k][1]*100:5.1f}%')
