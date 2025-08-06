import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:video_call/screen/cam_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:video_call/const/keys.dart';

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
  const _Logo();

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
  const _Image();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        'asset/img/home_img.png',
      ),
    );
  }
}

class _Footer extends StatefulWidget {
  const _Footer();

  @override
  State<_Footer> createState() => _FooterState();
}

class _FooterState extends State<_Footer> {
  bool _isCheckingRoom = false;
  bool? _roomExists;
  int _participantCount = 0;

  Future<void> _checkRoomStatus() async {
    setState(() {
      _isCheckingRoom = true;
      _roomExists = null;
    });

    try {
      // 임시 엔진을 생성하여 채널 상태 확인
      RtcEngine tempEngine = createAgoraRtcEngine();

      await tempEngine.initialize(
        RtcEngineContext(appId: appId),
      );

      // 이벤트 핸들러를 등록하여 채널 정보 수집
      List<int> activeUsers = [];
      bool channelJoined = false;

      tempEngine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            channelJoined = true;
            print('채널 확인용 연결 성공: ${connection.channelId}');
          },
          onUserJoined: (connection, uid, elapsed) {
            if (uid != 999999 && !activeUsers.contains(uid)) {
              // 임시 UID 제외
              activeUsers.add(uid);
              print('실제 사용자 발견: $uid (총 ${activeUsers.length}명)');
            }
          },
          onUserOffline: (connection, uid, reason) {
            activeUsers.remove(uid);
            print('사용자 나감: $uid (총 ${activeUsers.length}명)');
          },
          onError: (err, msg) {
            print('채널 확인 오류: $err - $msg');
          },
        ),
      );

      // 채널에 잠시 연결하여 정보 수집 (관찰자 모드)
      await tempEngine.joinChannel(
        token: token,
        channelId: channelName,
        uid: 999999, // 임시 UID
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleAudience, // 관찰자 모드
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      // 조금 더 긴 시간 대기하여 사용자 정보 수집
      await Future.delayed(Duration(seconds: 3));

      // 채널에서 나가기
      await tempEngine.leaveChannel();
      await tempEngine.release();

      // 실제 활성 사용자 수 확인
      int realUserCount = activeUsers.length;

      setState(() {
        _isCheckingRoom = false;
        _roomExists = realUserCount > 0; // 실제 참가자가 있을 때만 활성화된 것으로 간주
        _participantCount = realUserCount;
      });

      print('방 상태 확인 완료: 채널 연결=$channelJoined, 실제 참가자=$realUserCount명');
    } catch (e) {
      print('방 상태 확인 오류: $e');
      setState(() {
        _isCheckingRoom = false;
        _roomExists = false;
        _participantCount = 0;
      });
    }
  }

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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 방 상태 정보 표시
          if (_roomExists != null) ...[
            Container(
              padding: EdgeInsets.all(16),
              margin: EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: _roomExists! ? Colors.green[50] : Colors.orange[50],
                border: Border.all(
                  color: _roomExists! ? Colors.green : Colors.orange,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _roomExists! ? Icons.check_circle : Icons.info,
                        color: _roomExists! ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        _roomExists!
                            ? '방에 참가자가 있습니다'
                            : (_participantCount == 0
                                ? '방이 비어있습니다'
                                : '새로운 방이 생성됩니다'),
                        style: TextStyle(
                          color: _roomExists!
                              ? Colors.green[800]
                              : Colors.orange[800],
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '채널: $channelName',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '현재 참가자: $_participantCount명',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
          ],

          // 방 상태 확인 버튼
          ElevatedButton.icon(
            onPressed: _isCheckingRoom ? null : _checkRoomStatus,
            icon: _isCheckingRoom
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(Icons.search),
            label: Text(_isCheckingRoom ? '확인 중...' : '방 상태 확인'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[600],
              foregroundColor: Colors.white,
            ),
          ),

          SizedBox(height: 12),

          // 입장하기 버튼
          ElevatedButton.icon(
            onPressed: () => _requestPermissionsAndNavigate(context),
            icon: Icon(Icons.videocam),
            label: Text('입장하기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
