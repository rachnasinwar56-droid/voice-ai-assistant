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

  // ==========================================================
  // SPEECH RECOGNITION
  // ==========================================================

  Future<void> _initializeSpeech() async {
    final permission = await Permission.microphone.request();

    if (!permission.isGranted) {
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

  // ==========================================================
  // TTS
  // ==========================================================

  Future<void> _initializeTts() async {
    try {
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      if (Platform.isAndroid) {
        await _tts.awaitSpeakCompletion(true);
      }

      try {
        await _tts.setLanguage('hi-IN');
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;

    try {
      await _tts.stop();

      if (!mounted) return;

      setState(() {
        _speaking = true;
      });

      try {
        await _tts.setLanguage('hi-IN');
      } catch (_) {}

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

  // ==========================================================
  // VOICE INPUT
  // ==========================================================

  Future<void> _startListening() async {
    if (_thinking || _speaking) return;

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

    if (!mounted) return;

    setState(() {
      _listening = true;
      _speaking = false;
      _controller.clear();
    });

    try {
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

          if (result.finalResult && recognized.isNotEmpty) {
            setState(() {
              _listening = false;
            });

            _handleVoiceCommand(recognized);
          }
        },
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _listening = false;
      });

      _show('Microphone start nahi ho saka.');
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

  // ==========================================================
  // VOICE COMMAND ENGINE
  // ==========================================================

  Future<void> _handleVoiceCommand(String text) async {
    final command = text.trim();

    if (command.isEmpty) return;

    final lower = command.toLowerCase();

    // --------------------------------------------------------
    // CALL COMMAND
    // Example:
    // "Raj ko call karo"
    // --------------------------------------------------------

    if (_containsAny(lower, [
      'call karo',
      'call kar',
      'phone karo',
      'फोन करो',
      'कॉल करो',
    ])) {
      final name = _extractPersonName(
        command,
        [
          'ko call karo',
          'ko call kar',
          'ko phone karo',
          'को कॉल करो',
          'को फोन करो',
        ],
      );

      if (name.isNotEmpty) {
        await _makeCallByName(name);
        return;
      }
    }

    // --------------------------------------------------------
    // SMS COMMAND
    // Example:
    // "Raj ko SMS karo main aa raha hu"
    // --------------------------------------------------------

    if (_containsAny(lower, [
      'sms karo',
      'sms kar',
      'message karo',
      'message kar',
      'मैसेज करो',
      'मैसेज कर',
      'एसएमएस करो',
    ])) {
      final parsed = _parseMessageCommand(command);

      if (parsed != null) {
        await _sendSmsByName(
          parsed.name,
          parsed.message,
        );
        return;
      }
    }

    // --------------------------------------------------------
    // WHATSAPP COMMAND
    // Example:
    // "Raj ko WhatsApp message karo main aa raha hu"
    // --------------------------------------------------------

    if (_containsAny(lower, [
      'whatsapp',
      'व्हाट्सऐप',
      'व्हाट्सएप',
    ])) {
      final parsed = _parseWhatsAppCommand(command);

      if (parsed != null) {
        await _openWhatsApp(
          parsed.name,
          parsed.message,
        );
        return;
      }
    }

    // --------------------------------------------------------
    // NORMAL GEMINI QUESTION
    // --------------------------------------------------------

    await _sendMessage(command);
  }

  bool _containsAny(String text, List<String> values) {
    for (final value in values) {
      if (text.contains(value.toLowerCase())) {
        return true;
      }
    }

    return false;
  }

  // ==========================================================
  // NAME EXTRACTION
  // ==========================================================

  String _extractPersonName(
    String text,
    List<String> markers,
  ) {
    String result = text;

    for (final marker in markers) {
      final index = result.toLowerCase().indexOf(
            marker.toLowerCase(),
          );

      if (index >= 0) {
        result = result.substring(0, index);
        break;
      }
    }

    result = result
        .replaceAll(
          RegExp(
            r'^(raj|rahul|rohan|amit|ajay)\s+',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    return result.trim();
  }

  // ==========================================================
  // MESSAGE PARSER
  // ==========================================================

  ParsedCommand? _parseMessageCommand(String text) {
    final patterns = [
      RegExp(
        r'^(.+?)\s+ko\s+(?:sms|message)\s+(?:karo|kar)\s+(.+)$',
        caseSensitive: false,
      ),
      RegExp(
        r'^(.+?)\s+ko\s+(?:मैसेज|एसएमएस)\s+(?:करो|कर)\s+(.+)$',
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);

      if (match != null) {
        return ParsedCommand(
          name: match.group(1)!.trim(),
          message: match.group(2)!.trim(),
        );
      }
    }

    return null;
  }

  // ==========================================================
  // WHATSAPP PARSER
  // ==========================================================

  ParsedCommand? _parseWhatsAppCommand(String text) {
    final patterns = [
      RegExp(
        r'^(.+?)\s+ko\s+(?:whatsapp\s+)?(?:message\s+)?(?:karo|kar)\s+(.+)$',
        caseSensitive: false,
      ),
      RegExp(
        r'^(.+?)\s+ko\s+whatsapp\s+(.+)$',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);

      if (match != null) {
        return ParsedCommand(
          name: match.group(1)!.trim(),
          message: match.group(2)!.trim(),
        );
      }
    }

    return null;
  }

  // ==========================================================
  // CONTACT NAME -> PHONE NUMBER
  // ==========================================================

  Future<String?> _findContactNumber(String name) async {
    // Is version me contact database directly access nahi kiya gaya.
    //
    // Isliye pehle user ko contact number enter karne ka option
    // diya jayega.
    //
    // Automatic contact directory lookup ke liye contacts_service
    // package add kiya ja sakta hai.

    return null;
  }

  // ==========================================================
  // CALL
  // ==========================================================

  Future<void> _makeCallByName(String name) async {
    final number = await _askForNumber(
      title: 'Call contact',
      name: name,
    );

    if (number == null || number.trim().isEmpty) {
      return;
    }

    final permission = await Permission.phone.request();

    if (!permission.isGranted) {
      _show('Phone permission required.');
      await _speak('Phone permission chahiye.');
      return;
    }

    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.CALL',
        data: 'tel:${_cleanNumber(number)}',
      );

      await intent.launch();

      await _speak('$name ko call kar rahi hoon.');
    } catch (e) {
      _show('Call start nahi ho saka.');
      await _speak('Call start nahi ho saka.');
    }
  }

  // ==========================================================
  // SMS
  // ==========================================================

  Future<void> _sendSmsByName(
    String name,
    String message,
  ) async {
    final number = await _askForNumber(
      title: 'SMS contact',
      name: name,
    );

    if (number == null || number.trim().isEmpty) {
      return;
    }

    final permission = await Permission.sms.request();

    if (!permission.isGranted) {
      _show('SMS permission required.');
      await _speak('SMS permission chahiye.');
      return;
    }

    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SENDTO',
        data: 'smsto:${_cleanNumber(number)}',
        arguments: <String, dynamic>{
          'sms_body': message,
        },
      );

      await intent.launch();

      await _speak(
        '$name ke liye message tayyar hai.',
      );
    } catch (_) {
      _show('SMS app open nahi ho saki.');
      await _speak('SMS app open nahi ho saki.');
    }
  }

  // ==========================================================
  // WHATSAPP
  // ==========================================================

  Future<void> _openWhatsApp(
    String name,
    String message,
  ) async {
    final number = await _askForNumber(
      title: 'WhatsApp contact',
      name: name,
    );

    if (number == null || number.trim().isEmpty) {
      return;
    }

    final clean = _cleanNumber(number);

    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: 'https://wa.me/$clean?text=${Uri.encodeComponent(message)}',
      );

      await intent.launch();

      await _speak(
        '$name ka WhatsApp message tayyar hai.',
      );
    } catch (_) {
      _show('WhatsApp open nahi ho saka.');
      await _speak('WhatsApp open nahi ho saka.');
    }
  }

  String _cleanNumber(String value) {
    return value.replaceAll(
      RegExp(r'[^0-9+]'),
      '',
    );
  }

  // ==========================================================
  // NUMBER DIALOG
  // ==========================================================

  Future<String?> _askForNumber({
    required String title,
    required String name,
  }) async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$title: $name'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: 'Phone number',
              labelText: 'Number',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  controller.text.trim(),
                );
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    return result;
  }

  // ==========================================================
  // NORMAL GEMINI CHAT
  // ==========================================================

  Future<void> _sendMessage([String? value]) async {
    final text = (value ?? _controller.text).trim();

    if (text.isEmpty || _thinking) {
      return;
    }

    if (apiKey.isEmpty) {
      _show(
        'GEMINI_API_KEY missing.\n'
        'GitHub Secrets me GEMINI_API_KEY add karein.',
      );
      return;
    }

    try {
      await _speech.stop();
    } catch (_) {}

    if (!mounted) return;

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

      _show('Gemini Error: $e');
    }
  }

  // ==========================================================
  // UI
  // ==========================================================

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

  void _show(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
        title: const Text(
          'Siri',
          style: TextStyle(
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
                  await Permission.phone.request();
                  break;

                case 'sms':
                  await Permission.sms.request();
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
              PopupMenuItem(
                value: 'overlay',
                child: Text('Overlay Settings'),
              ),
              PopupMenuItem(
                value: 'notification',
                child: Text('Notification Access'),
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
                      return _bubble(_messages[index]);
                    },
                  ),
          ),

          if (_thinking)
            const Padding(
              padding: EdgeInsets.all(10),
              child: Row(
                children: [
                  Sized
