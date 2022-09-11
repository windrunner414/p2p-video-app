import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:oktoast/oktoast.dart';
import 'package:sdp_transform/sdp_transform.dart' as sdp_transform;
import 'package:socket_io_client/socket_io_client.dart' as IO;

class VideoChatPage extends StatefulWidget {
  final String signalingServer;
  final String stunServer;
  final String roomName;
  final String roomPassword;

  const VideoChatPage({
    super.key,
    required this.signalingServer,
    required this.stunServer,
    required this.roomName,
    required this.roomPassword,
  });

  @override
  State<VideoChatPage> createState() => _VideoChatPageState();
}

enum SignalingConnectStatus { connecting, connected, disconnected }

class _VideoChatPageState extends State<VideoChatPage> {
  final _localVideoRenderer = RTCVideoRenderer();
  final _remoteVideoRenderer = RTCVideoRenderer();

  bool _offer = false;

  late final RTCPeerConnection _peerConnection;
  late final MediaStream _localStream;

  late final IO.Socket _signalingSocket;
  final _signalingConnectStatus =
      StreamController<SignalingConnectStatus>.broadcast();

  late final _disposers = <VoidCallback>[
    _signalingConnectStatus.close,
  ];

  void _addDisposer(VoidCallback disposer) {
    if (!mounted) {
      disposer.call();
      return;
    }
    _disposers.add(disposer);
  }

  Future<void> _startDialing() async {
    final sdp = await _createOffer();
    _signalingSocket.emit('sendSessionDescription', sdp);
  }

  void _onSignalingConnect() {
    if (!_signalingConnectStatus.isClosed) {
      _signalingConnectStatus.add(SignalingConnectStatus.connected);
    }
    _signalingSocket.emit('join', {
      'roomName': widget.roomName,
      'password': widget.roomPassword,
    });
  }

  void _onReceiveSessionDescription(dynamic data) async {
    _setRemoteDescription(data);
    if (!_offer) {
      final sdp = await _createAnswer();
      _signalingSocket.emit('sendSessionDescription', sdp);
    }
  }

  void _onReceiveIceCandidate(dynamic data) {
    _addCandidate(data);
  }

  Future<void> _connectSignaling() async {
    _signalingSocket = IO.io(
      widget.signalingServer,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _signalingSocket.onConnect((data) => _onSignalingConnect());
    _signalingSocket.onDisconnect((data) {
      if (!_signalingConnectStatus.isClosed) {
        _signalingConnectStatus.add(SignalingConnectStatus.disconnected);
      }
    });

    _signalingSocket.onConnectError((e) => showToast(e.toString()));
    _signalingSocket.onConnectTimeout((e) => showToast('connect timeout'));
    _signalingSocket.onError((e) => showToast(e.toString()));
    _signalingSocket.on('roomCreated', (data) => showToast('room created'));
    _signalingSocket.on('roomJoined', (data) {
      showToast('start dialing');
      _startDialing();
    });
    _signalingSocket.on('sessionDescription', _onReceiveSessionDescription);
    _signalingSocket.on('iceCandidate', _onReceiveIceCandidate);
    _signalingSocket.on(
      'operationFailed',
      (data) => showToast(data.toString()),
    );

    _signalingSocket.connect();
    if (!_signalingConnectStatus.isClosed) {
      _signalingConnectStatus.add(SignalingConnectStatus.connecting);
    }
    _addDisposer(_signalingSocket.dispose);
  }

  Future<void> _initRenderers() async {
    await _localVideoRenderer.initialize();
    _addDisposer(_localVideoRenderer.dispose);
    await _remoteVideoRenderer.initialize();
    _addDisposer(_remoteVideoRenderer.dispose);
  }

  Future<void> _initLocalStream() async {
    final mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
      },
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _addDisposer(() {
      final tracks = _localStream.getTracks();
      for (final track in tracks) {
        track.stop();
      }
      _localStream.dispose();
    });
  }

  Future<void> _createPeerConnection() async {
    const config = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': true,
      },
      'optional': [],
    };

    final iceServers = {
      'iceServers': [
        {'url': 'stun:${widget.stunServer}'},
      ],
    };

    _peerConnection = await createPeerConnection({
      ...iceServers,
      ...{'sdpSemantics': 'unified-plan'},
    }, config);

    _addDisposer(_peerConnection.dispose);
    if (!mounted) {
      return;
    }

    _peerConnection.onTrack = (event) {
      if (event.track.kind == 'video') {
        _remoteVideoRenderer.srcObject = event.streams[0];
      }
    };

    _localStream.getTracks().forEach((track) {
      _peerConnection.addTrack(track, _localStream);
    });

    _peerConnection.onIceCandidate = (e) {
      if (e.candidate != null) {
        //TODO: need some delay
        _signalingSocket.emit(
          'sendIceCandidate',
          jsonEncode({
            'candidate': e.candidate,
            'sdpMid': e.sdpMid,
            'sdpMlineIndex': e.sdpMLineIndex
          }),
        );
      }
    };

    _peerConnection.onIceConnectionState = (e) {
      debugPrint(e.toString());
    };
  }

  Future<String> _createOffer() async {
    final description =
        await _peerConnection.createOffer({'offerToReceiveVideo': 1});
    _offer = true;
    _peerConnection.setLocalDescription(description);

    return jsonEncode(sdp_transform.parse(description.sdp.toString()));
  }

  Future<String> _createAnswer() async {
    final description =
        await _peerConnection.createAnswer({'offerToReceiveVideo': 1});
    _peerConnection.setLocalDescription(description);

    return jsonEncode(sdp_transform.parse(description.sdp.toString()));
  }

  void _setRemoteDescription(String data) async {
    final sdp = sdp_transform.write(jsonDecode(data), null);

    final description = RTCSessionDescription(sdp, _offer ? 'answer' : 'offer');
    debugPrint(jsonEncode(description.toMap()));

    await _peerConnection.setRemoteDescription(description);
  }

  void _addCandidate(String data) async {
    final session = await jsonDecode(data);
    debugPrint(session['candidate']);

    final candidate = RTCIceCandidate(
      session['candidate'],
      session['sdpMid'],
      session['sdpMlineIndex'],
    );
    await _peerConnection.addCandidate(candidate);
  }

  Future _init() async {
    debugPrint('init renderers');
    await _initRenderers();
    debugPrint('init local stream');
    await _initLocalStream();
    if (mounted) {
      _localVideoRenderer.srcObject = _localStream;
    }
    debugPrint('create peer connection');
    await _createPeerConnection();
    debugPrint('connect signaling');
    await _connectSignaling();
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    super.dispose();
    for (final disposer in _disposers) {
      disposer.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: RTCVideoView(_remoteVideoRenderer)),
            Positioned(
              top: 40,
              left: 20,
              width: 100,
              height: 100,
              child: RTCVideoView(_localVideoRenderer),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: StreamBuilder(
                stream: _signalingConnectStatus.stream,
                builder: (context, snapshot) {
                  String text;
                  switch (snapshot.data) {
                    case SignalingConnectStatus.connecting:
                      text = 'connecting';
                      break;
                    case SignalingConnectStatus.disconnected:
                      text = 'disconnected';
                      break;
                    case SignalingConnectStatus.connected:
                      return const SizedBox();
                    default:
                      text = 'no connection';
                  }
                  return Container(
                    height: 30,
                    color: Colors.red,
                    child: Center(
                      child: Text(
                        text,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: IconButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.close),
                iconSize: 36,
                color: Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
