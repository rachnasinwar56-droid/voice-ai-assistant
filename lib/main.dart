import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SiriApp());
}

// ============================================================
// SIRI APP
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
// SIRI HOME
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

  static const MethodChannel nativeChannel =
      MethodChannel('siri_native');

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
  bool _sendingSms = false;

  @override
  void initState() {
    super.initState();

    _gemini = GeminiService(
      apiKey: apiKey,
    );

    _initializeSpeech();
    _initializeTts();
  }

  // ==========================================================
  // SPEECH INITIALIZATION
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
      } catch (_) {}

      await _tts.stop();
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
  // MICROPHONE
  // ==========================================================

  Future<void> _startListening() async {
    if (_thinking || _sendingSms) return;

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

    try {
      await _speech.listen(
        localeId: 'hi_IN',
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        onResult: (result) {
          if (!mounted) return;

          final words = result.recognizedWords.trim();

          setState(() {
            _controller.text = words;
            _controller.selection = TextSelection.fromPosition(
              TextPosition(
                offset: _controller.text.length,
              ),
            );
          });

          if (result.finalResult) {
            setState(() {
              _listening = false;
            });

            if (words.isNotEmpty) {
              _sendMessage(words);
            }
          }
        },
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _listening = false;
      });
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
  // DIRECT SMS COMMAND
  //
  // Examples:
  //
  // Raj ko message karo main aa raha hu
  // Raj को message करो मैं आ रहा हूँ
  // Send SMS to Raj I am coming
  // Raj ko sms bhejo main aa raha hu
  // ==========================================================

  Future<bool> _handleSmsCommand(String text) async {
    final lower = text.toLowerCase().trim();

    final smsWords = [
      'message',
      'msg',
      'sms',
      'मैसेज',
      'मैसेज करो',
      'एसएमएस',
    ];

    final containsSmsWord = smsWords.any(
      (word) => lower.contains(word.toLowerCase()),
    );

    if (!containsSmsWord) {
      return false;
    }

    String? contactName;
    String? message;

    // ----------------------------------------------------------
    // Hindi / Hinglish:
    //
    // Raj ko message karo main aa raha hu
    // Raj को message करो मैं आ रहा हूँ
    // Raj ko sms bhejo main aa raha hu
    // ----------------------------------------------------------

    final hindiRegex = RegExp(
      r'^\s*(.+?)\s+(?:ko|को)\s+(?:message|msg|sms|मैसेज|एसएमएस)'
      r'(?:\s+(?:karo|kar do|bhejo|भेजो|करो|कर दो))?\s*(.*)$',
      caseSensitive: false,
    );

    final hindiMatch = hindiRegex.firstMatch(text);

    if (hindiMatch != null) {
      contactName = hindiMatch.group(1)?.trim();
      message = hindiMatch.group(2)?.trim();
    }

    // ----------------------------------------------------------
    // English:
    //
    // Send message to Raj I am coming
    // Send SMS to Raj I am coming
    // ----------------------------------------------------------

    if (contactName == null) {
      final englishRegex = RegExp(
        r'^\s*(?:send\s+)?(?:message|msg|sms)\s+'
        r'(?:to|for)\s+(.+?)\s+(.+)$',
        caseSensitive: false,
      );

      final englishMatch = englishRegex.firstMatch(text);

      if (englishMatch != null) {
        contactName = englishMatch.group(1)?.trim();
        message = englishMatch.group(2)?.trim();
      }
    }

    if (contactName == null || contactName.isEmpty) {
      return false;
    }

    // Remove accidental command words from contact name.
    contactName = contactName
        .replaceAll(
          RegExp(
            r'\s+(ko|को)\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    if (message == null || message.trim().isEmpty) {
      _show('Message kya bhejna hai?');

      await _speak(
        'Message kya bhejna hai?',
      );

      return true;
    }

    message = message.trim();

    if (!mounted) return true;

    setState(() {
      _sendingSms = true;
    });

    try {
      // Ask Android native code to:
      // 1. Find contact
      // 2. Get phone number
      // 3. Send SMS
      final result = await nativeChannel.invokeMethod(
        'sendSmsToContact',
        {
          'contactName': contactName,
          'message': message,
        },
      );

      final success = result is Map &&
          result['success'] == true;

      if (success) {
        final sentTo =
            result['contactName']?.toString() ?? contactName;

        _addAssistantMessage(
          'SMS sent to $sentTo.',
        );

        await _speak(
          '$sentTo को message भेज दिया है।',
        );
      } else {
        final error =
            result is Map
                ? result['error']?.toString()
                : null;

        final errorText =
            error == null || error.isEmpty
                ? 'Contact नहीं मिला या SMS नहीं भेजा जा सका।'
                : error;

        _show(errorText);

        await _speak(errorText);
      }
    } on PlatformException catch (e) {
      String messageText;

      switch (e.code) {
        case 'SMS_PERMISSION':
          messageText =
              'SMS permission की जरूरत है। कृपया Allow करें।';
          break;

        case 'CONTACT_PERMISSION':
          messageText =
              'Contacts permission की जरूरत है।';
          break;

        case 'CONTACT_NOT_FOUND':
          messageText =
              '$contactName नाम का contact नहीं मिला।';
          break;

        default:
          messageText =
              e.message ?? 'SMS भेजने में समस्या हुई।';
      }

      _show(messageText);
      await _speak(messageText);
    } catch (e) {
      _show('SMS error: $e');
      await _speak('SMS भेजने में समस्या हुई।');
    } finally {
      if (mounted) {
        setState(() {
          _sendingSms = false;
        });
      }
    }

    return true;
  }

  // ==========================================================
  // SEND / GEMINI
  // ==========================================================

  Future<void> _sendMessage([String? value]) async {
    final text = (
