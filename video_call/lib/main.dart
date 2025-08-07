import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_call/screen/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 세로화면만 허용
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    MaterialApp(
      theme: ThemeData(
        fontFamily: 'NotoSans',
      ),
      home: HomeScreen(),
    ),
  );
}
