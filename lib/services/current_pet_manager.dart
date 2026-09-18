import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CurrentPetManager {
  CurrentPetManager._();

  static final CurrentPetManager instance = CurrentPetManager._();

  final ValueNotifier<String> currentPetKey = ValueNotifier<String>('dog');

  static const Map<String, String> petImageMap = {
    'dog': 'assets/pets/dog.png',
    'cat': 'assets/pets/cat.png',
    'parrot': 'assets/pets/parrot.png',
    'sloth': 'assets/pets/sloth.png',
    'fox': 'assets/pets/fox.png',

    'cute_dog': 'assets/pets/shiba.png',
    'pomeranian': 'assets/pets/pomeranian.png',
    'norm_dog': 'assets/pets/calm_dog.png',
    'wagging_dog': 'assets/pets/clingy_dog.png',

    'lovely_cat': 'assets/pets/love_cat.png',
    'blue_cat': 'assets/pets/work_cat.png',
    'rocket_cat': 'assets/pets/rocket_cat.png',
    'loader_cat': 'assets/pets/waiting_cat.png',

    'bear': 'assets/pets/bear.png',
    'bee': 'assets/pets/bee.png',
    'giraffe': 'assets/pets/giraffe.png',
  };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final savedKey = prefs.getString('current_pet_key') ?? 'dog';

    currentPetKey.value = savedKey;
  }

  Future<void> setPet(String key) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('current_pet_key', key);

    currentPetKey.value = key;
  }

  String getImagePath(String key) {
    return petImageMap[key] ?? 'assets/pets/dog.png';
  }
}