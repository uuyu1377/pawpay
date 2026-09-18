"""Original PAWPAY terrain and toy buildings. Stdlib; run to regenerate assets.
Route array indices are display-only and preserve the existing game's order.
"""
from pathlib import Path
import json,math
from build_gacha_model import Mesh,rounded_box,sphere,lathe,add
ROOT=Path(__file__).resolve().parents[1]

COAST=[(.38,-2.15),(.69,-2.03),(.97,-1.72),(1.18,-1.27),(1.28,-.75),
 (1.22,-.18),(1.05,.40),(.76,.98),(.42,1.56),(.10,2.05),(-.10,2.19),
 (-.33,1.91),(-.57,1.51),(-.88,1.06),(-1.10,.52),(-1.20,-.06),
 (-1.13,-.65),(-.94,-1.15),(-.63,-1.59),(-.20,-1.94)]
SKY=[(0,.28,-1.67,.81,.58,4),(1.19,.17,-.65,.58,.75,4),
 (1.11,.43,.82,.63,.68,4),(-.03,.12,1.79,.86,.58,4),
 (-1.24,.37,.74,.57,.72,3),(-1.23,.19,-.73,.58,.73,3)]


def smooth(points,steps=4):
    out=[]
    for i in range(len(points)):
        a,b,c,d=[points[j%len(points)] for j in [i-1,i,i+1,i+2]]
        for k in range(steps):
            t=k/steps
            out.append(tuple(.5*(2*b[j]+(-a[j]+c[j])*t+(2*a[j]-5*b[j]+4*c[j]-d[j])*t*t+(-a[j]+3*b[j]-3*c[j]+d[j])*t*t*t) for j in range(2)))
    return out


def resample(points,n):
    ps=points+[points[0]];dist=[0]
    for a,b in zip(ps,ps[1:]):dist.append(dist[-1]+math.dist(a,b))
    out=[];k=1
    for i in range(n):
        t=dist[-1]*i/n
        while k<len(ps)-1 and dist[k]<t:k+=1
        f=(t-dist[k-1])/(dist[k]-dist[k-1]);out.append(tuple(ps[k-1][j]+f*(ps[k][j]-ps[k-1][j]) for j in range(2)))
    return out


def island(mesh,outline,y,top,side,bottom=-.20,tip=None):
    cx=sum(p[0] for p in outline)/len(outline);cz=sum(p[1] for p in outline)/len(outline)
    # Up-facing outline; terrain is deliberately its own render layer.
    mesh.face([[x,y,z] for x,z in reversed(outline)],top)
    for i,(x,z) in enumerate(outline):
        xx,zz=outline[(i+1)%len(outline)]
        mesh.face([[x,y,z],[xx,y,zz],[xx,bottom,zz],[x,bottom,z]],side)
        if tip is not None:
            mesh.face([[x,bottom,z],[xx,bottom,zz],[tip[0],tip[1],tip[2]]],
              ['#BDACC8','#CEBCD1','#E1CFD8'][i%3])


def ellipse(cx,cz,rx,rz,n=32,wobble=0):
    return [(cx+rx*math.cos(a)*(1+wobble*math.sin(3*a)),cz+rz*math.sin(a)*(1+wobble*math.sin(3*a))) for a in [i*math.tau/n for i in range(n)]]


def ribbon(mesh,points,width,color):
    for a,b in zip(points,points[1:]):
        dx,dz=b[0]-a[0],b[2]-a[2];length=math.hypot(dx,dz)
        if length<1e-7:continue
        ox,oz=-dz/length*width/2,dx/length*width/2
        mesh.face([[a[0]+ox,a[1],a[2]+oz],[b[0]+ox,b[1],b[2]+oz],
                   [b[0]-ox,b[1],b[2]-oz],[a[0]-ox,a[1],a[2]-oz]],color)


def cylinder(mesh,center,r,h,color):
    lathe(mesh,[(0,0),(r,0),(r,h),(0,h)],center,color,n=12)


def cone(mesh,center,r,h,color):
    lathe(mesh,[(r,0),(0,h)],center,color,n=12)


