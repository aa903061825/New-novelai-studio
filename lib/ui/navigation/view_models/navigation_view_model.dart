import 'package:flutter/material.dart';

class NavigationViewModel extends ChangeNotifier {
  int currentPageIndex = 0;

  void changeIndex(int value) {
    if (currentPageIndex == value) {
      return;
    }
    currentPageIndex = value;
  }
}
