import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_uikit/agora_uikit.dart';
import 'package:video_call/const/keys.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class CamScreen extends StatefulWidget {
  const CamScreen({super.key});

  @override
  State<CamScreen> createState() => _CamScreenState();
}

class _CamScreenState extends State<CamScreen> {
  RtcEngine? engine;
  int uid = 0;
  int? remoteUid;

  // 권한 상태 관리
  bool _permissionsGranted = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _generateUniqueUid();
  }

  // 기기 고유 uid 생성
  Future<void> _generateUniqueUid() async {
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String deviceId = '';

      if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? '';
      } else if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      }

      // 문자열을 숫자로 변환 (해시코드 사용)
      uid = deviceId.hashCode.abs() % 999999 + 1;
      print('생성된 고유 UID: $uid (기기 ID: $deviceId)');

      // uid 생성 후 권한 요청
      _requestPermissions();
    } catch (e) {
      print('UID 생성 오류: $e');
      // 오류 시 랜덤 UID 사용
      uid = DateTime.now().millisecondsSinceEpoch % 999999 + 1;
      _requestPermissions();
    }
  }

  Future<void> _requestPermissions() async {
    try {
      print('=== 권한 요청 시작 ===');

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

      // 권한이 허용된 경우
      if (cameraStatus == PermissionStatus.granted &&
          microphoneStatus == PermissionStatus.granted) {
        print('=== 권한 요청 완료 ===');
        setState(() {
          _permissionsGranted = true;
          _isLoading = false;
        });
        _initializeAgora();
      } else {
        // 권한이 거부된 경우
        setState(() {
          _isLoading = false;
          _errorMessage = '카메라 또는 마이크 권한이 필요합니다.';
        });
      }
    } catch (e) {
      print('권한 요청 오류: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = '권한 요청 중 오류가 발생했습니다: $e';
      });
    }
  }

  Future<void> _initializeAgora() async {
    try {
      print('=== Agora 초기화 시작 ===');
      
      if (engine == null) {
        print('Agora RTC Engine 생성 중...');
        engine = createAgoraRtcEngine();

        print('Agora 초기화 중... AppId: $appId');
        await engine!.initialize(
          RtcEngineContext(
            appId: appId,
          ),
        );

        print('이벤트 핸들러 등록 중...');
        engine!.registerEventHandler(
          RtcEngineEventHandler(
            onJoinChannelSuccess: (
              RtcConnection connection,
              int elapsed,
            ) {
              print('채널 참가 성공: ${connection.channelId}, UID: $uid');
            },
            onLeaveChannel: (
              RtcConnection connection,
              RtcStats stats,
            ) {
              print('채널 떠남');
            },
            onUserJoined: (
              RtcConnection connection,
              int remoteUid,
              int elapsed,
            ) {
              print('원격 사용자 참가: $remoteUid');
              setState(() {
                this.remoteUid = remoteUid;
              });
            },
            onUserOffline: (
              RtcConnection connection,
              int remoteUid,
              UserOfflineReasonType reason,
            ) {
              print('원격 사용자 나감: $remoteUid');
              setState(() {
                this.remoteUid = null;
              });
            },
            onLocalVideoStateChanged: (
              VideoSourceType source,
              LocalVideoStreamState state,
              LocalVideoStreamReason reason,
            ) {
              print('로컬 비디오 상태 변경: $state, 이유: $reason, 소스: $source');
              if (state == LocalVideoStreamState.localVideoStreamStateCapturing) {
                print('로컬 비디오 캡처 시작됨');
              } else if (state == LocalVideoStreamState.localVideoStreamStateEncoding) {
                print('로컬 비디오 인코딩 시작됨');
              }
            },
          ),
        );

        print('비디오 활성화 중...');
        await engine!.enableVideo();
        
        print('오디오 활성화 중...');
        await engine!.enableAudio();
        
        print('비디오 미리보기 시작...');
        await engine!.startPreview();

        ChannelMediaOptions options = ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        );

        print('채널 참가 중... 채널: $channelName, UID: $uid');
        await engine!.joinChannel(
          token: token,
          channelId: channelName,
          uid: uid,
          options: options,
        );
        
        print('=== Agora 초기화 완료 ===');
      }
    } catch (e) {
      print('Agora 초기화 오류: $e');
      setState(() {
        _errorMessage = '비디오 콜 초기화 중 오류가 발생했습니다: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('LIVE'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('권한 요청 중...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _requestPermissions();
              },
              child: Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (!_permissionsGranted) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, size: 64, color: Colors.orange),
            SizedBox(height: 16),
            Text('카메라와 마이크 권한이 필요합니다.'),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                });
                _requestPermissions();
              },
              child: Text('권한 요청'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // 메인 비디오 뷰 (원격 사용자 또는 로컬)
        Container(
          width: double.infinity,
          height: double.infinity,
          child: renderMainView(),
        ),
        // 로컬 비디오 뷰 (작은 화면) - 항상 표시
        Positioned(
          top: 50,
          right: 16,
          child: Container(
            width: 120,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: AgoraVideoView(
                controller: VideoViewController(
                  rtcEngine: engine!,
                  canvas: VideoCanvas(
                    uid: 0, // 로컬 비디오 (항상 표시)
                    renderMode: RenderModeType.renderModeAdaptive,
                  ),
                ),
              ),
            ),
          ),
        ),
        // 나가기 버튼
        Positioned(
          bottom: 16.0,
          left: 16.0,
          right: 16.0,
          child: ElevatedButton(
            onPressed: () {
              engine!.leaveChannel();
              engine!.release();
              Navigator.of(context).pop();
            },
            child: Text('나가기'),
          ),
        ),
      ],
    );
  }

  Widget renderMainView() {
    if (remoteUid == null) {
      // 원격 사용자가 없을 때는 대기 화면 표시
      return Container(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.videocam_off,
                size: 80,
                color: Colors.white54,
              ),
              SizedBox(height: 16),
              Text(
                '상대방을 기다리는 중...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '채널: $channelName',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 원격 사용자가 있을 때는 원격 비디오를 메인 화면에 표시
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: engine!,
        canvas: VideoCanvas(
          uid: remoteUid,
          renderMode: RenderModeType.renderModeAdaptive,
        ),
        connection: RtcConnection(
          channelId: channelName,
        ),
      ),
    );
  }

  @override
  void dispose() {
    engine?.leaveChannel();
    engine?.release();
    super.dispose();
  }
}
