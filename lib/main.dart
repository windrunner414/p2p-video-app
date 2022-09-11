import 'package:flutter/material.dart';
import 'package:oktoast/oktoast.dart';
import 'package:p2p_video/global.dart';
import 'package:p2p_video/video_chat.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sharedPrefs = await SharedPreferences.getInstance();
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
      builder: (BuildContext context, Widget? widget) {
        return OKToast(child: widget ?? const SizedBox());
      },
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _signalingServerController =
      TextEditingController(text: sharedPrefs.getString('signalingServer'));
  final _stunServerController =
      TextEditingController(text: sharedPrefs.getString('stunServer'));
  final _roomNameController =
      TextEditingController(text: sharedPrefs.getString('roomName'));
  final _roomPasswordController =
      TextEditingController(text: sharedPrefs.getString('roomPassword'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('P2P Video')),
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TextField(
              controller: _signalingServerController,
              decoration: const InputDecoration(
                hintText: 'signaling server',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _stunServerController,
              decoration: const InputDecoration(
                hintText: 'stun server',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _roomNameController,
              decoration: const InputDecoration(
                hintText: 'room name',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _roomPasswordController,
              decoration: const InputDecoration(
                hintText: 'room password',
              ),
              autocorrect: false,
              obscureText: true,
            ),
            const SizedBox(height: 15),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => VideoChatPage(
                    signalingServer: _signalingServerController.text,
                    stunServer: _stunServerController.text,
                    roomName: _roomNameController.text,
                    roomPassword: _roomPasswordController.text,
                  ),
                ));

                sharedPrefs.setString(
                  'signalingServer',
                  _signalingServerController.text,
                );
                sharedPrefs.setString('stunServer', _stunServerController.text);
                sharedPrefs.setString('roomName', _roomNameController.text);
                sharedPrefs.setString(
                  'roomPassword',
                  _roomPasswordController.text,
                );
              },
              child: const Text('Start!'),
            ),
          ],
        ),
      ),
    );
  }
}
