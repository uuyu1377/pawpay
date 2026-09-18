import 'dart:convert';
import 'package:flutter/services.dart';
import 'board_3d_geometry.dart';

class BoardMeshFace3D {
  const BoardMeshFace3D(this.points, this.material);
  final List<BoardPoint3> points;
  final String material;
}

/// Local, original meshes. Game state remains owned by PlaygroundPage.
class BoardSceneModel {
  const BoardSceneModel(
    this.base,
    this.decor,
    this.buildings, {
    this.paths = const [],
    this.clouds = const [],
  });
  final List<BoardMeshFace3D> base, decor, paths, clouds;
  final Map<String, List<BoardMeshFace3D>> buildings;
  static final Map<bool, Future<BoardSceneModel>> _cache = {};

  static Future<BoardSceneModel> load(bool magic) =>
      _cache.putIfAbsent(magic, () => _read(magic));

  static Future<BoardSceneModel> _read(bool magic) async {
    try {
      final path = 'assets/models/${magic ? 'sky' : 'taiwan'}_board.json';
      return BoardSceneModel.fromJson(
        jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>,
      );
    } catch (_) {
      _cache.remove(magic);
      rethrow;
    }
  }

  factory BoardSceneModel.fromJson(Map<String, dynamic> data) {
    if (data['format'] != 1)
      throw const FormatException('Unknown board format');
    List<BoardMeshFace3D> faces(dynamic items) => (items as List)
        .map(
          (f) => BoardMeshFace3D(
            (f['p'] as List)
                .map(
                  (p) => BoardPoint3(
                    (p[0] as num).toDouble(),
                    (p[1] as num).toDouble(),
                    (p[2] as num).toDouble(),
                  ),
                )
                .toList(),
            f['m'] as String,
          ),
        )
        .toList();
    final buildings = data['buildings'] as Map<String, dynamic>;
    return BoardSceneModel(
      faces(data['base']),
      faces(data['decor']),
      buildings.map((key, value) => MapEntry(key, faces(value))),
      paths: faces(data['paths'] ?? []),
      clouds: faces(data['clouds'] ?? []),
    );
  }
}
