import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:voice_message_package/src/helpers/play_status.dart';
import 'package:voice_message_package/src/helpers/utils.dart';

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
    positionStream = _player.eventStream.listen((event) async {
      if (event.position == null) return;
      if (!isDownloading) currentDuration = event.position!;

      final value = (noiseWidth * currentMillSeconds) / maxMillSeconds;
      animController.value = value;
      _updateUi();
      if (event.position!.inMilliseconds >= maxMillSeconds) {
        await _player.stop();
        currentDuration = Duration.zero;
        playStatus = PlayStatus.init;
        animController.reset();
        _updateUi();
        onComplete();
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

  /// Starts playing the voice.
  Future startPlaying(String path) async {
    await _player.play(UrlSource(path));
    await _player.setPlaybackRate(speed.getSpeed);
    var duration = await _player.getDuration();
    if (duration != null) {
      maxDuration = duration;
    }
    animController.duration = maxDuration;
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
      } else if (event.eventType == AudioEventType.position) {
        playStatus = PlayStatus.playing;
        _updateUi();
      }
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
