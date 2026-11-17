"""Independent pure-Python derivation of the TRON test vector used by the Flutter
unit tests (BIP39 seed -> BIP32 m/44h/195h/0h/0/0 -> secp256k1 -> Keccak-256 ->
Base58Check). Run: python tests/derive_vector.py"""
import hashlib, hmac
# --- keccak256 (pre-NIST padding 0x01) ---
RC=[0x0000000000000001,0x0000000000008082,0x800000000000808A,0x8000000080008000,0x000000000000808B,0x0000000080000001,0x8000000080008081,0x8000000000008009,0x000000000000008A,0x0000000000000088,0x0000000080008009,0x000000008000000A,0x000000008000808B,0x800000000000008B,0x8000000000008089,0x8000000000008003,0x8000000000008002,0x8000000000000080,0x000000000000800A,0x800000008000000A,0x8000000080008081,0x8000000000008080,0x0000000080000001,0x8000000080008008]
ROT=[[0,36,3,41,18],[1,44,10,45,2],[62,6,43,15,61],[28,55,25,21,56],[27,20,39,8,14]]
M=(1<<64)-1
def rol(x,n): return ((x<<n)|(x>>(64-n)))&M if n else x
def f(A):
    for rc in RC:
        C=[A[x][0]^A[x][1]^A[x][2]^A[x][3]^A[x][4] for x in range(5)]
        D=[C[(x-1)%5]^rol(C[(x+1)%5],1) for x in range(5)]
        A=[[A[x][y]^D[x] for y in range(5)] for x in range(5)]
        B=[[0]*5 for _ in range(5)]
        for x in range(5):
            for y in range(5): B[y][(2*x+3*y)%5]=rol(A[x][y],ROT[x][y])
        A=[[B[x][y]^((~B[(x+1)%5][y])&B[(x+2)%5][y]) for y in range(5)] for x in range(5)]
        A[0][0]^=rc
    return A
def keccak256(data):
    rate=136; p=bytearray(data)+b'\x01'
    while len(p)%rate: p+=b'\x00'
    p[-1]|=0x80
    A=[[0]*5 for _ in range(5)]
    for i in range(0,len(p),rate):
        blk=p[i:i+rate]
        for j in range(rate//8):
            x,y=j%5,j//5; A[x][y]^=int.from_bytes(blk[8*j:8*j+8],'little')
        A=f(A)
    out=b''.join(A[j%5][j//5].to_bytes(8,'little') for j in range(4))
    return out
assert keccak256(b'').hex()=='c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470'
# secp256k1
P=2**256-2**32-977; N=0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G=(0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)
def add(a,b):
    if a is None: return b
    if b is None: return a
    if a[0]==b[0] and (a[1]+b[1])%P==0: return None
    if a==b: l=3*a[0]*a[0]*pow(2*a[1],-1,P)%P
    else: l=(b[1]-a[1])*pow(b[0]-a[0],-1,P)%P
    x=(l*l-a[0]-b[0])%P; return (x,(l*(a[0]-x)-a[1])%P)
def mul(k,pt=G):
    r=None
    while k:
        if k&1: r=add(r,pt)
        pt=add(pt,pt); k>>=1
    return r
def ser(pt): return bytes([2+(pt[1]&1)])+pt[0].to_bytes(32,'big')
def ckd(k,c,i):
    if i>=2**31: data=b'\x00'+k.to_bytes(32,'big')+i.to_bytes(4,'big')
    else: data=ser(mul(k))+i.to_bytes(4,'big')
    I=hmac.new(c,data,hashlib.sha512).digest()
    return (int.from_bytes(I[:32],'big')+k)%N, I[32:]
A58='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
def b58(b):
    n=int.from_bytes(b,'big'); s=''
    while n: n,r=divmod(n,58); s=A58[r]+s
    return '1'*(len(b)-len(b.lstrip(b'\0')))+s
def b58check(payload): return b58(payload+hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4])
def derive(mn,path=(44+2**31,195+2**31,2**31,0,0)):
    seed=hashlib.pbkdf2_hmac('sha512',mn.encode(),b'mnemonic',2048)
    I=hmac.new(b'Bitcoin seed',seed,hashlib.sha512).digest()
    k,c=int.from_bytes(I[:32],'big'),I[32:]
    for i in path: k,c=ckd(k,c,i)
    pub=mul(k); raw=pub[0].to_bytes(32,'big')+pub[1].to_bytes(32,'big')
    addr=b'\x41'+keccak256(raw)[-20:]
    return k.to_bytes(32,'big').hex(), b58check(addr), addr.hex()
mn=' '.join(['abandon']*11+['about'])
print(derive(mn))
# known vector: privkey 1 -> address
print(b58check(b'\x41'+keccak256(mul(1)[0].to_bytes(32,'big')+mul(1)[1].to_bytes(32,'big'))[-20:]))
