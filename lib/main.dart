import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SiriApp());
}

// ============================================================
// APP
// ============================================================

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

// ============================================================
// HOME
// ============================================================

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

  // ============================================================
  // SPEECH
  // ============================================================

  Future<void> _initializeSpeech() async {
    try {
      final permission = await Permission.microphone.request();

      if (!permission.isGranted) {
        return;
      }

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

      if (!mounted) return;

      setState(() {
        _speechAvailable = available;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _speechAvailable = false;
      });
    }
  }

  // ============================================================
  // TTS
  // ============================================================

  Future<void> _initializeTts() async {
    try {
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;

    try {
      if (mounted) {
        setState(() {
          _speaking = true;
        });
      }

      try {
        await _tts.setLanguage('hi-IN');
      } catch (_) {
        try {
          await _tts.setLanguage('en-IN');
        } catch (_) {}
      }

      await _tts.speak(text);

      if (!mounted) return;

      setState(() {
        _speaking = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _speaking = false;
      });
    }
  }

  // ============================================================
  // MICROPHONE
  // ============================================================

  Future<void> _startListening() async {
    if (_thinking) return;

    try {
      final permission = await Permission.microphone.request();

      if (!permission.isGranted) {
        _show('Microphone permission required.');
        return;
      }

      if (!_speechAvailable) {
        await _initializeSpeech();
      }

      if (!_speechAvailable) {
        _show('Speech recognition is not available.');
        return;
      }

      await _tts.stop();

      if (mounted) {
        setState(() {
          _listening = true;
        });
      }

      await _speech.listen(
        localeId: 'hi_IN',
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        onResult: (result) {
          if (!mounted) return;

          final recognized = result.recognizedWords.trim();

          setState(() {
            _controller.text = recognized;

            _controller.selection = TextSelection.fromPosition(
              TextPosition(
                offset: _controller.text.length,
              ),
            );
          });

          // ======================================================
          // IMPORTANT:
          // Voice result automatically goes to _sendMessage().
          // User does NOT need to press Send.
          // ======================================================

          if (result.finalResult && recognized.isNotEmpty) {
            setState(() {
              _listening = false;
            });

            _sendMessage(recognized);
          }
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _listening = false;
      });

      _show('Microphone error.');
    }
  }

  Future<void> _stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _listening = false;
    });
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  // ============================================================
  // SEND TO GEMINI
  // ============================================================

  Future<void> _sendMessage([String? value]) async {
    final text = (value ?? _controller.text).trim();

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

    try {
      await _speech.stop();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _listening = false;
      _thinking = true;
      _controller.clear();

      _messages.add(
        ChatMessage(
          role: MessageRole.user,
          text: text,
        ),
      );
    });

    _scrollBottom();

    try {
      final answer = await _gemini.ask(text);

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

      _show('Error: $e');
    }
  }

  // ============================================================
  // SCROLL
  // ============================================================

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;

      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _show(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================================
  // PERMISSIONS
  // ============================================================

  Future<void> _requestPhone() async {
    final result = await Permission.phone.request();

    _show(
      result.isGranted
          ? 'Phone permission granted.'
          : 'Phone permission denied.',
    );
  }

  Future<void> _requestSms() async {
    final result = await Permission.sms.request();

    _show(
      result.isGranted
          ? 'SMS permission granted.'
          : 'SMS permission denied.',
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();

    _speech.stop();
    _tts.stop();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

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
              errorBuilder: (_, __, ___) {
                return const CircleAvatar(
                  child: Icon(Icons.auto_awesome),
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

              if (!mounted) return;

              setState(() {
                _speaking = false;
              });
            },
            icon: Icon(
              _speaking
                  ? Icons.volume_up
                  : Icons.volume_off,
            ),
          ),

          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'mic':
                  await Permission.microphone.request();
                  await _initializeSpeech();
                  break;

                case 'phone':
                  await _requestPhone();
                  break;

                case 'sms':
                  await _requestSms();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'mic',
                child: Text('Microphone Permission'),
              ),
              PopupMenuItem(
                value: 'phone',
                child: Text('Phone Permission'),
              ),
              PopupMenuItem(
                value: 'sms',
                child: Text('SMS Permission'),
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
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) {
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text('Siri सोच रही है...'),
                ],
              ),
            ),

          _input(),
        ],
      ),
    );
  }

  // ============================================================
  // STATUS
  // ============================================================

  Widget _status() {
    final ready = apiKey.isNotEmpty;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: ready
            ? Colors.green.withOpacity(.12)
            : Colors.red.withOpacity(.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
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

  // ============================================================
  // EMPTY
  // ============================================================

  Widget _empty() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(.35),
                    blurRadius: 40,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.network(
                  siriPhotoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return Container(
                      color: Colors.deepPurple,
                      child: const Icon(
                        Icons.auto_awesome,
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
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Your AI Voice Assistant',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white70,
              ),
            ),

            const SizedBox(height: 15),

            Text(
              _speechAvailable
                  ? '🎙️ Mic दबाकर बोलें'
                  : 'Microphone तैयार किया जा रहा है...',
              style: const TextStyle(
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CHAT BUBBLE
  // ============================================================

  Widget _bubble(ChatMessage message) {
    final isUser =
        message.role == MessageRole.user;

    return Align(
      alignment: isUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 340,
        ),
        margin: const EdgeInsets.only(
          bottom: 12,
        ),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isUser
              ? Colors.deepPurple
              : Colors.white.withOpacity(.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          message.text,
          style: const TextStyle(
            fontSize: 16,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // INPUT
  // ============================================================

  Widget _input() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          12,
          8,
          12,
          12,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction:
                    TextInputAction.send,
                onSubmitted: (_) {
                  _sendMessage();
                },
                decoration: InputDecoration(
                  hintText: _listening
                      ? 'Siri सुन रही है...'
                      : 'Siri से पूछें...',
                  filled: true,
                  fillColor:
                      Colors.white.withOpacity(.08),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Manual send button.
            // Voice input does NOT need this.
            FloatingActionButton(
              heroTag: 'send',
              mini: true,
              onPressed: _thinking
                  ? null
                  : () {
                      _sendMessage();
                    },
              child: const Icon(Icons.send),
            ),

            const SizedBox(width: 8),

            FloatingActionButton(
              heroTag: 'mic',
              backgroundColor: _listening
                  ? Colors.red
                  : Colors.deepPurple,
              onPressed: _toggleMic,
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
// MODELS
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
// GEMINI
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

    // Use a currently supported Flash model.
    const String model = 'gemini-2.5-flash';

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent?key=$apiKey',
    );

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'text': prompt,
     
