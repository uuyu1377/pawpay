import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_interface/theme/app_palette.dart';
import 'package:user_interface/widgets/paw_gacha_3d.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<PawGachaModel> loadModel() async => PawGachaModel.fromJson(
    jsonDecode(await rootBundle.loadString('assets/models/paw_gacha.json')) as Map<String,dynamic>);

  test('bundled model stays inside a small viewport through a full rotation', () async {
    final model=await loadModel();
    const size=Size(248,285);
    for (var step=0;step<24;step++) {
      final camera=GachaCamera3(size,yaw:step*math.pi/12);
      for (final face in model.meshes['body']!) {
        for (final vertex in face.points) {
          final p=camera.screen(vertex);
          expect(p.dx,inInclusiveRange(0,size.width));
          expect(p.dy,inInclusiveRange(0,size.height));
        }
      }
    }
  });

  test('stirring keeps each capsule, including its seam, inside the glass', () async {
    final model=await loadModel();
    final vertices=model.meshes['capsule']!.expand((f)=>f.points).toList();
    for (var frame=0;frame<32;frame++) {
      final phase=frame*math.pi/16;
      for (var i=0;i<model.capsules.length;i++) {
        final pose=model.capsules[i];
        final center=gachaCapsuleCenter(pose,i,phase,1);
        for (final vertex in vertices) {
          final p=vertex.turnZ(i*.71+phase)*pose.radius+center;
          final q=math.pow(p.x/.748,2)+math.pow((p.y-2.005)/.674,2)+math.pow(p.z/.648,2);
          expect(q,lessThan(1));
        }
      }
    }
  });

  testWidgets('rotation and reset do not start a draw animation', (tester) async {
    final model=await loadModel();
    final roll=AnimationController(vsync:tester,duration:const Duration(milliseconds:1400));
    final drop=AnimationController(vsync:tester,duration:const Duration(milliseconds:800));
    await tester.pumpWidget(MaterialApp(theme:buildAppTheme(const PaletteSpec()),
      home:Scaffold(body:MediaQuery(data:const MediaQueryData(textScaler:TextScaler.linear(1.8)),
        child:SizedBox(width:288,child:PawGachaMachine3D(model:model,roll:roll,drop:drop))))));
    await tester.pump();
    final canvas=find.byWidgetPredicate((w)=>w is CustomPaint && w.painter is PawGachaPainter);
    double yaw()=>(tester.widget<CustomPaint>(canvas).painter! as PawGachaPainter).camera.yaw;
    final initial=yaw();
    await tester.drag(canvas,const Offset(80,0));await tester.pump();
    expect(yaw(),isNot(initial));
    expect(roll.isAnimating,isFalse);expect(drop.value,0);
    await tester.tap(find.byTooltip('扭蛋機回正'));await tester.pump();
    expect(yaw(),closeTo(initial,.0001));
    roll.repeat();await tester.pump(const Duration(milliseconds:500));
    roll.stop();drop.forward();await tester.pump(const Duration(milliseconds:400));
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    roll.dispose();drop.dispose();
  });
}
