"""Generate PAWPAY's original, code-native capsule machine mesh. Stdlib only.
Run from any directory: python tools/build_gacha_model.py
Coordinates: +Y up, +Z front; colors are resolved from AppPalette at runtime.
"""
from pathlib import Path
import json
import math

class Mesh:
    def __init__(self): self.faces=[]
    def face(self, points, material):
        self.faces.append({'p':[[round(v,5) for v in p] for p in points], 'm':material})


def add(a,b): return [a[i]+b[i] for i in range(3)]

def ring(cx,cy,w,h,r,n=5):
    out=[]
    for x,y,start in [(cx+w/2-r,cy+h/2-r,0),(cx-w/2+r,cy+h/2-r,90),
                       (cx-w/2+r,cy-h/2+r,180),(cx+w/2-r,cy-h/2+r,270)]:
        for i in range(n+1):
            a=math.radians(start+i*90/n)
            out.append([x+r*math.cos(a),y+r*math.sin(a)])
    return out


def rounded_box(mesh,center,w,h,d,r,mat,bevel=.035):
    x,y,z=center
    bevel=min(bevel,d*.45,r*.5)
    layers=[]
    for zz,inset in [(-d/2,bevel),(-d/2+bevel,0),(d/2-bevel,0),(d/2,bevel)]:
        layers.append([[xx,yy,z+zz] for xx,yy in ring(x,y,w-inset*2,h-inset*2,r-inset)])
    for a,b in zip(layers,layers[1:]):
        for i in range(len(a)):
            j=(i+1)%len(a)
            mesh.face([a[i],a[j],b[j],b[i]],mat)
    # Keep planar end caps intact: fan triangles at different average depths
    # can incorrectly overlap front-mounted details in a Canvas renderer.
    mesh.face(layers[-1],mat)
    mesh.face(list(reversed(layers[0])),mat)


def lathe(mesh,profile,center,mat,n=28):
    rings=[]
    for r,y in profile:
        rings.append([add(center,[r*math.cos(i*math.tau/n),y,r*math.sin(i*math.tau/n)]) for i in range(n)])
    for a,b in zip(rings,rings[1:]):
        for i in range(n):
            j=(i+1)%n
            mesh.face([a[i],b[i],b[j],a[j]],mat)


def sphere(mesh,center,radii,mat,rings=8,slices=16,split=None):
    for j in range(rings):
        def at(k,i):
            a=math.pi*k/rings; b=math.tau*i/slices
            return add(center,[radii[0]*math.sin(a)*math.cos(b),radii[1]*math.cos(a),radii[2]*math.sin(a)*math.sin(b)])
        for i in range(slices):
            material=mat if split is None or j<rings/2 else split
            pts=[at(j,i),at(j+1,i),at(j+1,i+1),at(j,i+1)]
            # Outward winding; triangular pole faces avoid zero normals.
            if j==0: pts=[pts[0],pts[1],pts[2]]
            elif j==rings-1: pts=[pts[0],pts[1],pts[3]]
            mesh.face(list(reversed(pts)),material)


def disk_z(mesh,center,radius,depth,mat):
    temp=Mesh()
    lathe(temp,[(0,-depth/2),(radius*.88,-depth/2),(radius,-depth*.2),
                (radius,depth*.2),(radius*.88,depth/2),(0,depth/2)],(0,0,0),mat,n=24)
    for f in temp.faces:
        mesh.face([add(center,[p[0],-p[2],p[1]]) for p in f['p']],mat)


def ear(mesh,x,mat,inner=False):
    scale=.63 if inner else 1
    y=2.64+(.015 if inner else 0)
    triangle=[(x-.21*scale,y),(x+.20*scale,y),(x+.045*scale,y+.36*scale)]
    points=[]
    for i,tip in enumerate(triangle):
        previous=triangle[(i-1)%3]; following=triangle[(i+1)%3]
        start=[tip[j]+(previous[j]-tip[j])*.18 for j in range(2)]
        end=[tip[j]+(following[j]-tip[j])*.18 for j in range(2)]
        for step in range(6):
            t=step/5
            points.append([(1-t)**2*start[j]+2*t*(1-t)*tip[j]+t*t*end[j] for j in range(2)])
    zz=.15 if inner else .03; thick=.02 if inner else .18
    a=[[p[0],p[1],zz+thick/2] for p in points]; b=[[p[0],p[1],zz-thick/2] for p in points]
    mesh.face(a,mat);mesh.face(list(reversed(b)),mat)
    for i in range(len(a)):
        j=(i+1)%len(a);mesh.face([b[i],b[j],a[j],a[i]],mat)


def paw(mesh,center,size,mat):
    x,y,z=center
    sphere(mesh,(x,y-size*.10,z),(size*.26,size*.21,size*.055),mat,rings=6,slices=12)
    for dx,dy in [(-.32,.16),(-.12,.36),(.13,.36),(.33,.16)]:
        sphere(mesh,(x+dx*size,y+dy*size,z),(size*.11,size*.14,size*.05),mat,rings=6,slices=10)