def tree(mesh,p,r=.10,sky=False):
    cylinder(mesh,p,r*.18,.14,'#C19B77')
    sphere(mesh,add(p,(0,.18,0)),(r,r*1.15,r),'#B8D7BC' if sky else '#8DB58D',rings=5,slices=8)
    sphere(mesh,add(p,(r*.3,.25,-r*.15)),(r*.74,r*.80,r*.70),'#D2E5C5' if sky else '#B1CD95',rings=5,slices=8)


def gem(mesh,p,r=.10,h=.26,color='#B6A9D7'):
    lathe(mesh,[(0,-h*.25),(r,0),(r*.8,h*.60),(0,h)],p,color,n=6)


def window(mesh,p,w=.047,h=.065):
    rounded_box(mesh,p,w,h,.007,.009,'#91BECC',bevel=.002)


def tower(mesh,p,r=.16,h=.40,color='#FCF1E4',roof='#C5AFDF'):
    cylinder(mesh,p,r,h,color)
    lathe(mesh,[(r*1.25,0),(r*1.3,.025),(0,.26)],add(p,(0,h,0)),roof,n=12)
    for x in [-r*.42,r*.42]:window(mesh,add(p,(x,h*.58,r+.008)),.034,.063)


def mountain(mesh,p,r,h,color):
    # Rounded, low hills, intentionally smaller than the settlements.
    lathe(mesh,[(r,0),(r*.94,h*.24),(r*.64,h*.70),(r*.20,h),(0,h*1.015)],p,color,n=9)


def house(level,sky):
    m=Mesh();cylinder(m,(0,0,0),.12,.034,'tile')
    h=.13+min(level,3)*.043
    if sky:
        tower(m,(0,.035,0),.084,h,'#F9F1E6','roof')
        if level>1:gem(m,(-.095,.055,-.08),.034,.13,'#A7D5CC')
    else:
        rounded_box(m,(0,.035+h/2,0),.18,h,.17,.028,'#F7ECD8',bevel=.016)
        y=.035+h
        a=(-.119,y,-.114);b=(.119,y,-.114);c=(.119,y,.114);d=(-.119,y,.114)
        r1=(0,y+.10,-.114);r2=(0,y+.10,.114)
        for face in [[a,d,r2,r1],[r1,r2,c,b],[a,r1,b],[c,r2,d]]:m.face(face,'roof')
        for x in [-.048,.045]:window(m,(x,.08+h*.23,.091),.038,.052)
        rounded_box(m,(.015,.073,.093),.036,.07,.008,.012,'#B99374',bevel=.003)
        if level>1:cylinder(m,(-.050,y+.047,-.028),.018,.07,'#F3E6D0')
    return compact_building(m.faces)


def feature(kind,sky):
    m=Mesh();cylinder(m,(0,0,0),.12,.034,'tile')
    if kind=='start':
        if sky:
            for x in [-.084,.084]:cylinder(m,(x,.035,0),.025,.26,'#F2D79B')
            # Arch set in the XY plane.
            for i in range(14):
                a=i*math.pi/14;b=(i+1)*math.pi/14
                def at(t,r):return (r*math.cos(t),.295+r*math.sin(t),.012)
                m.face([at(a,.11),at(b,.11),at(b,.074),at(a,.074)],'#F2D79B')
            gem(m,(0,.13,0),.045,.10,'#C2DFDC')
        else:
            cylinder(m,(-.025,.035,0),.012,.27,'#C19779')
            m.face([(-.025,.30,0),(.105,.26,0),(-.025,.22,0)],'#E8938F')
    elif kind=='chance':
        if sky:
            cylinder(m,(0,.04,0),.095,.06,'#ECDFC6')
            cylinder(m,(0,.102,0),.079,.006,'#98C9CE')
            gem(m,(0,.11,0),.035,.13,'#EBCDA9')
        else:
            rounded_box(m,(0,.115,0),.14,.15,.14,.018,'#D2B2CF',bevel=.012)
            rounded_box(m,(0,.196,0),.04,.012,.15,.005,'#FFE1A1',bevel=.003)
            rounded_box(m,(0,.12,.074),.026,.15,.005,.002,'#FFE1A1',bevel=.001)
    elif kind=='jail':
        tower(m,(0,.04,0),.088,.23,'#D7E2E6','#94B5C4')
    elif kind=='goJail':
        gem(m,(0,.08,0),.074,.24,'#C8B3D9' if sky else '#E6A692')
    else:
        cylinder(m,(0,.04,0),.07,.04,'#ECCC96')
        cylinder(m,(.022,.083,0),.07,.04,'#F3DCAF')
    return compact_building(m.faces)


