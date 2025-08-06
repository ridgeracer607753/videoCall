import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:video_call/screen/cam_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[100],
      body: Column(
        children: [
          /// 1) 로고
          Expanded(
            child: _Logo(),
          ),

          /// 2) 이미지
          Expanded(
            child: _Image(),
          ),

          /// 3) 버튼
          Expanded(
            child: _Footer(),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(16.0),
          boxShadow: [
            BoxShadow(
              color: Colors.blue[300]!,
              blurRadius: 12.0,
              spreadRadius: 2.0,
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.videocam,
                color: Colors.white,
              ),
              SizedBox(width: 12.0),
              Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Image extends StatelessWidget {
  const _Image({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        'asset/img/home_img.png',
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({super.key});

  Future<void> _requestPermissionsAndNavigate(BuildContext context) async {
    try {
      print('=== 홈 화면에서 권한 요청 ===');

      // 권한 상태 확인
      PermissionStatus cameraStatus = await Permission.camera.status;
      PermissionStatus microphoneStatus = await Permission.microphone.status;

      print('현재 카메라 권한: $cameraStatus');
      print('현재 마이크 권한: $microphoneStatus');

      // 권한이 없으면 요청
      if (cameraStatus != PermissionStatus.granted) {
        print('카메라 권한 요청 중...');
        cameraStatus = await Permission.camera.request();
        print('카메라 권한 요청 결과: $cameraStatus');
      }

      if (microphoneStatus != PermissionStatus.granted) {
        print('마이크 권한 요청 중...');
        microphoneStatus = await Permission.microphone.request();
        print('마이크 권한 요청 결과: $microphoneStatus');
      }

      // 권한이 허용된 경우에만 화면 이동
      if (cameraStatus == PermissionStatus.granted &&
          microphoneStatus == PermissionStatus.granted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CamScreen(),
          ),
        );
      } else {
        // 권한이 거부된 경우 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('비디오 콜을 위해 카메라와 마이크 권한이 필요합니다.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('권한 요청 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => _requestPermissionsAndNavigate(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        child: Text('입장하기'),
      ),
    );
  }
}
