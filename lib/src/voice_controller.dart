import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:voice_message_package/src/helpers/play_status.dart';
import 'package:voice_message_package/src/helpers/utils.dart';
import 'package:http/http.dart' as http;

/// A controller for managing voice playback.
///
/// The [VoiceController] class provides functionality for playing, pausing, stopping, and seeking voice playback.
/// It uses the [just_audio](https://pub.dev/packages/just_audio) package for audio playback.
/// The controller also supports changing the playback speed and provides UI updates through a [ValueNotifier].
///
/// Example usage:
/// ```dart
/// VoiceController voiceController = VoiceController(
///   audioSrc: 'path/to/audio.mp3',
///   maxDuration: Duration(minutes: 5),
///   isFile: true,
///   onComplete: () {
///   },
///   onPause: () {
///   },
///   onPlaying: () {
///   },
/// );
///
class VoiceController extends MyTicker {
  final String audioSrc;
  String? filePath;
  late Duration maxDuration;
  Duration currentDuration = Duration.zero;
  final Function() onComplete;
  final Function() onPlaying;
  final Function() onPause;
  final Function(Object)? onError;
  late AnimationController animController;
  final AudioPlayer _player = AudioPlayer();
  final bool isFile;
  PlayStatus playStatus = PlayStatus.init;
  PlaySpeed speed = PlaySpeed.x1;
  ValueNotifier<int> updater = ValueNotifier<int>(0);
  List<double>? randoms;
  StreamSubscription? positionStream;
  StreamSubscription? playerStateStream;
  double? downloadProgress = 0;
  Uint8List? bytes;

  /// Gets the current playback position of the voice.
  double get currentMillSeconds {
    final c = currentDuration.inMilliseconds.toDouble();
    if (c >= maxMillSeconds) {
      return maxMillSeconds;
    }
    return c;
  }

  bool isSeeking = false;

  bool get isPlaying => playStatus == PlayStatus.playing;

  bool get isInit => playStatus == PlayStatus.init;

  bool get isDownloading => playStatus == PlayStatus.downloading;

  bool get isDownloadError => playStatus == PlayStatus.downloadError;

  bool get isStop => playStatus == PlayStatus.stop;

  bool get isPause => playStatus == PlayStatus.pause;

  double get maxMillSeconds => maxDuration.inMilliseconds.toDouble();
  late double noiseWidth;

  /// Creates a new [VoiceController] instance.
  VoiceController({
    required this.audioSrc,
    required this.maxDuration,
    required this.isFile,
    required this.onComplete,
    required this.onPause,
    required this.onPlaying,
    this.onError,
    this.randoms,
  });

