import 'package:flutter/material.dart';

class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.height = 56,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;

  static const _items = [
    (Icons.home_filled, 'Home'),
    (Icons.search_rounded, 'Search'),
    (Icons.explore_rounded, 'Explore'),
    (Icons.account_circle_outlined, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF292A2A),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var index = 0; index < _items.length; index++)
            IconButton(
              onPressed: () => onSelected(index),
              tooltip: _items[index].$2,
              icon: Icon(
                _items[index].$1,
                size: 27,
                color: selectedIndex == index
                    ? const Color(0xFFFFC400)
                    : Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}
