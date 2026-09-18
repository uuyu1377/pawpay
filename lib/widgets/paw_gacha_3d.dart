import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_palette.dart';

/// Three-dimensional coordinates. The camera faces +Z, with +Y pointing up.
class GachaPoint3 {
  const GachaPoint3(this.x, this.y, this.z);
  final double x, y, z;
  factory GachaPoint3.fromJson(List<dynamic> a) => GachaPoint3(
    (a[0] as num).toDouble(), (a[1] as num).toDouble(), (a[2] as num).toDouble());
  GachaPoint3 operator +(GachaPoint3 b) => GachaPoint3(x+b.x, y+b.y, z+b.z);
  GachaPoint3 operator -(GachaPoint3 b) => GachaPoint3(x-b.x, y-b.y, z-b.z);
  GachaPoint3 operator *(double s) => GachaPoint3(x*s, y*s, z*s);
  double dot(GachaPoint3 b) => x*b.x+y*b.y+z*b.z;
  GachaPoint3 cross(GachaPoint3 b) => GachaPoint3(y*b.z-z*b.y, z*b.x-x*b.z, x*b.y-y*b.x);
  double get length => math.sqrt(dot(this));
  GachaPoint3 get normalized => length < 1e-9 ? this : this*(1/length);
  GachaPoint3 turnY(double a) => GachaPoint3(x*math.cos(a)+z*math.sin(a),y,-x*math.sin(a)+z*math.cos(a));
  GachaPoint3 turnZ(double a) => GachaPoint3(x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a),z);
}

class GachaFace3 {
  GachaFace3(this.points, this.material);
  final List<GachaPoint3> points;
  final String material;
}

class GachaCapsulePose {
  GachaCapsulePose(this.center, this.radius);
  final GachaPoint3 center;
  final double radius;
}

GachaPoint3 gachaCapsuleCenter(GachaCapsulePose pose, int index, double phase, double stir) {
  final base=pose.center;
  final spun=GachaPoint3(base.x,0,base.z).turnY(phase);
  final center=GachaPoint3(base.x+(spun.x-base.x)*stir,
    base.y+math.sin(phase*2+index)*.075*stir,base.z+(spun.z-base.z)*stir);
  final delta=center-const GachaPoint3(0,2.005,0);
  final normalized=GachaPoint3(delta.x/.748,delta.y/.674,delta.z/.648).length;
  // Conservative ellipsoid boundary, including the capsule's equatorial seam.
  final limit=.98-pose.radius*1.01/.648;
  return const GachaPoint3(0,2.005,0)+delta*(normalized>limit ? limit/normalized : 1.0);
}

/// Original local mesh, loaded once. It contains no images or remote resources.
class PawGachaModel {
  PawGachaModel(this.meshes, this.capsules, this.crankOrigin);
  final Map<String, List<GachaFace3>> meshes;
  final List<GachaCapsulePose> capsules;
  final GachaPoint3 crankOrigin;
  static Future<PawGachaModel>? _cached;
  static Future<PawGachaModel> load() => _cached ??= _read();
  static Future<PawGachaModel> _read() async {
    try {
      return PawGachaModel.fromJson(jsonDecode(await rootBundle.loadString('assets/models/paw_gacha.json')) as Map<String, dynamic>);
    } catch (_) { _cached = null; rethrow; }
  }
  factory PawGachaModel.fromJson(Map<String,dynamic> json) {
    if (json['format'] != 1) throw const FormatException('Unknown PAWPAY mesh format');
    final raw = json['meshes'] as Map<String,dynamic>;
    return PawGachaModel({for (final name in ['body','glass','highlights','crank','capsule'])
      name: (raw[name] as List).map((f) => GachaFace3(
        (f['p'] as List).map((p) => GachaPoint3.fromJson(p as List)).toList(), f['m'] as String)).toList()},
      (json['capsules'] as List).map((p) => GachaCapsulePose(GachaPoint3.fromJson(p as List), (p[3] as num).toDouble())).toList(),
      GachaPoint3.fromJson(json['crank_origin'] as List));
  }
}

class GachaCamera3 {
  GachaCamera3(this.size, {this.yaw = -.34})
      : unit = math.min(size.width/2.95, size.height/3.85);
  final Size size;
  final double yaw, unit;
  static const elevation = .16;
  GachaPoint3 view(GachaPoint3 p) {
    final v = (p-const GachaPoint3(0,1.51,0)).turnY(yaw);
    return GachaPoint3(v.x,v.y*math.cos(elevation)-v.z*math.sin(elevation),
      v.y*math.sin(elevation)+v.z*math.cos(elevation));
  }
  Offset screen(GachaPoint3 p) {
    final v = view(p);
    final perspective = 7/(7-v.z);
    return Offset(size.width*.5+v.x*unit*perspective, size.height*.48-v.y*unit*perspective);
  }
  bool visible(List<GachaPoint3> points) {
    final normal=(points[1]-points[0]).cross(points[2]-points[0]);
    final center=points.reduce((a,b)=>a+b)*(1/points.length);
    final n=normal.turnY(yaw);
    final viewNormal=GachaPoint3(n.x,n.y*math.cos(elevation)-n.z*math.sin(elevation),
      n.y*math.sin(elevation)+n.z*math.cos(elevation));
    return viewNormal.dot(const GachaPoint3(0,0,7)-view(center)) > 1e-8;
  }
}