def compact_building(faces):
    # Circular foundations leave daylight between even the closest two stops.
    return [{'p':[[round(x*.80,6),round(y*.86,6),round(z*.80,6)] for x,y,z in f['p']],
             'm':f['m']} for f in faces]


def taiwan():
    base,decor,paths=Mesh(),Mesh(),Mesh();outline=smooth(COAST)
    island(base,[(x*1.025,z*1.025) for x,z in outline],.065,'#EDDCBC','#C6AD89',bottom=-.14)
    island(base,outline,.12,'#B6D09E','#95B58E',bottom=.048)
    inner=resample([(x*.76,z*.76) for x,z in outline],28)
    route=[(x,.137,z) for x,z in inner]
    ribbon(paths,[(x,.127,z) for x,z in inner+[inner[0]]],.17,'#EFE6CF')
    ribbon(paths,[(x,.129,z) for x,z in inner+[inner[0]]],.065,'#DCCCA9')
    for i,(x,z) in enumerate([( .26,-1.00),(.24,-.51),(.12,.02),(-.05,.49),(-.15,.98)]):
        mountain(decor,(x,.12,z),.20 if i!=2 else .25,.30 if i!=2 else .40,['#95B59B','#A4C4A5','#7CA494'][i%3])
    # A small lake, fields and trees instead of a wall of oversized peaks.
    island(paths,ellipse(-.33,.28,.22,.28),.132,'#A7D2D0','#A7D2D0',bottom=.129)
    for ix in range(2):
        for iz in range(3):
            rounded_box(decor,(-.47+ix*.13,.14,-.57+iz*.13),.10,.024,.10,.012,
                ['#D1D99C','#D8CB8D'][(ix+iz)%2],bevel=.005)
    for x,z in [(-.33,-1.05),(.62,-.92),(.62,-.42),(.53,.36),(.36,.86),(-.41,.85),(-.71,.09),(-.12,1.38)]:tree(decor,(x,.12,z),.075)
    for x,z in [(-.25,-1.42),(-.65,-.92)]:
        cylinder(decor,(x,.13,z),.015,.27,'#FCF5E9')
        for a in [0,math.tau/3,math.tau*2/3]:
            c=(x,.39,z+.013);tip=(x+math.cos(a)*.115,.39+math.sin(a)*.115,z+.013)
            m=(x+math.cos(a+.35)*.045,.39+math.sin(a+.35)*.045,z+.013)
            decor.face([c,tip,m],'#FCF5E9')
    return base,decor,route,outline,paths


