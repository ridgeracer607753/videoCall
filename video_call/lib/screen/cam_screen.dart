import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
// agora_uikit 제거됨
import 'package:video_call/const/keys.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

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

  // 방 상태 관리
  bool _isChannelJoined = false;
  int _totalUserCount = 0;
  List<int> _connectedUsers = [];

  // 주인장 권한 관리
  bool _isHost = false;
  int? _hostUid;

  // 카메라 제어
  bool _isFrontCamera = true;

  // 데이터 스트림 ID
  int? _dataStreamId;

  // 연결 상태 모니터링
  String _connectionState = "연결 시도 중";
  String _networkQuality = "측정 중";
  DateTime? _lastConnectionUpdate;

  // 토큰 만료 관리
  String _tokenStatus = "확인 중";
  DateTime? _tokenExpiry;

  // 강퇴 관리
  bool _isKicked = false;

  // 대안 통신을 위한 타이머
  Timer? _alternativeCommTimer;

  // 화면 배치 관리
  int? _mainScreenUid; // 큰 화면에 표시할 사용자 UID

  @override
  void initState() {
    super.initState();

    // 세로화면 고정
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    _generateUniqueUid();
    _loadHostStatus();
    _checkTokenExpiry();
    _initializeAgora();

    // 대안 통신 타이머 시작 (1초마다 SharedPreferences 확인)
    // SharedPreferences 제거됨 - 순수 Agora Data Stream만 사용
  }

  // 토큰 만료 시간 체크
  void _checkTokenExpiry() {
    if (token != null && token!.isNotEmpty) {
      try {
        // Agora 토큰에서 만료 시간 추출 (base64 디코딩)
        final parts = token!.split('.');
        if (parts.length >= 2) {
          // 토큰이 유효한 형태라고 가정하고 24시간 후 만료로 설정
          _tokenExpiry = DateTime.now().add(Duration(hours: 24));
          setState(() {
            _tokenStatus = "유효 (24시간)";
          });
        } else {
          setState(() {
            _tokenStatus = "형식 오류";
          });
        }
      } catch (e) {
        setState(() {
          _tokenStatus = "분석 실패";
        });
      }
    } else {
      setState(() {
        _tokenStatus = "토큰 없음";
      });
    }
  }

  // 주인장 상태 로드
  Future<void> _loadHostStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isHost = prefs.getBool('is_host') ?? false;
      _hostUid = prefs.getInt('host_uid');
    });
  }

  // 연결된 사용자들 중에서 주인장 감지
  void _detectHostFromUsers() {
    if (_connectedUsers.isEmpty) {
      _hostUid = null;
      return;
    }

    // 실제 주인장 설정이 있는 경우 그것을 우선
    final prefs = SharedPreferences.getInstance();
    prefs.then((sharedPrefs) {
      int? savedHostUid = sharedPrefs.getInt('host_uid');

      if (savedHostUid != null && _connectedUsers.contains(savedHostUid)) {
        // 저장된 주인장 UID가 현재 연결된 사용자 중에 있으면 사용
        setState(() {
          _hostUid = savedHostUid;
        });
        print('📋 저장된 주인장 UID 사용: $savedHostUid');
      } else {
        // 저장된 주인장이 없거나 연결되지 않은 경우, 가장 작은 UID를 주인장으로 설정
        int smallestUid = _connectedUsers.reduce((a, b) => a < b ? a : b);
        setState(() {
          _hostUid = smallestUid;
        });
        print('🎯 자동 감지된 주인장 UID: $smallestUid');
      }
    });
  }

  // 큰 화면에 표시할 사용자 결정
  void _updateMainScreenUid() {
    if (_connectedUsers.isEmpty) {
      _mainScreenUid = null;
      return;
    }

    // 참가자가 2명인 경우: 서로 보이게
    if (_totalUserCount == 2) {
      // 상대방을 큰 화면에 표시
      List<int> otherUsers = _connectedUsers.where((u) => u != uid).toList();
      if (otherUsers.isNotEmpty) {
        _mainScreenUid = otherUsers.first;
      }
    }
    // 3명 이상인 경우: 기본적으로 첫 번째 사용자를 큰 화면에 표시
    else if (_totalUserCount >= 3) {
      if (_mainScreenUid == null || !_connectedUsers.contains(_mainScreenUid)) {
        List<int> otherUsers = _connectedUsers.where((u) => u != uid).toList();
        if (otherUsers.isNotEmpty) {
          _mainScreenUid = otherUsers.first;
        }
      }
    }

    print('🖥️ 큰 화면 UID 업데이트: $_mainScreenUid (총 $_totalUserCount명)');
  }

  // 미니 화면 클릭 시 큰 화면과 전환
  void _switchToMainScreen(int targetUid) {
    if (_connectedUsers.contains(targetUid)) {
      setState(() {
        _mainScreenUid = targetUid;
      });
      print('🔄 화면 전환: $targetUid를 큰 화면으로 이동');
    }
  }

  // 미니 화면에 표시할 사용자 목록 가져오기
  List<int> _getMiniScreenUsers() {
    if (_totalUserCount <= 2) {
      return []; // 2명 이하일 때는 미니 화면 없음
    }

    List<int> otherUsers = _connectedUsers.where((u) => u != uid).toList();
    return otherUsers.where((u) => u != _mainScreenUid).toList();
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

      // 더 고유한 UID 생성: 기기ID + 현재시간 + 랜덤값
      int deviceHash = deviceId.hashCode.abs();
      int timeHash = DateTime.now().millisecondsSinceEpoch;
      int randomHash =
          (DateTime.now().microsecond * 1000 + deviceHash) % 999999;

      uid = (deviceHash + timeHash + randomHash).abs() % 999999 +
          100000; // 6자리 UID
      print('생성된 고유 UID: $uid (기기 ID: $deviceId)');

      // uid 생성 후 권한 요청
      _requestPermissions();
    } catch (e) {
      print('UID 생성 오류: $e');
      // 오류 시 랜덤 UID 사용 (시간 기반으로 더 고유하게)
      uid = (DateTime.now().millisecondsSinceEpoch + DateTime.now().microsecond)
                  .abs() %
              999999 +
          100000;
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
              print('=== 채널 참가 성공 ===');
              print('채널: ${connection.channelId}');
              print('로컬 UID: $uid');
              print('연결 시간: ${elapsed}ms');
              print('네트워크 타입: ${connection.toString()}');
              setState(() {
                _isChannelJoined = true;
                _connectedUsers.add(uid);
                _totalUserCount = _connectedUsers.length;

                // 자신도 주인장 감지 대상에 포함
                _detectHostFromUsers();

                // 화면 배치 업데이트
                _updateMainScreenUid();
              });

              // 채널 참가 후 데이터 스트림 생성
              _createDataStreamSafely();
            },
            onLeaveChannel: (
              RtcConnection connection,
              RtcStats stats,
            ) {
              print('채널 떠남');
              setState(() {
                _isChannelJoined = false;
                _connectedUsers.clear();
                _totalUserCount = 0;
                remoteUid = null;
              });
            },
            onUserJoined: (
              RtcConnection connection,
              int remoteUid,
              int elapsed,
            ) {
              print('=== 원격 사용자 참가 ===');
              print('원격 UID: $remoteUid');
              print('채널: ${connection.channelId}');
              print('로컬 UID: $uid');
              print('연결된 사용자 목록: $_connectedUsers');

              setState(() {
                this.remoteUid = remoteUid;
                if (!_connectedUsers.contains(remoteUid)) {
                  _connectedUsers.add(remoteUid);
                  _totalUserCount = _connectedUsers.length;
                }

                // 주인장 감지 로직 - 가장 작은 UID를 주인장으로 간주
                _detectHostFromUsers();

                // 화면 배치 업데이트
                _updateMainScreenUid();
              });

              print('업데이트된 사용자 목록: $_connectedUsers (총 $_totalUserCount명)');
              print('현재 감지된 주인장 UID: $_hostUid');
            },
            onUserOffline: (
              RtcConnection connection,
              int remoteUid,
              UserOfflineReasonType reason,
            ) {
              print('원격 사용자 나감: $remoteUid (이유: $reason)');
              setState(() {
                if (this.remoteUid == remoteUid) {
                  this.remoteUid = null;
                }
                _connectedUsers.remove(remoteUid);
                _totalUserCount = _connectedUsers.length;

                // 사용자가 나간 후 주인장 재감지
                _detectHostFromUsers();

                // 화면 배치 업데이트
                _updateMainScreenUid();
              });
            },
            onLocalVideoStateChanged: (
              VideoSourceType source,
              LocalVideoStreamState state,
              LocalVideoStreamReason reason,
            ) {
              print('로컬 비디오 상태 변경: $state, 이유: $reason, 소스: $source');
              if (state ==
                  LocalVideoStreamState.localVideoStreamStateCapturing) {
                print('로컬 비디오 캡처 시작됨');
              } else if (state ==
                  LocalVideoStreamState.localVideoStreamStateEncoding) {
                print('로컬 비디오 인코딩 시작됨');
              }
            },
            onError: (err, msg) {
              print('=== Agora 오류 발생 ===');
              print('오류 코드: $err');
              print('오류 메시지: $msg');
              print('현재 채널: $channelName');
              print('현재 UID: $uid');

              if (err == ErrorCodeType.errTokenExpired) {
                print('⚠️ 토큰이 만료되었습니다!');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.white),
                        SizedBox(width: 8),
                        Expanded(child: Text('토큰이 만료되었습니다. 개발자에게 문의하세요.')),
                      ],
                    ),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 5),
                  ),
                );
              }
            },
            onConnectionStateChanged: (connection, state, reason) {
              print('=== 연결 상태 변경 ===');
              print('연결 상태: $state');
              print('변경 이유: $reason');
              print('채널: ${connection.channelId}');

              setState(() {
                _connectionState = _getConnectionStateText(state);
                _lastConnectionUpdate = DateTime.now();
              });
            },
            onNetworkQuality: (connection, uid, txQuality, rxQuality) {
              if (uid == this.uid) {
                print('=== 네트워크 품질 (${DateTime.now()}) ===');
                print('송신 품질: $txQuality');
                print('수신 품질: $rxQuality');

                setState(() {
                  _networkQuality =
                      _getNetworkQualityText(txQuality, rxQuality);
                });
              }
            },
            onStreamMessage: (connection, uid, streamId, data, length, sentTs) {
              try {
                String message = String.fromCharCodes(data);
                print('📨📨📨 스트림 메시지 수신 상세 정보:');
                print('- 메시지: "$message"');
                print('- 발신자 UID: $uid');
                print('- 스트림 ID: $streamId');
                print('- 데이터 길이: $length');
                print('- 전송 시간: $sentTs');
                _handleStreamMessage(message);
              } catch (e) {
                print('❌ 스트림 메시지 처리 오류: $e');
                print('데이터: $data');
              }
            },
            onStreamMessageError:
                (connection, uid, streamId, error, missed, cached) {
              print('❌❌❌ 스트림 메시지 오류 발생:');
              print('- UID: $uid');
              print('- 스트림 ID: $streamId');
              print('- 오류 코드: $error');
              print('- 누락된 메시지: $missed');
              print('- 캐시된 메시지: $cached');
            },
          ),
        );

        print('비디오 활성화 중...');
        await engine!.enableVideo();

        print('오디오 활성화 중...');
        await engine!.enableAudio();

        // 비디오 인코더 설정 (해상도 및 품질 개선)
        print('비디오 인코더 설정 중...');
        await engine!.setVideoEncoderConfiguration(
          VideoEncoderConfiguration(
            dimensions: VideoDimensions(width: 640, height: 480), // 4:3 비율
            frameRate: 15,
            bitrate: 400,
            orientationMode: OrientationMode.orientationModeAdaptive,
          ),
        );

        print('비디오 미리보기 시작...');
        await engine!.startPreview();

        // 데이터 스트림은 채널 참가 후에 생성하도록 이동

        ChannelMediaOptions options = ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          // 연결 안정성 개선 옵션들
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
          enableAudioRecordingOrPlayout: true,
        );

        print('=== 채널 참가 시도 ===');
        print('📍 채널명: "$channelName"');
        print('🔑 로컬 UID: $uid');
        print('🎫 토큰 상태: $_tokenStatus');
        print('🎫 토큰 길이: ${token?.length ?? 0}자');
        if (_tokenExpiry != null) {
          print('⏰ 토큰 만료: ${_tokenExpiry.toString()}');
        }
        print('📱 앱 ID: $appId');
        print('⚙️ 클라이언트 역할: ${options.clientRoleType}');
        print('📺 채널 프로필: ${options.channelProfile}');
        print('옵션: ${options.toString()}');

        // 채널 참가 전에 짧은 지연 추가 (안정성 향상)
        await Future.delayed(Duration(milliseconds: 500));

        await engine!.joinChannel(
          token: token ?? '',
          channelId: channelName, // 원래 채널명 사용 (testchannel)
          uid: uid,
          options: options,
        );

        print('채널 참가 요청 완료, 응답 대기 중...');

        // 채널 참가 후 추가 안정화 시간
        await Future.delayed(Duration(milliseconds: 1000));

        print('=== Agora 초기화 완료 ===');
      }
    } catch (e) {
      print('Agora 초기화 오류: $e');
      setState(() {
        _errorMessage = '비디오 콜 초기화 중 오류가 발생했습니다: $e';
      });
    }
  }

  // 카메라 전환 - 손님이 주인장 카메라를 강제 전환!
  Future<void> _switchCamera() async {
    if (!_canControlHost()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('카메라 제어 권한이 없습니다. 주인장이 있을 때만 제어할 수 있습니다.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    print('🔥 손님이 주인장 카메라 강제 전환 요청!');

    try {
      await _sendCameraSwitchRequest();
      print('✅ Agora 데이터 스트림 전송 성공!');

      // 성공 피드백
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.flash_on, color: Colors.white),
              SizedBox(width: 8),
              Text('📡 주인장 카메라 전환 요청을 보냈습니다!'),
            ],
          ),
          backgroundColor: Colors.blue[600],
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('❌ Agora 데이터 스트림 실패: $e');

      // 실패 피드백
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 8),
              Text('❌ 카메라 전환 요청 실패: 연결을 확인하세요'),
            ],
          ),
          backgroundColor: Colors.red[600],
          duration: Duration(seconds: 3),
        ),
      );
    }

    print('🚀 카메라 전환 요청 완료!');
  }

  // 주인장을 방에서 내보내는 기능
  Future<void> _kickHostFromRoom() async {
    if (_isHost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('주인장은 자신을 내보낼 수 없습니다.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 주인장이 없는 경우 - 재감지 시도
    if (_hostUid == null) {
      print('⚠️ 주인장 UID가 null - 재감지 시도');
      _detectHostFromUsers();

      // 재감지 후에도 없으면 에러 표시
      if (_hostUid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('현재 방에 주인장이 감지되지 않습니다.'),
                SizedBox(height: 4),
                Text('연결된 사용자: $_connectedUsers',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    // 주인장이 실제로 연결되어 있는지 확인
    if (!_connectedUsers.contains(_hostUid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('주인장(UID: $_hostUid)이 현재 연결되어 있지 않습니다.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('주인장 내보내기'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('정말로 주인장을 방에서 내보내시겠습니까?'),
            SizedBox(height: 8),
            Text(
              '주인장 UID: $_hostUid',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              // 주인장에게 강퇴 신호 전송
              await _sendKickMessage(_hostUid!);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.send, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('주인장에게 방 나가기 요청을 보냈습니다.'),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );

              print('🚨 주인장($_hostUid) 강퇴 신호 전송 완료');
            },
            child: Text('내보내기', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 권한 확인 - 주인장이 아닌 사용자만 제어 가능
  bool _canControlHost() {
    // 일반 사용자인 경우: 주인장이 있을 때만 원격 제어 가능
    return !_isHost && remoteUid != null && _totalUserCount > 1;
  }

  // 카메라 전환 요청 전송 - 동적 Stream ID 사용
  Future<void> _sendCameraSwitchRequest() async {
    try {
      print('🔍 데이터 스트림 전송 시작...');
      print('엔진 상태: ${engine != null ? "정상" : "null"}');
      print('채널 참가 상태: $_isChannelJoined');
      print('현재 Stream ID: $_dataStreamId');
      print('현재 UID: $uid');

      if (engine == null) {
        throw Exception('Agora 엔진이 초기화되지 않았습니다');
      }

      if (!_isChannelJoined) {
        throw Exception('아직 채널에 참가하지 않았습니다');
      }

      // Stream ID가 없으면 새로 생성
      if (_dataStreamId == null) {
        print('📡 Stream ID가 없어서 새로 생성합니다...');
        await _createDataStreamSafely();
      }

      if (_dataStreamId == null) {
        throw Exception('데이터 스트림 생성에 실패했습니다');
      }

      // 메시지 준비
      String switchMessage =
          "SWITCH_CAMERA:$uid:${DateTime.now().millisecondsSinceEpoch}";
      Uint8List messageData = Uint8List.fromList(switchMessage.codeUnits);

      print('🚀 메시지 전송: $switchMessage (Stream ID: $_dataStreamId)');

      // 메시지 전송
      await engine!.sendStreamMessage(
        streamId: _dataStreamId!,
        data: messageData,
        length: messageData.length,
      );

      print('✅ 카메라 전환 요청 전송 완료!');
    } catch (e) {
      print('❌ 카메라 전환 요청 전송 실패: $e');
      rethrow;
    }
  }

  // SharedPreferences 관련 함수들 제거됨 - 순수 Agora Data Stream만 사용

  // 안전한 데이터 스트림 생성
  Future<void> _createDataStreamSafely() async {
    try {
      print('📡 채널 참가 후 데이터 스트림 생성 시도...');
      _dataStreamId = await engine!.createDataStream(
        DataStreamConfig(
          syncWithAudio: false,
          ordered: true,
        ),
      );
      print('✅ 데이터 스트림 생성 성공! Stream ID: $_dataStreamId');
    } catch (e) {
      print('❌ 데이터 스트림 생성 실패: $e');
      _dataStreamId = null;
    }
  }

  // SharedPreferences 체크 함수 제거됨 - 순수 Agora Data Stream만 사용

  // 강퇴 메시지 전송
  Future<void> _sendKickMessage(int targetUid) async {
    try {
      if (engine == null || !_isChannelJoined) {
        throw Exception('엔진이 준비되지 않았거나 채널에 참가하지 않았습니다');
      }

      // Stream ID 확인 및 생성
      if (_dataStreamId == null) {
        await _createDataStreamSafely();
      }

      if (_dataStreamId == null) {
        throw Exception('데이터 스트림 생성에 실패했습니다');
      }

      String kickMessage =
          "KICK_HOST:$uid:${DateTime.now().millisecondsSinceEpoch}";
      Uint8List messageData = Uint8List.fromList(kickMessage.codeUnits);

      await engine!.sendStreamMessage(
        streamId: _dataStreamId!,
        data: messageData,
        length: messageData.length,
      );

      print('💬 강퇴 메시지 전송: $kickMessage (Stream ID: $_dataStreamId)');
    } catch (e) {
      print('❌ 강퇴 메시지 전송 실패: $e');
    }
  }

  // 메시지 수신 처리 (강퇴 및 카메라 전환)
  void _handleStreamMessage(String message) {
    print('📨 스트림 메시지 수신됨: "$message"');
    print('현재 사용자 주인장 여부: $_isHost');

    if (message.startsWith("KICK_HOST:")) {
      print('🚨 강퇴 메시지로 인식');
      _handleKickMessage(message);
    } else if (message.startsWith("SWITCH_CAMERA:")) {
      print('📷 카메라 전환 메시지로 인식');
      _handleCameraSwitchRequest(message);
    } else {
      print('❓ 알 수 없는 메시지 형식: $message');
    }
  }

  // 강퇴 메시지 수신 처리
  void _handleKickMessage(String message) {
    List<String> parts = message.split(":");
    if (parts.length >= 2) {
      String senderUid = parts[1];
      print('🚨 강퇴 메시지 수신됨. 보낸 사람: $senderUid');

      // 주인장인 경우에만 처리하고, 중복 처리 방지
      if (_isHost && !_isKicked) {
        setState(() {
          _isKicked = true;
        });

        _showKickedDialog(senderUid);
      }
    }
  }

  // 카메라 전환 요청 수신 처리
  void _handleCameraSwitchRequest(String message) {
    List<String> parts = message.split(":");
    if (parts.length >= 2) {
      String senderUid = parts[1];
      print('📷 카메라 전환 요청 수신됨. 요청자: $senderUid (현재 주인장: $_isHost)');

      // 주인장인 경우에만 처리 - 즉시 강제 실행!
      if (_isHost) {
        print('🔥 주인장이므로 즉시 카메라 강제 전환 실행!');
        _processCameraSwitchRequest(senderUid);
      } else {
        print('⚠️ 주인장이 아니므로 카메라 전환 요청 무시');
      }
    }
  }

  // 카메라 전환 요청 실제 처리 - 승인 없이 강제 실행!
  Future<void> _processCameraSwitchRequest(String requesterUid) async {
    print('🚀 강제 카메라 전환 시작! (요청자: $requesterUid)');

    try {
      // 강제로 즉시 카메라 전환 실행!
      print('🔄 engine.switchCamera() 실행 중...');
      await engine!.switchCamera();

      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });

      print('✅ 카메라 강제 전환 성공! 현재 상태: ${_isFrontCamera ? "전면" : "후면"}');

      // 주인장에게 강제 전환 알림
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                    '🔥 UID $requesterUid가 강제로 카메라를 ${_isFrontCamera ? "전면" : "후면"}으로 전환했습니다!'),
              ),
            ],
          ),
          backgroundColor: Colors.red[600],
          duration: Duration(seconds: 4),
        ),
      );

      print(
          '📷 강제 카메라 전환 완료: ${_isFrontCamera ? "전면" : "후면"} (강제 요청자: $requesterUid)');
    } catch (e) {
      print('❌ 강제 카메라 전환 실패: $e');

      // 오류 시에도 알림
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('카메라 전환 중 오류가 발생했습니다: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // 강퇴 다이얼로그 표시 및 홈화면으로 이동
  void _showKickedDialog(String kickerUid) {
    // 5초 후 자동으로 홈화면으로 이동
    Timer(Duration(seconds: 5), () {
      if (Navigator.canPop(context)) {
        Navigator.pop(context); // 다이얼로그 닫기
      }
      _leaveRoomAndGoHome(); // 방 나가기 및 홈화면 이동
    });

    showDialog(
      context: context,
      barrierDismissible: false, // 뒤로가기로 닫을 수 없음
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.exit_to_app, color: Colors.red),
            SizedBox(width: 8),
            Text('방에서 내보내짐'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber, size: 48, color: Colors.orange),
            SizedBox(height: 16),
            Text(
              '다른 사용자에 의해 방에서 내보내졌습니다.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text('요청자 UID: $kickerUid',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            SizedBox(height: 16),
            Text(
              '5초 후 자동으로 홈화면으로 이동됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // 다이얼로그 닫기
              _leaveRoomAndGoHome(); // 방 나가기 및 홈화면 이동
            },
            child: Text('지금 나가기', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 방 나가기 및 홈화면 이동
  Future<void> _leaveRoomAndGoHome() async {
    try {
      print('🚪 강퇴로 인한 방 나가기 시작');

      if (engine != null) {
        await engine!.leaveChannel();
        await engine!.release();
      }

      // 홈화면으로 이동
      Navigator.of(context).popUntil((route) => route.isFirst);

      print('🏠 홈화면으로 이동 완료');
    } catch (e) {
      print('❌ 방 나가기 오류: $e');
      // 오류가 있어도 홈화면으로 이동
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // 연결 상태를 한국어로 변환
  String _getConnectionStateText(ConnectionStateType state) {
    switch (state) {
      case ConnectionStateType.connectionStateDisconnected:
        return "연결 끊김";
      case ConnectionStateType.connectionStateConnecting:
        return "연결 중";
      case ConnectionStateType.connectionStateConnected:
        return "연결됨";
      case ConnectionStateType.connectionStateReconnecting:
        return "재연결 중";
      case ConnectionStateType.connectionStateFailed:
        return "연결 실패";
    }
  }

  // 네트워크 품질을 한국어로 변환
  String _getNetworkQualityText(QualityType txQuality, QualityType rxQuality) {
    String tx = _qualityToText(txQuality);
    String rx = _qualityToText(rxQuality);
    return "송신: $tx, 수신: $rx";
  }

  String _qualityToText(QualityType quality) {
    switch (quality) {
      case QualityType.qualityExcellent:
        return "최고";
      case QualityType.qualityGood:
        return "좋음";
      case QualityType.qualityPoor:
        return "보통";
      case QualityType.qualityBad:
        return "나쁨";
      case QualityType.qualityVbad:
        return "매우나쁨";
      case QualityType.qualityDown:
        return "끊김";
      default:
        return "측정중";
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time).inSeconds;
    if (diff < 60) {
      return "${diff}초 전";
    } else {
      return "${(diff / 60).floor()}분 전";
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
        // 방 상태 정보 표시 (위치 조정)
        Positioned(
          top: 230,
          left: 16,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isChannelJoined ? Icons.wifi : Icons.wifi_off,
                      color: _isChannelJoined ? Colors.green : Colors.red,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      _isChannelJoined ? '연결됨' : '연결 안됨',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  '방: $channelName',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
                Text(
                  '참가자: $_totalUserCount명',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
                if (_isHost)
                  Row(
                    children: [
                      Icon(
                        Icons.workspace_premium,
                        color: Colors.yellow,
                        size: 12,
                      ),
                      SizedBox(width: 2),
                      Text(
                        '주인장 (나)',
                        style: TextStyle(
                          color: Colors.yellow,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '손님',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                      if (_hostUid != null &&
                          _connectedUsers.contains(_hostUid))
                        Text(
                          '큰 화면: 주인장($_hostUid)',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else if (_connectedUsers.isNotEmpty)
                        Text(
                          '큰 화면: ${_connectedUsers.first}',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else
                        Text(
                          '큰 화면: 대기 중',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                if (_connectedUsers.isNotEmpty)
                  Text(
                    'UID: ${_connectedUsers.join(", ")}',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                    ),
                  ),
                SizedBox(height: 2),
                Text(
                  '연결: $_connectionState',
                  style: TextStyle(
                    color: _connectionState == "연결됨"
                        ? Colors.green
                        : Colors.orange,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$_networkQuality',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 8,
                  ),
                ),
                Text(
                  '토큰: $_tokenStatus',
                  style: TextStyle(
                    color: _tokenStatus.contains("유효")
                        ? Colors.green
                        : Colors.orange,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_lastConnectionUpdate != null)
                  Text(
                    '업데이트: ${_formatTime(_lastConnectionUpdate!)}',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 8,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // 내 화면 (왼쪽 상단, 빨간 테두리) - 4:3 비율로 수정
        Positioned(
          top: 50,
          left: 16,
          child: Container(
            width: 120,
            height: 90, // 4:3 비율 (120:90 = 4:3)
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red, width: 3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: AgoraVideoView(
                controller: VideoViewController(
                  rtcEngine: engine!,
                  canvas: VideoCanvas(
                    uid: 0, // 로컬 비디오 (내 화면)
                    renderMode: RenderModeType.renderModeHidden, // 왜곡 방지
                  ),
                ),
              ),
            ),
          ),
        ),
        // 미니 화면들 (오른쪽 상단, 3명 이상일 때만 표시)
        ..._buildMiniScreens(),
        // 주인장 제어 버튼들 (권한이 있는 경우에만 표시)
        if (_canControlHost()) ...[
          Positioned(
            bottom: 100,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 카메라 전환 버튼
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue[600],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      onPressed: _switchCamera,
                      icon: Icon(
                        _isFrontCamera ? Icons.camera_front : Icons.camera_rear,
                        color: Colors.white,
                        size: 28,
                      ),
                      tooltip: '주인장 카메라 전환 요청',
                    ),
                  ),
                  SizedBox(height: 12),
                  // 주인장 내보내기 버튼 (주인장이 아닐 때만 표시)
                  if (!_isHost)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.red[600],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        onPressed: _kickHostFromRoom,
                        icon: Icon(
                          Icons.exit_to_app,
                          color: Colors.white,
                          size: 28,
                        ),
                        tooltip: '주인장 내보내기',
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 제어 버튼 설명 라벨
          Positioned(
            bottom: 240,
            left: 16,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.control_camera,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '주인장 제어',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• 주인장 카메라 제어\n• 주인장 내보내기',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '나가기',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget renderMainView() {
    // 연결된 사용자가 없거나 큰 화면에 표시할 사용자가 없는 경우
    if (_connectedUsers.isEmpty || _mainScreenUid == null) {
      return Container(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isChannelJoined ? Icons.videocam_off : Icons.wifi_off,
                size: 80,
                color: _isChannelJoined ? Colors.white54 : Colors.red,
              ),
              SizedBox(height: 16),
              Text(
                _isChannelJoined ? '상대방을 기다리는 중...' : '방에 연결 중...',
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
              if (_isChannelJoined) ...[
                SizedBox(height: 8),
                Text(
                  '방이 생성되었습니다 ✓',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '현재 참가자: $_totalUserCount명',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ] else ...[
                SizedBox(height: 8),
                Text(
                  '방 생성 중...',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 8),
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // 큰 화면에 지정된 사용자 표시
    print('🖥️ 큰 화면에 사용자 $_mainScreenUid 표시 (총 $_totalUserCount명)');
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: engine!,
        canvas: VideoCanvas(
          uid: _mainScreenUid,
          renderMode: RenderModeType.renderModeHidden, // 왜곡 방지
        ),
        connection: RtcConnection(
          channelId: channelName,
        ),
      ),
    );
  }

  // 미니 화면들 빌드
  List<Widget> _buildMiniScreens() {
    List<int> miniUsers = _getMiniScreenUsers();
    List<Widget> miniScreens = [];

    for (int i = 0; i < miniUsers.length; i++) {
      int userId = miniUsers[i];
      miniScreens.add(
        Positioned(
          top: 50 + (i * 100.0), // 각 미니 화면을 세로로 배치 (간격 조정)
          right: 16,
          child: GestureDetector(
            onTap: () => _switchToMainScreen(userId),
            child: Container(
              width: 120,
              height: 90, // 4:3 비율로 수정
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    AgoraVideoView(
                      controller: VideoViewController.remote(
                        rtcEngine: engine!,
                        canvas: VideoCanvas(
                          uid: userId,
                          renderMode: RenderModeType.renderModeHidden, // 왜곡 방지
                        ),
                        connection: RtcConnection(
                          channelId: channelName,
                        ),
                      ),
                    ),
                    // 사용자 ID 표시
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$userId',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return miniScreens;
  }

  @override
  void dispose() {
    _alternativeCommTimer?.cancel();
    engine?.leaveChannel();
    engine?.release();

    // 화면 방향 제한 해제 (필요한 경우)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    super.dispose();
  }
}