def build():
    body=Mesh()
    lathe(body,[(0,0),(1.04,0),(1.08,.035),(1.08,.09),(1.04,.13),(0,.13)],(0,.02,0),'stage',n=40)
    lathe(body,[(0,0),(.99,0),(.99,.015),(0,.015)],(0,.155,0),'cream',n=40)
    for x in [-.50,.50]:
        for z in [-.31,.31]:
            sphere(body,(x,.24,z),(.17,.11,.17),'rose',rings=6,slices=12)
    rounded_box(body,(0,.80,0),1.48,1.09,1.02,.23,'rose',bevel=.085)
    rounded_box(body,(0,.795,.527),1.27,.87,.065,.20,'cream',bevel=.02)
    # Outlet frame, dark recess and little scoop tray.
    rounded_box(body,(0,.51,.58),.79,.34,.10,.10,'trim',bevel=.025)
    rounded_box(body,(0,.52,.641),.63,.22,.015,.065,'recess',bevel=.006)
    rounded_box(body,(0,.355,.68),.76,.075,.32,.035,'cream',bevel=.02)
    rounded_box(body,(0,.386,.70),.57,.02,.22,.009,'soft',bevel=.005)
    # The crank is a separate animated mesh, in local coordinates.
    disk_z(body,(-.22,.96,.612),.205,.085,'trim')
    disk_z(body,(-.22,.96,.664),.171,.04,'soft')
    rounded_box(body,(.36,1.04,.579),.20,.11,.025,.04,'trim',bevel=.008)
    rounded_box(body,(.36,1.04,.598),.125,.02,.012,.009,'recess',bevel=.003)
    # A separate PAWPAY nameplate above the dial.
    rounded_box(body,(0,1.285,.585),.72,.14,.06,.06,'cream',bevel=.018)
    lathe(body,[(0,0),(.70,0),(.765,.045),(.765,.11),(.70,.155),(0,.155)],(0,1.29,0),'rose')
    lathe(body,[(0,0),(.72,0),(.735,.025),(.72,.05),(0,.05)],(0,1.42,0),'trim')
    # Side hardware makes the depth readable even at rest.
    for x in [-.76,.76]:
        sphere(body,(x,.95,0),(.065,.12,.17),'cream',rings=6,slices=12)
    lathe(body,[(0,0),(.56,0),(.68,.055),(.69,.105),(.63,.155),(0,.155)],(0,2.57,0),'rose',n=32)
    lathe(body,[(0,0),(.61,0),(.64,.025),(.59,.055),(0,.055)],(0,2.70,0),'cream',n=32)
    for x in [-.40,.40]: ear(body,x,'cream');ear(body,x,'ear',True)
    glass=Mesh(); sphere(glass,(0,2.005,0),(.748,.674,.648),'glass',rings=12,slices=28)
    # Narrow strips on the glass are actual surface geometry, not a flat sticker.
    highlights=Mesh()
    for start,end,width,mat in [(.43,1.43,.09,'shine'),(.51,1.03,.035,'shineSoft')]:
        angle=-.74 if mat=='shine' else .66
        for j in range(12):
            def point(t,a):return [.752*math.sin(t)*math.sin(a),2.005+.678*math.cos(t),.652*math.sin(t)*math.cos(a)]
            t=start+(end-start)*j/12;u=start+(end-start)*(j+1)/12
            highlights.face([point(t,angle-width),point(u,angle-width),point(u,angle+width),point(t,angle+width)],mat)
    crank=Mesh()
    rounded_box(crank,(0,0,.018),.275,.071,.075,.034,'rose',bevel=.025)
    disk_z(crank,(0,0,.06),.072,.035,'cream')
    paw(crank,(0,-.008,.083),.12,'ink')
    capsule=Mesh(); sphere(capsule,(0,0,0),(1,1,1),'capsuleTop',rings=8,slices=12,split='capsuleColor')
    lathe(capsule,[(1.007,-.025),(1.008,.025)],(0,0,0),'capsuleSeam',n=20)
    poses=[[-.32,1.64,-.19,.158], [.02,1.63,-.22,.16], [.35,1.66,-.14,.15],
           [-.31,1.62,.18,.158], [.03,1.60,.23,.16], [.36,1.67,.20,.153],
           [-.45,1.89,-.05,.15],[-.12,1.90,-.17,.158],[.21,1.94,-.08,.16],
           [-.20,1.92,.20,.16],[.16,1.94,.25,.15],[.0,2.24,.02,.158]]
    return {'format':1,'name':'PAWPAY Paw Capsule Atelier','crank_origin':[-.22,.96,.70],
      'meshes':{'body':body.faces,'glass':glass.faces,'highlights':highlights.faces,
                'crank':crank.faces,'capsule':capsule.faces},'capsules':poses}

if __name__=='__main__':
    root=Path(__file__).resolve().parents[1]
    destination=root/'assets/models/paw_gacha.json';destination.parent.mkdir(parents=True,exist_ok=True)
    model=build();destination.write_text(json.dumps(model,separators=(',',':'))+'\n')
    print('Generated',destination.name,':',sum(len(v) for v in model['meshes'].values()),'mesh faces; 12 capsule instances')
