import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:video_call/screen/cam_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:video_call/const/keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 세로화면 고정
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[100],
      body: Center(
        child: _Footer(),
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

  // 주인장 관련 변수들
  bool _isHost = false;
  bool _isLongPressing = false;
  Timer? _longPressTimer;
  double _pressProgress = 0.0;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _loadHostStatus();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  // 주인장 상태 로드
  Future<void> _loadHostStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isHost = prefs.getBool('is_host') ?? false;
    });
  }

  // 주인장 권한 설정
  Future<void> _setHostStatus(bool isHost) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_host', isHost);
    if (isHost) {
      // 현재 UID를 저장
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('host_uid', now % 999999 + 1);
    }
    setState(() {
      _isHost = isHost;
    });
  }

  // 5초 장누름 처리
  void _onLongPressStart() {
    if (_isHost) return; // 이미 주인장이면 무시

    setState(() {
      _isLongPressing = true;
      _pressProgress = 0.0;
    });

    // 프로그레스 애니메이션
    _progressTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
      setState(() {
        _pressProgress += 0.01; // 5초 = 100 * 50ms
      });

      if (_pressProgress >= 1.0) {
        timer.cancel();
      }
    });

    // 5초 타이머
    _longPressTimer = Timer(Duration(seconds: 5), () {
      _becomeHost();
    });
  }

  void _onLongPressEnd() {
    _longPressTimer?.cancel();
    _progressTimer?.cancel();
    setState(() {
      _isLongPressing = false;
      _pressProgress = 0.0;
    });
  }

  // 주인장 되기
  void _becomeHost() {
    _setHostStatus(true);
    _onLongPressEnd();

    // 성공 메시지 표시
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.workspace_premium, color: Colors.yellow),
            SizedBox(width: 8),
            Text('주인장 권한을 획득했습니다!'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _checkRoomStatus() async {
    setState(() {
      _isCheckingRoom = true;
      _roomExists = null;
      _participantCount = 0;
    });

    try {
      print('=== 방 상태 확인 시작 ===');

      // 임시 엔진을 생성하여 채널 상태 확인
      RtcEngine tempEngine = createAgoraRtcEngine();

      await tempEngine.initialize(
        RtcEngineContext(appId: appId),
      );

      // 이벤트 핸들러를 등록하여 채널 정보 수집
      List<int> activeUsers = [];
      bool channelJoined = false;
      bool userDetectionComplete = false;

      tempEngine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            channelJoined = true;
            print('채널 확인용 연결 성공: ${connection.channelId}');

            // 채널에 참가한 후 잠시 기다린 다음 사용자 감지 완료로 표시
            Timer(Duration(seconds: 5), () {
              userDetectionComplete = true;
            });
          },
          onUserJoined: (connection, uid, elapsed) {
            print('사용자 감지됨: $uid');
            if (uid != 888888 && !activeUsers.contains(uid)) {
              // 새로운 임시 UID로 변경하고 제외
              activeUsers.add(uid);
              print('실제 사용자 추가: $uid (총 ${activeUsers.length}명)');
              // 사용자가 감지되면 즉시 감지 완료로 표시
              userDetectionComplete = true;
            } else {
              print('임시 UID 또는 중복 사용자 무시: $uid');
            }
          },
          onUserOffline: (connection, uid, reason) {
            activeUsers.remove(uid);
            print('사용자 나감: $uid (총 ${activeUsers.length}명, 이유: $reason)');
          },
          onError: (err, msg) {
            print('채널 확인 오류: $err - $msg');
            if (err == ErrorCodeType.errTokenExpired) {
              print('⚠️ 토큰이 만료되었습니다! keys.dart에서 토큰을 갱신하세요.');
            }
          },
          onRemoteAudioStateChanged: (connection, uid, state, reason, elapsed) {
            print('원격 오디오 상태 변경: UID=$uid, State=$state');
          },
          onRemoteVideoStateChanged: (connection, uid, state, reason, elapsed) {
            print('원격 비디오 상태 변경: UID=$uid, State=$state');
          },
        ),
      );

      // 비디오와 오디오 활성화 (더 나은 감지를 위해)
      await tempEngine.enableVideo();
      await tempEngine.enableAudio();

      // 채널에 잠시 연결하여 정보 수집 (브로드캐스터 모드로 변경)
      await tempEngine.joinChannel(
        token: token ?? '',
        channelId: channelName,
        uid: 888888, // 새로운 임시 UID
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster, // 브로드캐스터 모드로 변경
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishCameraTrack: false, // 카메라는 발행하지 않음
          publishMicrophoneTrack: false, // 마이크도 발행하지 않음
          autoSubscribeAudio: true, // 오디오 구독
          autoSubscribeVideo: true, // 비디오 구독
        ),
      );

      // 채널 연결 직후 기존 사용자 목록을 요청
      try {
        if (token != null && token!.isNotEmpty) {
          await tempEngine.renewToken(token!); // 채널 새로고침을 통해 기존 사용자 감지 개선
          print('✅ 토큰 갱신 성공');
        } else {
          print('⚠️ 토큰이 없어서 갱신 건너뜀');
        }
      } catch (e) {
        print('⚠️ 토큰 갱신 실패 (무시해도 됨): $e');
      }

      print('채널 참가 완료, 사용자 감지 대기 중...');

      // 사용자 감지를 위해 더 긴 시간 대기
      int waitTime = 0;
      while (waitTime < 6 && !userDetectionComplete) {
        await Future.delayed(Duration(seconds: 1));
        waitTime++;
        print('대기 중... ${waitTime}초 (현재 감지된 사용자: ${activeUsers.length}명)');

        // 2초 후부터 추가 방법으로 사용자 감지 시도
        if (waitTime == 2) {
          try {
            // 채널 정보 갱신 시도
            await tempEngine.muteLocalAudioStream(true);
            await tempEngine.muteLocalAudioStream(false);
          } catch (e) {
            print('추가 감지 시도 실패: $e');
          }
        }

        // 4초 후 한번 더 시도
        if (waitTime == 4) {
          try {
            await tempEngine.muteLocalVideoStream(true);
            await tempEngine.muteLocalVideoStream(false);
          } catch (e) {
            print('추가 감지 시도 2 실패: $e');
          }
        }
      }

      print('사용자 감지 완료, 채널에서 나가는 중...');

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

      print('=== 방 상태 확인 완료 ===');
      print('채널 연결: $channelJoined');
      print('실제 참가자: $realUserCount명');
      print('감지된 UID 목록: $activeUsers');
    } catch (e) {
      print('방 상태 확인 오류: $e');
      setState(() {
        _isCheckingRoom = false;
        _roomExists = false;
        _participantCount = 0;
      });

      // 토큰 만료 오류인 경우 사용자에게 알림
      if (e.toString().contains('errTokenExpired')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error, color: Colors.white),
                    SizedBox(width: 8),
                    Text('토큰이 만료되었습니다'),
                  ],
                ),
                SizedBox(height: 4),
                Text('개발자가 토큰을 갱신해야 합니다.', style: TextStyle(fontSize: 12)),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
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
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 40),

          // 주인장 상태 표시
          if (_isHost) ...[
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.yellow[100],
                border: Border.all(color: Colors.yellow[700]!, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium,
                      color: Colors.yellow[700], size: 20),
                  SizedBox(width: 8),
                  Text(
                    '주인장 권한 보유',
                    style: TextStyle(
                      color: Colors.yellow[800],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),
            TextButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('주인장 권한 해제'),
                    content: Text('주인장 권한을 해제하시겠습니까?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('취소'),
                      ),
                      TextButton(
                        onPressed: () {
                          _setHostStatus(false);
                          Navigator.pop(context);
                        },
                        child: Text('해제'),
                      ),
                    ],
                  ),
                );
              },
              child: Text('권한 해제', style: TextStyle(color: Colors.red)),
            ),
            SizedBox(height: 20),
          ],

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
                                ? '방이 비어있습니다 (주인장 감지 안됨)'
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
                  if (_participantCount == 0 && _roomExists == false)
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💡 주인장이 방에 있다면 다시 한번 확인해보세요',
                            style: TextStyle(
                              color: Colors.blue[600],
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '📱 주인장이 앱을 완전히 시작했는지 확인해주세요',
                            style: TextStyle(
                              color: Colors.orange[600],
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 20),
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
            label: Text(_isCheckingRoom ? '확인 중... (최대 6초)' : '방 상태 확인'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _isCheckingRoom ? Colors.orange[600] : Colors.grey[600],
              foregroundColor: Colors.white,
            ),
          ),

          SizedBox(height: 20),

          // 주인장 되기 버튼 (주인장이 아닐 때만 표시)
          if (!_isHost) ...[
            GestureDetector(
              onTapDown: (_) => _onLongPressStart(),
              onTapUp: (_) => _onLongPressEnd(),
              onTapCancel: _onLongPressEnd,
              child: Container(
                width: 200,
                height: 50,
                decoration: BoxDecoration(
                  color:
                      _isLongPressing ? Colors.yellow[300] : Colors.yellow[100],
                  border: Border.all(color: Colors.yellow[700]!, width: 2),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Stack(
                  children: [
                    // 프로그레스 바
                    if (_isLongPressing)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 200 * _pressProgress,
                          decoration: BoxDecoration(
                            color: Colors.yellow[600],
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                      ),
                    // 텍스트
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.workspace_premium,
                            color: Colors.yellow[800],
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            _isLongPressing
                                ? '${(5 - (_pressProgress * 5)).ceil()}초...'
                                : '주인장 되기 (5초 누르기)',
                            style: TextStyle(
                              color: Colors.yellow[800],
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 30),
          ],

          // 입장하기 버튼 (할아버지 할머니용 - 화면 절반 크기)
          Container(
            width: MediaQuery.of(context).size.width * 0.9, // 화면 폭의 90%
            height: MediaQuery.of(context).size.height * 0.3, // 화면 높이의 30%
            margin: EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: () => _requestPermissionsAndNavigate(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600], // 강한 빨간색
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 15,
                shadowColor: Colors.red[300],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.videocam,
                    size: 80, // 매우 큰 아이콘
                    color: Colors.white,
                  ),
                  SizedBox(height: 24),
                  Text(
                    '입장하기',
                    style: TextStyle(
                      fontSize: 42, // 매우 큰 글씨
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 3,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '화상통화 시작',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 40),
        ],
      ),
    );
  }
}