/// Presentation only. Parent controllers own the original draw/drop timing.
/// Horizontal drag never calls a purchase, wallet, or draw API.
class PawGachaMachine3D extends StatefulWidget {
  const PawGachaMachine3D({super.key,required this.roll,required this.drop, this.model});
  final AnimationController roll, drop;
  final PawGachaModel? model;
  @override
  State<PawGachaMachine3D> createState()=>_PawGachaMachine3DState();
}

class _PawGachaMachine3DState extends State<PawGachaMachine3D> {
  late Future<PawGachaModel> _model;
  late Listenable _motion;
  double _yaw=-.34;
  @override
  void initState() { super.initState(); _model=_load(); _motion=Listenable.merge([widget.roll,widget.drop]); }
  Future<PawGachaModel> _load()=>widget.model==null ? PawGachaModel.load() : Future.value(widget.model!);
  @override
  void didUpdateWidget(covariant PawGachaMachine3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model!=widget.model) _model=_load();
    if (oldWidget.roll!=widget.roll || oldWidget.drop!=widget.drop) _motion=Listenable.merge([widget.roll,widget.drop]);
  }
  void _reset()=>setState(()=>_yaw=-.34);
  @override
  Widget build(BuildContext context) {
    final palette=AppPalette.of(context);
    return Column(mainAxisSize:MainAxisSize.min,children:[
      AspectRatio(aspectRatio:.87,child:FutureBuilder<PawGachaModel>(future:_model,
        builder:(context,snapshot) {
          if (snapshot.hasError) return Center(child:TextButton.icon(
            onPressed:()=>setState(()=>_model=_load()),icon:const Icon(Icons.refresh),label:const Text('重新載入扭蛋機')));
          if (!snapshot.hasData) return const Center(child:SizedBox(width:24,height:24,child:CircularProgressIndicator(strokeWidth:2)));
          return LayoutBuilder(builder:(context,box)=>Semantics(
            label:'PAWPAY 貓耳立體扭蛋機，左右拖曳旋轉，雙擊回正',
            child:GestureDetector(behavior:HitTestBehavior.opaque,
              onHorizontalDragUpdate:(d)=>setState(()=>_yaw=(_yaw+d.delta.dx*.009)%(math.pi*2)),
              onDoubleTap:_reset,
              child:RepaintBoundary(child:CustomPaint(size:Size(box.maxWidth,box.maxHeight),
                painter:PawGachaPainter(model:snapshot.data!,camera:GachaCamera3(Size(box.maxWidth,box.maxHeight),yaw:_yaw),
                  palette:palette,roll:widget.roll,drop:widget.drop,motion:_motion))),
            )));
        })),
      Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        Flexible(child:Text('左右拖曳轉動',style:TextStyle(color:palette.ink2,fontSize:11))),
        IconButton(tooltip:'扭蛋機回正',onPressed:_reset,
          icon:Icon(Icons.view_in_ar_rounded,size:18,color:palette.accentInk)),
      ]),
    ]);
  }
}

class _PaintedFace {
  _PaintedFace(this.path,this.depth,this.color);
  final Path path;
  final double depth;
  final Color color;
}

