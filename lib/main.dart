import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoiceAssistantApp());
}

class VoiceAssistantApp extends StatelessWidget {
  const VoiceAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice AI Assistant',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080808),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AssistantHome(),
    );
  }
}

class AssistantHome extends StatefulWidget {
  const AssistantHome({super.key});

  @override
  State<AssistantHome> createState() => _AssistantHomeState();
}

class _AssistantHomeState extends State<AssistantHome> {
  late final GeminiLiveService _gemini;

  final TextEditingController _textController = TextEditingController();

  bool _connected = false;
  bool _listening = false;
  bool _thinking = false;

  String _status = 'Disconnected';

  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();

    _gemini = GeminiLiveService(
      apiKey: const String.fromEnvironment(
        'GEMINI_API_KEY',
        defaultValue: '',
      ),
      model: 'gemini-3.1-flash-live-preview',
    );

    _gemini.onText = (text) {
      if (!mounted) return;

      setState(() {
        _thinking = false;

        if (_messages.isNotEmpty &&
            _messages.last.role == MessageRole.assistant) {
          _messages.last = ChatMessage(
            role: MessageRole.assistant,
            text: '${_messages.last.text}$text',
          );
        } else {
          _messages.add(
            ChatMessage(
              role: MessageRole.assistant,
              text: text,
            ),
          );
        }
      });
    };

    _gemini.onStatus = (status) {
      if (!mounted) return;

      setState(() {
        _status = status;
      });
    };

    _gemini.onConnected = () {
      if (!mounted) return;

      setState(() {
        _connected = true;
        _status = 'Connected';
      });
    };

    _gemini.onDisconnected = () {
      if (!mounted) return;

      setState(() {
        _connected = false;
        _status = 'Disconnected';
        _thinking = false;
        _listening = false;
      });
    };

