#!/usr/bin/env python3
"""Offline cross-check (NOT the Dart code): a Python port of the IPv6 classification in
lib/services/url_normalizer.dart and of lib/services/net_guard.dart, compared on a fixed
table plus a 300k-address structured random sweep. Exit code 1 on any mismatch.

It only proves the *logic as ported*; the Dart tests (test/ip_parity_test.dart) are the real
gate and must pass in CI. If either Dart file changes, update this port or ignore it.
"""
import random
import sys
import re
def hexval(c):
    if '0'<=c<='9': return ord(c)-48
    if 'a'<=c<='f': return ord(c)-87
    if 'A'<=c<='F': return ord(c)-55
    return -1
def v4kind(a,b,c):
    if a==0: return 'unspecified'
    if a==127: return 'loopback'
    if a==10: return 'private'
    if a==172 and 16<=b<=31: return 'private'
    if a==192 and b==168: return 'private'
    if a==100 and 64<=b<=127: return 'private'
    if a==169 and b==254: return 'linklocal'
    if (a,b,c) in ((192,0,2),(198,51,100),(203,0,113)): return 'documentation'
    if (a==192 and b==0 and c==0) or (a==192 and b==88 and c==99) or (a==198 and b in (18,19)) or a>=224: return 'reserved'
    return 'public'