class PawGachaPainter extends CustomPainter {
  PawGachaPainter({required this.model,required this.camera,required this.palette,
    required this.roll,required this.drop,required Listenable motion}):super(repaint:motion);
  final PawGachaModel model;
  final GachaCamera3 camera;
  final AppPalette palette;
  final AnimationController roll,drop;
  static const _capsuleColors=[Color(0xFFECA6BD),Color(0xFFAACBC6),Color(0xFFEACD96),Color(0xFFBDAED6),Color(0xFFAFCDE5),Color(0xFFE7B49D)];
  late final Map<String,Color> _materials={
    'rose':Color.lerp(palette.accent,const Color(0xFFF9ECDF),.22)!,
    'soft':palette.accentSoft,'cream':const Color(0xFFFFF8EB),
    'trim':const Color(0xFFEAD4B5),'stage':Color.lerp(palette.accentSoft,const Color(0xFFE6D4CB),.38)!,
    'recess':const Color(0xFF755E65),'ink':palette.accentInk,
    'ear':Color.lerp(palette.accent,Colors.white,.40)!,
    'cheek':palette.accent,'glass':const Color(0xFFC0E3E8).withValues(alpha:.11),
    'shine':Colors.white.withValues(alpha:.64),'shineSoft':Colors.white.withValues(alpha:.32),
    'capsuleTop':const Color(0xFFFFFBF0),'capsuleSeam':const Color(0xFFFFF8EB),
  };
  Path _path(List<Offset> p) {
    final path=Path()..moveTo(p.first.dx,p.first.dy);
    for (final v in p.skip(1)) { path.lineTo(v.dx,v.dy); }
    return path..close();
  }
  List<_PaintedFace> _project(List<GachaFace3> faces, {GachaPoint3 Function(GachaPoint3)? transform,Color? capsule}) {
    final out=<_PaintedFace>[];
    final light=const GachaPoint3(-.45,.85,1.4).normalized;
    for (final face in faces) {
      final points=transform==null ? face.points : face.points.map(transform).toList();
      if (!camera.visible(points)) continue;
      var color=face.material=='capsuleColor' ? capsule! : _materials[face.material]!;
      if (face.material == 'glass') {
        final normal=(points[1]-points[0]).cross(points[2]-points[0]).normalized.turnY(camera.yaw);
        color=color.withValues(alpha:.06+.17*(1-normal.z.abs()));
      }
      if (!{'glass','shine','shineSoft'}.contains(face.material)) {
        final normal=(points[1]-points[0]).cross(points[2]-points[0]).normalized.turnY(camera.yaw);
        final shade=.78+.22*math.max(0.0,normal.dot(light));
        color=Color.lerp(Colors.black,color,shade)!;
      }
      out.add(_PaintedFace(_path(points.map(camera.screen).toList()),
        points.fold<double>(0,(v,p)=>v+camera.view(p).z)/points.length,color));
    }
    return out;
  }
  // Static meshes are projected once per camera/palette change, not per frame.
  late final List<_PaintedFace> _fixed=[
    ..._project(model.meshes['body']!),..._project(model.meshes['glass']!),
    ..._project(model.meshes['highlights']!),
  ];
  @override
  void paint(Canvas canvas,Size size) {
    final phase=roll.value*math.pi*2;
    final dropT=drop.value;
    final stir=roll.isAnimating ? 1.0 : (dropT>0 ? 1-Curves.easeOut.transform(dropT) : 0.0);
    final faces=< _PaintedFace>[..._fixed];
    faces.addAll(_project(model.meshes['crank']!,transform:(p)=>p.turnZ(-phase)+model.crankOrigin));
    for (var i=0;i<model.capsules.length;i++) {
      final pose=model.capsules[i];
      final position=gachaCapsuleCenter(pose,i,phase,stir);
      faces.addAll(_project(model.meshes['capsule']!,capsule:_capsuleColors[i%_capsuleColors.length],
        transform:(p)=>p.turnZ(i*.71+phase*stir)*pose.radius+position));
    }
    if (dropT>0) {
      // Local presentation follows the existing 800 ms drop controller only.
      final t=Curves.easeOut.transform(dropT);
      final center=GachaPoint3(0,.55-.12*t+.07*math.sin(math.pi*t),.73+.23*t);
      faces.addAll(_project(model.meshes['capsule']!,capsule:_capsuleColors.first,
        transform:(p)=>p.turnZ(t*math.pi)*(.11+.025*t)+center));
    }
    final floor=List.generate(48,(i)=>camera.screen(GachaPoint3(math.cos(i*math.pi/24)*1.14,.006,math.sin(i*math.pi/24)*.94)));
    canvas.drawPath(_path(floor),Paint()..color=palette.accentInk.withValues(alpha:.13)
      ..maskFilter=const MaskFilter.blur(BlurStyle.normal,9));
    faces.sort((a,b)=>a.depth.compareTo(b.depth));
    final paint=Paint()..isAntiAlias=true;
    for (final face in faces) { canvas.drawPath(face.path,paint..color=face.color); }
    _nameplate(canvas);
  }
  void _nameplate(Canvas canvas) {
    const anchor=GachaPoint3(0,1.285,.62);
    if (!camera.visible(const [GachaPoint3(-.2,1.25,.62),GachaPoint3(.2,1.25,.62),GachaPoint3(.2,1.32,.62)])) return;
    final center=camera.screen(anchor),x=camera.screen(anchor+const GachaPoint3(.01,0,0))-center,
      y=camera.screen(anchor+const GachaPoint3(0,-.01,0))-center;
    canvas.save();
    canvas.transform(Float64List.fromList([x.dx,x.dy,0,0,y.dx,y.dy,0,0,0,0,1,0,center.dx,center.dy,0,1]));
    final label=TextPainter(text:TextSpan(text:'PAWPAY',style:TextStyle(fontSize:8.6,letterSpacing:1.4,
      color:palette.accentInk,fontWeight:FontWeight.w800)),textDirection:TextDirection.ltr)..layout();
    label.paint(canvas,Offset(-label.width/2,-label.height/2));label.dispose();canvas.restore();
  }
  @override
  bool shouldRepaint(covariant PawGachaPainter oldDelegate)=>oldDelegate.camera!=camera || oldDelegate.palette!=palette || oldDelegate.model!=model || oldDelegate.roll!=roll || oldDelegate.drop!=drop;
}