def sky():
    base,decor,paths,clouds=Mesh(),Mesh(),Mesh(),Mesh();route=[];groups=[]
    for group,(cx,y,cz,rx,rz,count) in enumerate(SKY):
        outline=ellipse(cx,cz,rx,rz,30,.045)
        island(base,outline,y,['#DCE4CE','#CDE1D5','#E0D6E9'][group%3], '#EFE3D6',bottom=y-.12,tip=(cx+.07,y-1.05,cz+.05))
        # Clockwise groups, with a short local arc facing away from the castle.
        outward=math.atan2(cz,cx)
        for i in range(count):
            a=outward-.92+i*1.84/(count-1)
            route.append((cx+rx*.61*math.cos(a),y+.017,cz+rz*.58*math.sin(a)));groups.append(group)
        gem(decor,(cx,y,cz),.10,.30,['#B3C9DF','#BCAADB','#A8CFC5'][group%3])
        tree(decor,(cx-rx*.25,y,cz+rz*.17),.09,True)
    # Segmented, gently arched bridges join distinct floating islands.
    for i,a in enumerate(route):
        b=route[(i+1)%len(route)];cross=groups[i]!=groups[(i+1)%len(route)]
        count=18 if cross else 5
        points=[]
        for j in range(count+1):
            t=j/count
            points.append((a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t+(.16*math.sin(math.pi*t) if cross else .0),a[2]+(b[2]-a[2])*t))
        ribbon(paths,points,.115,'#EDDCCA' if cross else '#F5ECDC')
        if cross:
            for j in range(2,count-1,2):
                p=points[j];q=points[j+1];dx,dz=q[0]-p[0],q[2]-p[2];length=math.hypot(dx,dz)
                ox,oz=-dz/length*.071,dx/length*.071
                ribbon(decor,[(p[0]-ox,p[1]+.004,p[2]-oz),(p[0]+ox,p[1]+.004,p[2]+oz)],.017,'#CBB499')
    # Central castle is a separate floating landmark, with cloud pillows below.
    island(base,ellipse(0,0,.46,.56,32,.055),.48,'#E8E1D5','#EEE0D3',bottom=.32,tip=(.02,-.42,0))
    rounded_box(decor,(0,.66,0),.43,.36,.29,.045,'#FCF1E7',bevel=.024)
    tower(decor,(-.22,.48,-.02),.10,.43,'#FCF1E7','#CFB7D9')
    tower(decor,(.22,.48,-.02),.10,.43,'#FCF1E7','#CFB7D9')
    tower(decor,(0,.79,-.08),.12,.34,'#FCF1E7','#D7AAC8')
    rounded_box(decor,(0,.62,.155),.10,.21,.009,.047,'#B8C7D7',bevel=.003)
    for x in [-.13,.13]:window(decor,(x,.76,.154),.052,.078)
    gem(decor,(0,1.40,-.08),.06,.12,'#EED8A2')
    # A small rainbow behind the castle, positioned in 3D space.
    for band,color in enumerate(['#E7B5C4','#F1DBAC','#C1D9CE','#B9C9E3']):
        r=.41+band*.045
        for i in range(18):
            a=i*math.pi/18;b=(i+1)*math.pi/18
            def p(t,rr):return (rr*math.cos(t),.51+rr*math.sin(t),-.32)
            decor.face([p(a,r),p(b,r),p(b,r+.042),p(a,r+.042)],color)
    for cx,cz,scale in [(-1.45,-1.64,.28),(.91,-1.87,.27),(1.39,.21,.25),(.55,1.55,.29),(-1.23,1.55,.28),(-.60,.00,.20)]:
        for dx,dy,dz,r in [(-.6,0,0,.68),(0,.08,0,.90),(.65,0,.05,.60)]:
            sphere(clouds,(cx+dx*scale,-.12+dy*scale,cz+dz*scale),(r*scale,.18*scale/.28,r*scale*.65),'#F9F6F4',rings=5,slices=10)
    return base,decor,route,groups,paths,clouds


def main():
    tbase,tdecor,troute,coast,tpaths=taiwan();sbase,sdecor,sroute,groups,spaths,clouds=sky()
    for name,base,decor,route in [('taiwan',tbase,tdecor,troute),('sky',sbase,sdecor,sroute)]:
        data={'format':1,'name':name,'route':route,'base':base.faces,'decor':decor.faces,
              'paths':(tpaths if name=='taiwan' else spaths).faces,'clouds':[] if name=='taiwan' else clouds.faces,
              'buildings':{**{f'land{i}':house(i,name=='sky') for i in range(4)},
                 **{k:feature(k,name=='sky') for k in ['start','chance','jail','goJail','tax']}}}
        (ROOT/f'assets/models/{name}_board.json').write_text(json.dumps(data,separators=(',',':'))+'\n')
        print(name,len(route),'stops',len(base.faces)+len(decor.faces),'environment faces')
    lines=["// Generated by tools/build_board_models.py. Display geometry only.",'']
    def arr(name,values):
        lines.append(f'const {name} = <List<double>>[')
        for x,y,z in values:lines.append(f'  [{x:.6f}, {y:.6f}, {z:.6f}],')
        lines.append('];\n')
    arr('taiwanCoast3D',[(x,.12,z) for x,z in coast]);arr('taiwanStops3D',troute);arr('skyStops3D',sroute)
    lines.append('const skyStopGroups3D = <int>['+','.join(map(str,groups))+'];')
    lines.append('const skyPlatforms3D = <List<double>>[')
    for x,y,z,rx,rz,_ in SKY:lines.append(f'  [{x},{y},{z},{rx},{rz}],')
    lines.append('];\n')
    (ROOT/'lib/widgets/board_world_data.dart').write_text('\n'.join(lines))
if __name__=='__main__':main()
