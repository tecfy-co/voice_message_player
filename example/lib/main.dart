import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:voice_message_package/voice_message_package.dart';

void main() => runApp(const MyApp());

///
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => Sizer(
        builder: (_, __, ___) => MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.grey.shade200,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 300,
                    child: VoiceMessageView(
                      controller: VoiceController(
                        audioSrc:
                            'https://ticketsrv.tecfy.co/file/general/6522d2bded272cf3786b52ab/66ec60e9230596533635fac1-audio_202409190835.ogg',
                        // audioSrc:
                        //     'https://eu2.contabostorage.com/051b18991d4c4fdf9470eb1a6f2c251c:tecfy.ticket/files/Tecfy/20663217070/1397585487799059',
                        maxDuration: const Duration(seconds: 200),
                        isFile: false,
                        onComplete: () {
                          /// do something on complete
                        },
                        onPause: () {
                          /// do something on pause
                        },
                        onPlaying: () {
                          /// do something on playing
                        },
                        onError: (err) {
                          /// do something on error
                        },
                      ),
                      innerPadding: EdgeInsets.all(10),
                      cornerRadius: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