    _gemini.onError = (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    };
  }

  @override
  void dispose() {
    _textController.dispose();
    _gemini.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (const String.fromEnvironment(
      'GEMINI_API_KEY',
      defaultValue: '',
    ).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'GEMINI_API_KEY missing. Run with --dart-define.',
          ),
        ),
      );
      return;
    }

    await _gemini.connect();
  }

  Future<void> _requestMicrophone() async {
    final status = await Permission.microphone.request();

    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission is required.'),
        ),
      );
    }
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();

    if (text.isEmpty) return;

    if (!_connected) {
      await _connect();
    }

    setState(() {
      _messages.add(
        ChatMessage(
          role: MessageRole.user,
          text: text,
        ),
      );

      _thinking = true;
    });

    _textController.clear();

    await _gemini.sendText(text);
  }

  Future<void> _toggleListening() async {
    if (!_connected) {
      await _connect();
      return;
    }

    await _requestMicrophone();

    setState(() {
      _listening = !_listening;
    });

    if (_listening) {
      await _gemini.startMicrophone();
    } else {
      await _gemini.stopMicrophone();
    }
  }

  Future<void> _openOverlaySettings() async {
    if (!Platform.isAndroid) return;

    const intent = AndroidIntent(
      action: 'android.settings.action.MANAGE_OVERLAY_PERMISSION',
    );

    await intent.launch();
  }

  Future<void> _openNotificationSettings() async {
    if (!Platform.isAndroid) return;

    const intent = AndroidIntent(
      action: 'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS',
    );

    await intent.launch();
  }

  Future<void> _requestCallPermission() async {
    await Permission.phone.request();
  }

  Future<void> _requestSmsPermission() async {
    await Permission.sms.request();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Voice AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Connect',
            onPressed: _connected ? null : _connect,
            icon: Icon(
              _connected ? Icons.cloud_done : Icons.cloud_off,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'mic':
                  await _requestMicrophone();
                  break;

                case 'phone':
                  await _requestCallPermission();
                  break;

                case 'sms':
                  await _requestSmsPermission();
                  break;

                case 'overlay':
                  await _openOverlaySettings();
                  break;

                case 'notifications':
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
                child: Text('Call Permission'),
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
                value: 'notifications',
                child: Text('Notification Access'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatus(),

          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) {
                      return _buildMessage(
                        _messages[index],
                      );
                    },
                  ),
          ),

          if (_thinking)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text('Gemini is thinking...'),
                ],
              ),
            ),

          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildStatus() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: _connected
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
              shape: BoxShape.circle,
              color: _connected ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 10),
          Text(_status),
          const Spacer(),
          if (_listening)
            const Text(
              'LISTENING',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.graphic_eq,
              size: 90,
              color: Colors.deepPurple.shade300,
            ),
            const SizedBox(height: 20),
            const Text(
              'Voice AI Assistant',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Talk to Gemini using voice or text.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.role == MessageRole.user;

    return Align(
      alignment:
          isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 12),
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

  Widget _buildInput() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                onSubmitted: (_) => _sendText(),
                decoration: InputDecoration(
                  hintText: 'Ask anything...',
                  filled: true,
                  fillColor: Colors.white.withOpacity(.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              heroTag: 'send',
              mini: true,
              onPressed: _sendText,
              child: const Icon(Icons.send),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              heroTag: 'voice',
              backgroundColor:
                  _listening ? Colors.red : Colors.deepPurple,
              onPressed: _toggleListening,
              child: Icon(
                _listening ? Icons.stop : Icons.mic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class GeminiLiveService {
  final String apiKey;
  final String model;

  GeminiLiveService({
    required this.apiKey,
    required this.model,
  });

  WebSocketChannel? _channel;
  StreamSubscription? _socketSubscription;

  Function(String text)? onText;
  Function(String status)? onStatus;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String error)? onError;

  bool _connected = false;

  Future<void> connect() async {
    if (_connected) return;

    try {
      onStatus?.call('Connecting...');

      final uri = Uri.parse(
        'wss://generativelanguage.googleapis.com/ws/'
        'google.ai.generativelanguage.v1beta.'
        'GenerativeService.BidiGenerateContent'
        '?key=${Uri.encodeQueryComponent(apiKey)}',
      );

      _channel = IOWebSocketChannel.connect(uri);

      await _channel!.ready;

      _connected = true;

      onConnected?.call();

      _sendSetup();

      _socketSubscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          onError?.call('WebSocket error: $error');
        },
        onDone: () {
          _connected = false;
          onDisconnected?.call();
        },
      );
    } catch (e) {
      _connected = false;
      onError?.call('Connection failed: $e');
    }
  }

  void _sendSetup() {
    final setup = {
      'setup': {
        'model': 'models/$model',
        'responseModalities': ['TEXT'],
        'systemInstruction': {
          'parts': [
            {
              'text':
                  '''
You are a helpful voice-first AI assistant.

Rules:
- Answer naturally and concisely.
- Understand Hindi, English and Hinglish.
- If the user asks for an action involving phone permissions,
  explain that Android permission is required.
- Never claim that you performed a phone action unless the
  application actually executed it.
'''
            }
          ],
        },
      }
    };

    _sendJson(setup);
  }

  Future<void> sendText(String text) async {
    if (!_connected) {
      await connect();
    }

    final message = {
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {
                'text': text,
              }
            ]
          }
        ],
        'turnComplete': true,
      }
    };

    _sendJson(message);
  }

  void _sendJson(Map<String, dynamic> message) {
    if (!_connected || _channel == null) return;

    _channel!.sink.add(
      jsonEncode(message),
    );
  }

  void _handleMessage(dynamic event) {
    try {
      final data = jsonDecode(event.toString());

      final serverContent = data['serverContent'];

      if (serverContent == null) return;

      final modelTurn = serverContent['modelTurn'];

      if (modelTurn == null) return;

      final parts = modelTurn['parts'];

      if (parts == null) return;

      for (final part in parts) {
        final text = part['text'];

        if (text is String && text.isNotEmpty) {
          onText?.call(text);
        }

        final inlineData = part['inlineData'];

        if (inlineData != null) {
          final mimeType =
              inlineData['mimeType']?.toString() ?? '';

          final base64Audio =
              inlineData['data']?.toString() ?? '';

          if (base64Audio.isNotEmpty) {
            _handleAudio(
              mimeType,
              base64Audio,
            );
          }
        }
      }
    } catch (e) {
      onError?.call('Invalid Gemini response: $e');
    }
  }

  void _handleAudio(
    String mimeType,
    String base64Audio,
  ) {
    // Gemini Live audio is returned as raw PCM.
    //
    // Production implementation:
    // 1. Decode Base64.
    // 2. Convert PCM16/24kHz to an audio stream.
    // 3. Feed it to an Android AudioTrack/Flutter audio player.
    //
    // This method is intentionally separated so that the audio
    // output implementation can be replaced independently.
  }

  Future<void> startMicrophone() async {
    /*
      Production microphone pipeline:

      Microphone
          ↓
      PCM 16-bit / 16kHz
          ↓
      Base64
          ↓
      realtimeInput.audio
          ↓
      Gemini Live API

      Example message:

      {
        "realtimeInput": {
          "audio": {
            "data": "...base64...",
            "mimeType": "audio/pcm;rate=16000"
          }
        }
      }

      Use the `record` package to capture PCM frames and send
      each frame through `_sendJson()`.
    */

    onStatus?.call('Microphone ready');
  }

  Future<void> stopMicrophone() async {
    onStatus?.call('Microphone stopped');
  }

  Future<void> disconnect() async {
    _connected = false;

    await _socketSubscription?.cancel();
    await _channel?.sink.close();

    _socketSubscription = null;
    _channel = null;

    onDisconnected?.call();
  }

  void dispose() {
    disconnect();
  }
}
