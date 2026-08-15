import 'package:flutter/material.dart';
import '../models/category.dart';

// 預設分類
List<Category> studentCategories = [
  Category(id: "1", name: "早餐", icon: "🍞", group: "student"),
  Category(id: "2", name: "午餐", icon: "🍱", group: "student"),
  Category(id: "3", name: "晚餐", icon: "🍜", group: "student"),
  Category(id: "4", name: "飲料", icon: "🧋", group: "student"),
];

List<Category> workerCategories = [
  Category(id: "8", name: "通勤咖啡", icon: "☕", group: "worker"),
  Category(id: "9", name: "交通", icon: "🚇", group: "worker"),
  Category(id: "10", name: "家庭開銷", icon: "🏠", group: "worker"),
];

List<Category> customCategories = [];

class CategoryPage extends StatefulWidget {
  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  String selectedGroup = "student";

  @override
  Widget build(BuildContext context) {
    List<Category> categories = [];

    if (selectedGroup == "student") categories = studentCategories;
    if (selectedGroup == "worker") categories = workerCategories;
    if (selectedGroup == "custom") categories = customCategories;

    return Scaffold(
      appBar: AppBar(
        title: Text("記帳類別分類"),
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ChoiceChip(
                label: Text("大學生"),
                selected: selectedGroup == "student",
                onSelected: (_) => setState(() => selectedGroup = "student"),
              ),
              ChoiceChip(
                label: Text("出社會"),
                selected: selectedGroup == "worker",
                onSelected: (_) => setState(() => selectedGroup = "worker"),
              ),
              ChoiceChip(
                label: Text("自訂"),
                selected: selectedGroup == "custom",
                onSelected: (_) => setState(() => selectedGroup = "custom"),
              ),
            ],
          ),
          Divider(),

          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.all(16),
              itemCount: categories.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final c = categories[index];
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.grey.shade200,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(c.icon, style: TextStyle(fontSize: 28)),
                      SizedBox(height: 8),
                      Text(c.name),
                    ],
                  ),
                );
              },
            ),
          ),

          if (selectedGroup == "custom")
            Padding(
              padding: EdgeInsets.all(12),
              child: ElevatedButton(
                onPressed: () => _showAddCustomDialog(),
                child: Text("新增自訂類別"),
              ),
            ),
        ],
      ),
    );
  }

  void _showAddCustomDialog() {
    String name = "";
    String icon = "⭐";

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("新增自訂類別"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(labelText: "名稱"),
              onChanged: (val) => name = val,
            ),
            TextField(
              decoration: InputDecoration(labelText: "Emoji圖案"),
              onChanged: (val) => icon = val,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("取消"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                customCategories.add(
                  Category(
                    id: DateTime.now()
                        .microsecondsSinceEpoch
                        .toString(),
                    name: name,
                    icon: icon,
                    group: "custom",
                  ),
                );
              });
              Navigator.pop(context);
            },
            child: Text("新增"),
          ),
        ],
      ),
    );
  }
}
