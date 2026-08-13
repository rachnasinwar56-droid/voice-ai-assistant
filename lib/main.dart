import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SiriApp());
}

class SiriApp extends StatelessWidget {
  const SiriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Siri',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF070707),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const SiriHome(),
    );
  }
}

class SiriHome extends StatefulWidget {
  const SiriHome({super.key});

  @override
  State<SiriHome> createState() => _SiriHomeState();
}

class _SiriHomeState extends State<SiriHome> {
  static const String apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static const String siriPhotoUrl =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d3/Siri_logo.svg/512px-Siri_logo.svg.png';

  late final GeminiService _gemini;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<ChatMessage> _messages = [];

  bool _speechAvailable = false;
  bool _listening = false;
  bool _thinking = false;
  bool _speaking = false;

  @override
  void initState() {
    super.initState();

    _gemini = GeminiService(apiKey: apiKey);

    _initializeSpeech();
    _initializeTts();
  }

  Future<void> _initializeSpeech() async {
    final mic = await Permission.microphone.request();

    if (!mic.isGranted) {
      return;
    }

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;

          if (status == 'notListening') {
            setState(() {
              _listening = false;
            });
          }
        },
        onError: (_) {
          if (!mounted) return;

          setState(() {
            _listening = false;
          });
        },
      );

      if (mounted) {
        setState(() {
          _speechAvailable = available;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _speechAvailable = false;
        });
      }
    }
  }

  Future<void> _initializeTts() async {
    try {
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      if (Platform.isAndroid) {
        await _tts.awaitSpeakCompletion(true);
      }
    } catch (_) {}
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;

    try {
      setState(() {
        _speaking = true;
      });

      await _tts.stop();

      await _tts.setLanguage('hi-IN');

      await _tts.speak(text);

      if (mounted) {
        setState(() {
          _speaking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _speaking = false;
        });
      }
    }
  }

  Future<void> _startListening() async {
    if (_thinking) return;

    final permission =
        await Permission.microphone.request();

    if (!permission.isGranted) {
      _show('Microphone permission required.');
      return;
    }

    if (!_speechAvailable) {
      await _initializeSpeech();
    }

    if (!_speechAvailable) {
      _show(
        'Speech recognition is not available on this device.',
      );
      return;
    }

    await _tts.stop();

    setState(() {
      _listening = true;
    });

    try {
      await _speech.listen(
        localeId: 'hi_IN',
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        onResult: (result) {
          if (!mounted) return;

          setState(() {
            _controller.text = result.recognizedWords;

            _controller.selection =
                TextSelection.fromPosition(
              TextPosition(
                offset: _controller.text.length,
              ),
            );
          });

          if (result.finalResult) {
            setState(() {
              _listening = false;
            });

            final text =
                result.recognizedWords.trim();

            if (text.isNotEmpty) {
              _sendMessage(text);
            }
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _listening = false;
        });
      }
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();

    if (mounted) {
      setState(() {
        _listening = false;
      });
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _sendMessage([String? value]) async {
    final text =
        (value ?? _controller.text).trim();

    if (text.isEmpty || _thinking) {
      return;
    }

    if (apiKey.isEmpty) {
      _show(
        'GEMINI_API_KEY missing.\n'
        'GitHub → Settings → Secrets → Actions में key add करें.',
      );
      return;
    }

    await _speech.stop();

    setState(() {
      _listening = false;

      _messages.add(
        ChatMessage(
          role: MessageRole.user,
          text: text,
        ),
      );

      _thinking = true;
      _controller.clear();
    });

    _scrollBottom();

    try {
      final answer =
          await _gemini.ask(text);

      if (!mounted) return;

      setState(() {
        _thinking = false;

        _messages.add(
          ChatMessage(
            role: MessageRole.assistant,
            text: answer,
          ),
        );
      });

      _scrollBottom();

      await _speak(answer);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _thinking = false;
      });

      _show(
        'Gemini error: $e',
      );
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;

      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration:
            const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _show(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior:
            SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _requestPhone() async {
    final result =
        await Permission.phone.request();

    _show(
      result.isGranted
          ? 'Phone permission granted.'
          : 'Phone permission denied.',
    );
  }

  Future<void> _requestSms() async {
    final result =
        await Permission.sms.request();

    _show(
      result.isGranted
          ? 'SMS permission granted.'
          : 'SMS permission denied.',
    );
  }

  Future<void> _openOverlay() async {
    if (!Platform.isAndroid) return;

    try {
      const intent = AndroidIntent(
        action:
            'android.settings.action.MANAGE_OVERLAY_PERMISSION',
      );

      await intent.launch();
    } catch (_) {
      _show(
        'Unable to open Overlay Settings.',
      );
    }
  }

  Future<void> _openNotificationSettings() async {
    if (!Platform.isAndroid) return;

    try {
      const intent = AndroidIntent(
        action:
            'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS',
      );

      await intent.launch();
    } catch (_) {
      _show(
        'Unable to open Notification Settings.',
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,

        leading: Padding(
          padding: const EdgeInsets.all(7),
          child: ClipOval(
            child: Image.network(
              siriPhotoUrl,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) {
                return const CircleAvatar(
                  child: Icon(
                    Icons.auto_awesome,
                  ),
                );
              },
            ),
          ),
        ),

        title: const Text(
          'Siri',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Stop Siri',
            onPressed: () async {
              await _tts.stop();

              if (mounted) {
                setState(() {
                  _speaking = false;
                });
              }
            },
            icon: Icon(
              _speaking
                  ? Icons.volume_up
                  : Icons.volume_off,
            ),
          ),

          PopupMenuButton<String>(
            onSelected:
                (value) async {
              switch (value) {
                case 'mic':
                  await Permission
                      .microphone
                      .request();
                  await _initializeSpeech();
                  break;

                case 'phone':
                  await _requestPhone();
                  break;

                case 'sms':
                  await _requestSms();
                  break;

                case 'overlay':
                  await _openOverlay();
                  break;

                case 'notification':
                  await _openNotificationSettings();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'mic',
                child: Text(
                  'Microphone Permission',
                ),
              ),
              PopupMenuItem(
                value: 'phone',
                child: Text(
                  'Phone Permission',
                ),
              ),
              PopupMenuItem(
                value: 'sms',
                child: Text(
                  'SMS Permission',
                ),
              ),
              PopupMenuItem(
                value: 'overlay',
                child: Text(
                  'Overlay Settings',
                ),
              ),
              PopupMenuItem(
                value: 'notification',
                child: Text(
                  'Notification Access',
                ),
              ),
            ],
          ),
        ],
      ),

      body: Column(
        children: [
          _status(),

          Expanded(
            child: _messages.isEmpty
                ? _empty()
                : ListView.builder(
                    controller: _scroll,
                    padding:
                        const EdgeInsets.all(16),
                    itemCount:
                        _messages.length,
                    itemBuilder:
                        (_, index) {
                      return _bubble(
                        _messages[index],
                      );
                    },
                  ),
          ),

          if (_thinking)
            const Padding(
              padding: EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox(
                    width: 17,
                    height: 17,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Siri सोच रही है...',
                  ),
                ],
              ),
            ),

          _input(),
        ],
      ),
    );
  }

  Widget _status() {
    final ready =
        apiKey.isNotEmpty;

    return Container(
      margin:
          const EdgeInsets.all(12),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: ready
            ? Colors.green
                .withOpacity(.12)
            : Colors.red
                .withOpacity(.12),
        borderRadius:
            BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(
              color: ready
                  ? Colors.green
                  : Colors.red,
              shape: BoxShape.circle,
            ),
          ),

          const SizedBox(width: 10),

          Text(
            ready
                ? (_listening
                    ? 'Listening...'
                    : _speaking
                        ? 'Siri बोल रही है...'
                        : 'Siri Ready')
                : 'Gemini API Key Missing',
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: SingleChildScrollView(
        padding:
            const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Container(
              width: 130,
              height: 130,
              decoration:
                  BoxDecoration(
                shape:
                    BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors
                        .deepPurple
                        .withOpacity(.35),
                    blurRadius: 40,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.network(
                  siriPhotoUrl,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, __, ___) {
                    return Container(
                      color:
                          Colors.deepPurple,
                      child: const Icon(
                        Icons
                            .auto_awesome,
                        size: 65,
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              'Siri',
              style: TextStyle(
                fontSize: 34,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Your AI Voice Assistant',
              style: TextStyle(
                fontSize: 18,
                color:
                    Colors.white70,
              ),
            ),

            const SizedBox(height: 15),

            Text(
              _speechAvailable
                  ? '🎙️ Mic दबाकर बोलें'
                  : 'Microphone तैयार किया जा रहा है...',
              style:
                  const TextStyle(
                color:
                    Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(
      ChatMessage message) {
    final user =
        message.role ==
            MessageRole.user;

    return Align(
      alignment: user
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints:
            const BoxConstraints(
          maxWidth: 340,
        ),
        margin:
            const EdgeInsets.only(
          bottom: 12,
        ),
        padding:
            const EdgeInsets.all(15),
        decoration:
            BoxDecoration(
          color: user
              ? Colors.deepPurple
              : Colors.white
                  .withOpacity(.08),
          borderRadius:
              BorderRadius.circular(
            18,
          ),
        ),
        child: Text(
          message.text,
          style:
              const TextStyle(
            fontSize: 16,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _input() {
    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(
          12,
          8,
          12,
          12,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller:
                    _controller,
                textInputAction:
                    TextInputAction.send,
                onSubmitted: (_) =>
                    _sendMessage(),
                decoration:
                    InputDecoration(
                  hintText: _listening
                      ? 'Siri सुन रही है...'
                      : 'Siri से पूछें...',
                  filled: true,
                  fillColor:
                      Colors.white
                          .withOpacity(
                    .08,
                  ),
                  border:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      28,
                    ),
                    borderSide:
                        BorderSide.none,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            FloatingActionButton(
              heroTag: 'send',
              mini: true,
              onPressed: _thinking
                  ? null
                  : () =>
                      _sendMessage(),
              child: const Icon(
                Icons.send,
              ),
            ),

            const SizedBox(width: 8),

            FloatingActionButton(
              heroTag: 'mic',
              backgroundColor:
                  _listening
                      ? Colors.red
                      : Colors.deepPurple,
              onPressed:
                  _toggleMic,
              child: Icon(
                _listening
                    ? Icons.stop
                    : Icons.mic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ============================================================
// MESSAGE MODEL
// ============================================================

enum MessageRole {
  user,
  assistant,
}

class ChatMessage {
  final MessageRole role;
  final String text;

  ChatMessage({
    required this.role,
    required this.text,
  });
}


// ============================================================
// GEMINI SERVICE
// ============================================================

class GeminiService {
  final String apiKey;

  GeminiService({
    required this.apiKey,
  });

  Future<String> ask(String prompt) async {
    if (apiKey.isEmpty) {
      throw Exception(
        'Gemini API key missing.',
      );
    }

    // Current supported Gemini models.
    //
    // Primary:
    // gemini-3.6-flash
    //
    // Fallback:
    // gemini-3.5-flash
    const models = [
      'gemini-3.6-flash',
      'gemini-3.5-flash',
    ];

    String lastError =
        'No response from Gemini.';

    for (final model in models) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/'
          'v1beta/models/$model:generateContent'
          '?key=$apiKey',
        );

        final response = await http
            .post(
              url,
              headers: {
                'Content-Type':
   