  Future<bool> _convertRecordedFile() async {
    if (filePath != null) return true;
    if (audioSrc.isEmpty) {
      playStatus = PlayStatus.downloadError;
      _updateUi();
      print('XXXXX source URI is blank!');
      return false;
    }
    print('start download ausio file..');
    try {
      var res = await http.get(Uri.parse(audioSrc));
      bytes = res.bodyBytes;
      var filePathSource = [
        (await getApplicationDocumentsDirectory()).path,
        "audio.ogg"
      ].join('/');
      await File(filePathSource).writeAsBytes(bytes!);
      filePath = "$filePathSource.aac";
      if (await File(filePath!).exists()) {
        await File(filePath!).delete();
      }
      var session = await FFmpegKit.execute(
          '-i "$filePathSource" -c:a aac -strict -2 "$filePath"');
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        print('XXXXXXXXXXXXXXXXXX Error converting file');
        print(returnCode);
        playStatus = PlayStatus.downloadError;
        _updateUi();
        return false;
      }

      if (await File(filePath!).exists()) {
        print('++++++++++++++++++++++++++ found!!');
        filePath = filePath;
      } else {
        print('XXXXXXXXX Audio file not found!!');
        playStatus = PlayStatus.downloadError;
        _updateUi();
        return false;
      }
      // // Unique session id created for this execution
      // final sessionId = session.getSessionId();
      // print('sessionId : $sessionId');

      // // Command arguments as a single string
      // final command = session.getCommand();
      // print('command : $command');

      // // Command arguments
      // final commandArguments = session.getArguments();
      // print('commandArguments : $commandArguments');

      // // State of the execution. Shows whether it is still running or completed
      // final state = await session.getState();
      // print('state : $state}');

      // final startTime = session.getStartTime();
      // print('startTime : $startTime');
      // final endTime = await session.getEndTime();
      // print('endTime : $endTime');
      // final duration = await session.getDuration();
      // print('duration : $duration');

      // // Console output generated for this execution
      // final output = await session.getOutput();
      // print('output : $output');

      // // The stack trace if FFmpegKit fails to run a command
      // final failStackTrace = await session.getFailStackTrace();
      // print('failStackTrace : $failStackTrace');
      print('file downloaded and converted successfully!');
      playStatus = PlayStatus.init;
      _updateUi();
      return true;
    } catch (err, t) {
      print(err);
      print(t);
      return false;
    }
  }

  /// Initializes the voice controller.
  bool isInited = false;
  Future init(double _noiseWidth) async {
    if (isInited) return;
    isInited = true;
    noiseWidth = _noiseWidth;
    if (randoms?.isEmpty ?? true) _setRandoms();
    animController = AnimationController(
      vsync: this,
      upperBound: noiseWidth,
      duration: maxDuration,
    );
    // _updateUi();
    _listenToRemindingTime();
    _listenToPlayerState();
  }

  Future play() async {
    try {
      playStatus = PlayStatus.downloading;
      _updateUi();
      if (isFile) {
        await startPlaying(audioSrc);
        onPlaying();
      } else {
        await startPlaying(audioSrc);
        onPlaying();
        _updateUi();
      }
    } catch (err) {
      playStatus = PlayStatus.downloadError;
      _updateUi();
      if (onError != null) {
        onError!(err);
      } else {
        rethrow;
      }
    }
  }

  void _listenToRemindingTime() {
    positionStream = _player.onPositionChanged.listen((position) async {
      // if (event.position == null) return;
      if (!isDownloading) currentDuration = position;

      final value = (noiseWidth * currentMillSeconds) / maxMillSeconds;
      animController.value = value;

      if (position.inMilliseconds >= maxMillSeconds) {
        await _player.stop();
        currentDuration = Duration.zero;
        playStatus = PlayStatus.init;
        animController.reset();
        _updateUi();
        onComplete();
      } else {
        playStatus = PlayStatus.playing;
        _updateUi();
      }
    });
  }

  void _updateUi() {
    // updater.notifyListeners();
    updater.value++;
  }

  /// Stops playing the voice.
  Future stopPlaying() async {
    await _player.pause();
    playStatus = PlayStatus.stop;
  }

  Future<bool> _tryToDownloadAndPlayFile() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        var result = await _convertRecordedFile();
        if (!result) return false;

        await _player.play(DeviceFileSource(filePath!));
        if (speed.getSpeed != 1.0) {
          await _player.setPlaybackRate(speed.getSpeed);
        }

        //----------------
        // the following lines make some audio files not working on Web and some mobile devices
        // like https://ticketsrv.tecfy.co/file/general/6522d2bded272cf3786b52ab/66ec60e9230596533635fac1-audio_202409190835.ogg
        //----------------
        // var duration = await _player.getDuration();
        // if (duration != null) {
        //   maxDuration = duration;
        // }
        // animController.duration = maxDuration;
        return true;
      }
    } catch (err) {
      print('XXXX _tryToDownloadAndPlayFile XXX $err');
    }
    return false;
  }

  /// Starts playing the voice.
  Future startPlaying(String path) async {
    if (await _tryToDownloadAndPlayFile()) return;
    // print(path);
    await _player.play(UrlSource(path));
    if (speed.getSpeed != 1.0) {
      await _player.setPlaybackRate(speed.getSpeed);
    }

    //----------------
    // the following lines make some audio files not working on Web and some mobile devices
    // like https://ticketsrv.tecfy.co/file/general/6522d2bded272cf3786b52ab/66ec60e9230596533635fac1-audio_202409190835.ogg
    //----------------
    // var duration = await _player.getDuration();
    // if (duration != null) {
    //   maxDuration = duration;
    // }
    // animController.duration = maxDuration;
  }

  Future<void> dispose() async {
    await _player.dispose();
    positionStream?.cancel();
    playerStateStream?.cancel();
    animController.dispose();
  }

  /// Seeks to the given [duration].
  void onSeek(Duration duration) {
    isSeeking = false;
    currentDuration = duration;
    _updateUi();
    _player.seek(duration);
  }

  /// Pauses the voice playback.
  void pausePlaying() async {
    await _player.pause();
    await Future.delayed(Duration(milliseconds: 50));
    playStatus = PlayStatus.pause;
    _updateUi();
    onPause();
  }

  void cancelDownload() {
    playStatus = PlayStatus.init;
    _updateUi();
  }

  /// Resumes the voice playback.
  void _listenToPlayerState() {
    playerStateStream = _player.eventStream.listen((event) async {
      if (event.eventType == AudioEventType.complete) {
        // await _player.stop();
        // currentDuration = Duration.zero;
        playStatus = PlayStatus.init;
        // animController.reset();
        _updateUi();
        // onComplete();
      }
      // else if (event.eventType == AudioEventType.position) {
      //   playStatus = PlayStatus.playing;
      //   _updateUi();
      // }
    });
  }

  /// Changes the speed of the voice playback.
  void changeSpeed() {
    // Function implementation goes here
    switch (speed) {
      case PlaySpeed.x1:
        speed = PlaySpeed.x1_25;
        break;
      case PlaySpeed.x1_25:
        speed = PlaySpeed.x1_5;
        break;
      case PlaySpeed.x1_5:
        speed = PlaySpeed.x1_75;
        break;
      case PlaySpeed.x1_75:
        speed = PlaySpeed.x2;
        break;
      case PlaySpeed.x2:
        speed = PlaySpeed.x2_25;
        break;
      case PlaySpeed.x2_25:
        speed = PlaySpeed.x1;
        break;
    }
    _player.setPlaybackRate(speed.getSpeed);
    _updateUi();
  }

  /// Changes the speed of the voice playback.
  void onChangeSliderStart(double value) {
    isSeeking = true;

    /// pause the voice
    pausePlaying();
  }

  void _setRandoms() {
    randoms = [];
    for (var i = 0; i < (noiseWidth / 5.5); i++) {
      randoms!.add(5.74.w() * Random().nextDouble() + .26.w());
    }
  }

  /// Changes the speed of the voice playback.
  void onChanging(double d) {
    currentDuration = Duration(milliseconds: d.toInt());
    final value = (noiseWidth * d) / maxMillSeconds;
    animController.value = value;
    _updateUi();
  }

  ///
  String get remindingTime {
    if (currentDuration == Duration.zero) {
      return maxDuration.formattedTime;
    }
    if (isSeeking || isPause) {
      return currentDuration.formattedTime;
    }
    if (isInit) {
      return maxDuration.formattedTime;
    }
    return currentDuration.formattedTime;
  }
}

/// A custom [TickerProvider] implementation for the voice controller.
///
/// This class provides the necessary functionality for controlling the voice playback.
/// It implements the [TickerProvider] interface, allowing it to create [Ticker] objects
/// that can be used to schedule animations or other periodic tasks.
///
/// Example usage:
/// ```dart
/// VoiceController voiceController = VoiceController();
/// voiceController.start();
/// voiceController.stop();
/// ```

///
/// This class extends [TickerProvider] and provides a custom ticker for the voice controller.
/// It can be used to create animations or perform actions at regular intervals.
class MyTicker extends TickerProvider {
  @override

  /// Creates a new ticker.
  Ticker createTicker(TickerCallback onTick) {
    return Ticker(onTick);
  }
}