def parse_v4(host):
    parts=host.split('.')
    if len(parts)>1 and parts[-1]=='' : parts.pop()
    if not parts or len(parts)>4: return None
    nums=[]
    for p in parts:
        if p=='': return None
        radix=10; s=p
        if len(s)>=2 and s[:2].lower()=='0x': radix=16; s=s[2:]
        elif len(s)>=2 and s[0]=='0': radix=8; s=s[1:]
        v=0
        if s:
            z=0
            while z<len(s)-1 and s[z]=='0': z+=1
            s=s[z:]
            if len(s)>11: return None
            for ch in s:
                h=hexval(ch)
                if h<0 or h>=radix: return None
                v=v*radix+h
        nums.append(v)
    for x in nums[:-1]:
        if x>255: return None
    limit=256**(5-len(nums))
    if nums[-1]>=limit: return None
    v=nums[-1]; w=16777216
    for x in nums[:-1]:
        v+=x*w; w//=256
    a=(v//16777216)%256; b=(v//65536)%256; c=(v//256)%256; d=v%256
    return dict(canonical=f'{a}.{b}.{c}.{d}', kind=v4kind(a,b,c))
def strict_v4(s):
    p=s.split('.')
    if len(p)!=4: return False
    for x in p:
        if not x or len(x)>3 or not x.isdigit() or not x.isascii(): return False
        if int(x)>255: return False
    return True
def parse_v6(s, fixed=True):
    if not s or len(s)>45: return None
    for c in s:
        if not (c==':' or c=='.' or hexval(c)>=0): return None
    if ':::' in s: return None
    dbl=s.find('::')
    if dbl>=0 and s.find('::',dbl+1)>=0: return None
    head=s[:dbl] if dbl>=0 else s
    tail=s[dbl+2:] if dbl>=0 else ''
    allg=([] if not head else head.split(':'))+([] if not tail else tail.split(':'))
    count=0
    for i,g in enumerate(allg):
        if g=='': return None
        if '.' in g:
            if i!=len(allg)-1 or not strict_v4(g): return None
            count+=2
        else:
            if len(g)>4: return None
            count+=1
    if (count>7) if dbl>=0 else (count!=8): return None
    def parse_words(part):
        if part=='': return []
        res=[]
        groups=part.split(':')
        for i,g in enumerate(groups):
            if '.' in g:
                if i!=len(groups)-1 or not strict_v4(g): return None
                o=[int(x) for x in g.split('.')]
                res+= [(o[0]<<8)|o[1], (o[2]<<8)|o[3]]
            else:
                try: v=int(g,16)
                except: return None
                if v>0xffff: return None
                res.append(v)
        return res
    hw=parse_words(head); tw=parse_words(tail)
    if hw is None or tw is None: return None
    explicit=len(hw)+len(tw)
    if dbl>=0:
        z=8-explicit
        if z<1: return None
        words=hw+[0]*z+tw
    else:
        if explicit!=8: return None
        words=hw+tw
    if len(words)!=8: return None
    def emb(hi,lo):
        a='.'.join(map(str,[hi>>8,hi&0xff,lo>>8,lo&0xff]))
        r=parse_v4(a)
        return r['kind'] if r else 'reserved'
    first=words[0]
    kind='public'
    if all(w==0 for w in words[:7]) and words[7]<=1:
        kind='unspecified' if words[7]==0 else 'loopback'
    elif all(w==0 for w in words[:5]) and words[5]==0xffff: kind=emb(words[6],words[7])
    elif all(w==0 for w in words[:6]):
        e=emb(words[6],words[7]); kind='reserved' if e=='public' else e
    elif first==0x64 and words[1]==0xff9b:
        kind=emb(words[6],words[7]) if all(w==0 for w in words[2:6]) else 'reserved'
    elif first==0x2002: kind=emb(words[1],words[2])
    elif first==0x2001 and words[1]<0x0200: kind='reserved'
    elif first==0x100 and all(w==0 for w in words[1:4]): kind='reserved'
    elif (first&0xffc0)==0xfe80: kind='linklocal'
    elif (first&0xffc0)==0xfec0: kind='reserved'
    elif (first&0xfe00)==0xfc00: kind='private'
    elif (first&0xff00)==0xff00: kind='reserved'
    elif words[0]==0x2001 and words[1]==0x0db8: kind='documentation'
    elif first==0x3fff and (words[1]&0xf000)==0: kind='documentation'
    elif (first&0xe000)!=0x2000: kind='reserved'
    return dict(canonical=s, kind=kind, words=words)

def blocked_v4(b0,b1,b2,b3):
    if b0==0: return True
    if b0==10: return True
    if b0==100 and (b1&0xC0)==64: return True
    if b0==127: return True
    if b0==169 and b1==254: return True
    if b0==172 and (b1&0xF0)==16: return True
    if b0==192 and b1==0 and b2==0: return True
    if b0==192 and b1==0 and b2==2: return True
    if b0==192 and b1==88 and b2==99: return True
    if b0==192 and b1==168: return True
    if b0==198 and (b1&0xFE)==18: return True
    if b0==198 and b1==51 and b2==100: return True
    if b0==203 and b1==0 and b2==113: return True
    if b0>=224: return True
    return False
def netguard_v6(words):
    b=[]
    for w in words: b+= [w>>8, w&0xff]
    def zeros(f,t): return all(b[i]==0 for i in range(f,t))
    if zeros(0,15) and b[15] in (0,1): return True
    if zeros(0,12): return True
    if zeros(0,10) and b[10]==0xff and b[11]==0xff: return blocked_v4(*b[12:16])
    if b[0]==0 and b[1]==0x64 and b[2]==0xff and b[3]==0x9b:
        if zeros(4,12): return blocked_v4(*b[12:16])
        return True
    if b[0]==0xfe and (b[1]&0xC0)==0x80: return True
    if b[0]==0xfe and (b[1]&0xC0)==0xC0: return True
    if (b[0]&0xFE)==0xFC: return True
    if b[0]==0xff: return True
    if b[0]==0x20 and b[1]==0x01 and b[2]<=0x01: return True
    if b[0]==0x20 and b[1]==0x01 and b[2]==0x0d and b[3]==0xb8: return True
    if b[0]==0x3f and b[1]==0xff and (b[2]&0xF0)==0: return True
    if b[0]==0x20 and b[1]==0x02: return blocked_v4(*b[2:6])
    if b[0]==0x01 and zeros(1,8): return True
    if (b[0]&0xE0)!=0x20: return True
    return False

def parity(words):
    # reconstruct a canonical text so parse_v6 is exercised too
    txt=':'.join('%x'%w for w in words)
    r=parse_v6(txt)
    assert r is not None, txt
    return r['kind']!='public', netguard_v6(words), r['kind'], txt

table=['::','::1','::808:808','::2','::c0a8:101','::ffff:8.8.8.8','::ffff:127.0.0.1','64:ff9b::808:808','64:ff9b::7f00:1',
 '64:ff9b:1::1','64:ff9b:2::1','64:ff9b::1:808:808','2001:20::1','2001:100::1','2001:200::1','2001:4860:4860::8888','3fff::1','3fff:fff::1','3fff:1000::1',
 '4000::1','8000::1','e000::1','2a00:1450::1','2606:4700::1','2002:808:808::','2002:7f00:1::','2002:c0a8:101::','100::1','100:0:0:1::1','fe80::1','fec0::1','fd00::1','ff02::1','2001:db8::1','2001:0::1','::ffff:0:808:808','::1:808:808']
bad=0
for t in table:
    from_text=parse_v6(t)
    words=from_text['words']
    nb,ng,kind,_=parity(words)
    flag='OK ' if nb==ng else 'MISMATCH'
    if nb!=ng: bad+=1
    print(flag,t.ljust(24),kind.ljust(14),'normalizer_nonpublic=%s netguard_blocked=%s'%(nb,ng))
# randomized structured sweep over prefixes
random.seed(7)
pre=[0,1,0x20,0x64,0x100,0x2001,0x2002,0x2606,0x2a00,0x3fff,0x4000,0x8000,0xfc00,0xfd00,0xfe80,0xfec0,0xff00,0xffff,0x3ffe,0x5f00,0x2000,0x2fff,0x3000]
cnt=0
for _ in range(300000):
    w=[random.choice(pre) if i==0 else random.choice([0,0,0,1,0xffff,0xff9b,0x200,0x1ff,0xdb8,0x0fff,0x1000,random.randrange(65536)]) for i in range(8)]
    if random.random()<0.4: w[random.randrange(2,6)]=0
    if random.random()<0.3: w[0]=random.choice([0,0x64])
    if random.random()<0.3: 
        for i in range(1,6): w[i]=0
    if random.random()<0.2: w[5]=0xffff
    nb,ng,kind,txt=parity(w)
    cnt+=1
    if nb!=ng:
        bad+=1
        if bad<15: print('MISMATCH',txt,kind,nb,ng)
print('sweep',cnt,'cases; mismatches total =',bad)
sys.exit(1 if bad else 0)
