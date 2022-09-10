import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:p2p_video/config.dart';
import 'package:sdp_transform/sdp_transform.dart' as sdp_transform;

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'p2p video',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const VideoChatPage(),
    );
  }
}

class VideoChatPage extends StatefulWidget {
  const VideoChatPage({super.key});

  @override
  State<VideoChatPage> createState() => _VideoChatPageState();
}

class _VideoChatPageState extends State<VideoChatPage> {
  final _localVideoRenderer = RTCVideoRenderer();
  final _remoteVideoRenderer = RTCVideoRenderer();

  final _sdpController = TextEditingController();
  bool _offer = false;

  late final RTCPeerConnection _peerConnection;
  late final MediaStream _localStream;

  late final _disposers = <VoidCallback>[
    _sdpController.dispose,
  ];

  void _addDisposer(VoidCallback disposer) {
    if (!mounted) {
      disposer.call();
      return;
    }
    _disposers.add(disposer);
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
    _addDisposer(_localStream.dispose);
  }

  Future<void> _createPeerConnection() async {
    _peerConnection =
        await createPeerConnection(webrtcServers, offerSdpConstraints);

    _addDisposer(_peerConnection.dispose);
    if (!mounted) {
      return;
    }

    _peerConnection.addStream(_localStream);

    _peerConnection.onIceCandidate = (e) {
      if (e.candidate != null) {
        debugPrint(jsonEncode({
          'candidate': e.candidate,
          'sdpMid': e.sdpMid,
          'sdpMlineIndex': e.sdpMLineIndex
        }));
      }
    };

    _peerConnection.onIceConnectionState = (e) {
      debugPrint(e.toString());
    };

    _peerConnection.onAddStream = (stream) {
      debugPrint('addStream: ${stream.id}');
      _remoteVideoRenderer.srcObject = stream;
    };
  }

  Future<void> _createOffer() async {
    final description =
        await _peerConnection.createOffer({'offerToReceiveVideo': 1});

    debugPrint(jsonEncode(sdp_transform.parse(description.sdp.toString())));

    _offer = true;
    _peerConnection.setLocalDescription(description);
  }

  void _createAnswer() async {
    final description =
        await _peerConnection.createAnswer({'offerToReceiveVideo': 1});

    debugPrint(jsonEncode(sdp_transform.parse(description.sdp.toString())));

    _peerConnection.setLocalDescription(description);
  }

  void _setRemoteDescription() async {
    final sdp = sdp_transform.write(jsonDecode(_sdpController.text), null);

    final description = RTCSessionDescription(sdp, _offer ? 'answer' : 'offer');
    debugPrint(jsonEncode(description.toMap()));

    await _peerConnection.setRemoteDescription(description);
  }

  void _addCandidate() async {
    final session = await jsonDecode(_sdpController.text);
    debugPrint(session['candidate']);

    final candidate = RTCIceCandidate(
      session['candidate'],
      session['sdpMid'],
      session['sdpMlineIndex'],
    );
    await _peerConnection.addCandidate(candidate);
  }

  Future _init() async {
    await _initRenderers();
    await _initLocalStream();
    if (mounted) {
      _localVideoRenderer.srcObject = _localStream;
    }
    await _createPeerConnection();
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
      appBar: AppBar(
        title: const Text('Video Chat'),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: RTCVideoView(_remoteVideoRenderer)),
          Positioned(
            top: 20,
            left: 20,
            width: 100,
            height: 100,
            child: RTCVideoView(_localVideoRenderer),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    TextField(
                      controller: _sdpController,
                      decoration: const InputDecoration(
                        hintText: 'SDP',
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _createOffer,
                      child: const Text("Offer"),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _createAnswer,
                      child: const Text("Answer"),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _setRemoteDescription,
                      child: const Text("Set Remote Description"),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _addCandidate,
                      child: const Text("Set Candidate"),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    child: const Text("Close"),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
          );
        },
        child: const Icon(Icons.cast_connected_outlined),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
