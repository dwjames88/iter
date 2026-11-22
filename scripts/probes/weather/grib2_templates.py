# Usage: python3 -I grib2_templates.py file.grib2 -- prints each message's discipline/category/number, grid template(3.x), packing template (5.x), npoints
import sys,struct
b=open(sys.argv[1],'rb').read();p=0
while True:
    i=b.find(b'GRIB',p)
    if i<0:break
    tot=struct.unpack('>Q',b[i+8:i+16])[0];disc=b[i+6];q=i+16;info={'disc':disc}
    while q<i+tot-4:
        L=struct.unpack('>I',b[q:q+4])[0];s=b[q+4]
        if s==3: info['gridT']=struct.unpack('>H',b[q+12:q+14])[0];info['npts']=struct.unpack('>I',b[q+6:q+10])[0]
        if s==4: info['cat/num']=(b[q+9],b[q+10]);info['lvl']=b[q+22]
        if s==5: info['packT']=struct.unpack('>H',b[q+9:q+11])[0];info['npk']=struct.unpack('>I',b[q+5:q+9])[0]
        q+=L
    print(info,'msgbytes',tot);p=i+tot
