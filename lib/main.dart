import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
        scaffoldBackgroundColor: const Color(0xFF080808),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
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
  late final GeminiLiveService _gemini;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _connected = false;
  bool _listening = false;
  bool _thinking = false;
  String _status = 'Disconnected';
  final List<ChatMessage> _messages = [];

  static const String siriPhotoUrl =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d3/Siri_logo.svg/512px-Siri_logo.svg.png';

  @override
  void initState() {
    super.initState();

    _gemini = GeminiLiveService(
      apiKey: const String.fromEnvironment(
        'GEMINI_API_KEY',
        defaultValue: '',
      ),
      model: 'gemini-2.0-flash-exp',
    );

    _gemini.onText = (text) {
      if (!mounted) return;
      setState(() {
        _thinking = false;
        if (_messages.isNotEmpty &&
            _messages.last.role == MessageRole.assistant) {
          _messages[_messages.length - 1] = ChatMessage(
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
      _scrollToBottom();
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
        _listening = false;
        _thinking = false;
        _status = 'Disconnected';
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
    _controller.dispose();
    _scrollController.dispose();
    _gemini.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    const apiKey = String.fromEnvironment(
      'GEMINI_API_KEY',
      defaultValue: '',
    );

    if (apiKey.isEmpty) {
      _showMessage(
        'Gemini API key missing.\nGitHub Secret GEMINI_API_KEY check karo.',
      );
      return;
    }

    await _gemini.connect();
  }

  Future<bool> _requestMicrophone() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showMessage('Microphone permission required.');
      return false;
    }
    return true;
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (!_connected) {
      await _connect();
      if (!_connected) return;
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

    _controller.clear();
    _scrollToBottom();

    await _gemini.sendText(text);
  }

  Future<void> _toggleMicrophone() async {
    if (!_connected) {
      await _connect();
      if (!_connected) return;
    }

    final permission = await _requestMicrophone();
    if (!permission) return;

    if (_listening) {
      await _gemini.stopMicrophone();
      if (!mounted) return;
      setState(() {
        _listening = false;
      });
      return;
    }

    try {
      await _gemini.startMicrophone();
      if (!mounted) return;
      setState(() {
        _listening = true;
        _status = 'Listening...';
      });
    } catch (e) {
      _showMessage('Microphone error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            ClipOval(
              child: Image.network(
                siriPhotoUrl,
                width: 42,
                height: 42,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Colors.deepPurple,
                          Colors.purpleAccent,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.smart_toy,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Siri',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 21,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Connect',
            onPressed: _connected ? null : _connect,
            icon: Icon(
              _connected ? Icons.cloud_done : Icons.cloud_off,
            ),
          ),
          IconButton(
            tooltip: 'Microphone permission',
            onPressed: _requestMicrophone,
            icon: const Icon(
              Icons.mic_none,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatus(),
          Expanded(
            child: _messages.isEmpty
                ? _buildWelcome()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) {
                      return _buildMessage(_messages[index]);
                    },
                  ),
          ),
          if (_thinking)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
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
                  Text('Siri is thinking...'),
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
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
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
            const Row(
              children: [
                Icon(Icons.mic, size: 16),
                SizedBox(width: 5),
                Text(
                  'LISTENING',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurple,
                    Colors.purpleAccent,
                  ],
                ),
              ),
              padding: const EdgeInsets.all(4),
              child: ClipOval(
                child: Image.network(
                  siriPhotoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return const Icon(
                      Icons.smart_toy,
                      size: 70,
                      color: Colors.white,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Hello, I am Siri',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Talk to me using your microphone or type a message below.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 25),
            FilledButton.icon(
              onPressed: _toggleMicrophone,
              icon: const Icon(Icons.mic),
              label: const Text('Talk to Siri'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.role == MessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isUser ? Colors.deepPurple : Colors.white.withOpacity(.08),
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
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: InputDecoration(
                  hintText: 'Ask Siri anything...',
                  filled: true,
                  fillColor: Colors.white.withOpacity(.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
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
              heroTag: 'microphone',
              backgroundColor: _listening ? Colors.red : Colors.deepPurple,
              onPressed: _toggleMicrophone,
              child: Icon(_listening ? Icons.stop : Icons.mic),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CHAT MESSAGE
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
// GEMINI LIVE SERVICE
// ============================================================

class GeminiLiveService {
  final String apiKey;
  final String model;

  GeminiLiveService({
    required this.apiKey,
    required this.model,
  });

  WebSocketChannel? _channel;
  StreamSubscription? _socketSubscription;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _microphoneSubscription;

  bool _connected = false;
  bool _microphoneRunning = false;

  Function(String text)? onText;
  Function(String status)? onStatus;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String error)? onError;

  Future<void> connect() async {
    if (_connected) return;

    if (apiKey.isEmpty) {
      onError?.call('GEMINI_API_KEY is missing.');
      return;
    }

    try {
      onStatus?.call('Connecting to Gemini...');

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
        (data) {
          _handleResponse(data);
        },
        onError: (e) {
          onError?.call('WebSocket error: $e');
          _disconnect();
        },
        onDone: () {
          _disconnect();
        },
      );
    } catch (e) {
      onError?.call('Connection error: $e');
      _disconnect();
    }
  }

  void _sendSetup() {
    final setupData = {
      'setup': {
        'model': 'models/$model',
        'generationConfig': {
          'responseModalities': ['TEXT']
        }
      }
    };
    _channel?.sink.add(jsonEncode(setupData));
  }

  Future<void> sendText(String text) async {
    if (!_connected || _channel == null) return;

    final messageData = {
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text}
            ]
          }
        ],
        'turnComplete': true
      }
    };

    _channel!.sink.add(jsonEncode(messageData));
  }

  Future<void> startMicrophone() async {
    if (!_connected || _microphoneRunning) return;

    _recorder = AudioRecorder();

    final stream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _microphoneRunning = true;

    _microphoneSubscription = stream.listen((chunk) {
      if (!_connected || _channel == null) return;

      final base64Audio = base64Encode(chunk);
      final audioFrame = {
        'realtimeInput': {
          'mediaChunks': [
            {
              'mimeType': 'audio/pcm',
              'data': base64Audio
            }
          ]
        }
      };

      _channel!.sink.add(jsonEncode(audioFrame));
    });
  }

  Future<void> stopMicrophone() async {
    await _microphoneSubscription?.cancel();
    _microphoneSubscription = null;
    await _recorder?.stop();
    await _recorder?.dispose();
    _recorder = null;
    _microphoneRunning = false;
    onStatus?.call('Connected');
  }

  void _handleResponse(dynamic response) {
    try {
      final jsonResponse = jsonDecode(response.toString());

      if (jsonResponse.containsKey('serverContent')) {
        final serverContent = jsonResponse['serverContent'];
        if (serverContent.containsKey('modelTurn')) {
          final parts = serverContent['modelTurn']['parts'] as List?;
          if (parts != null) {
            for (var part in parts) {
              if (part is Map && part.containsKey('text')) {
                onText?.call(part['text']);
              }
            }
          }
        }
      }
    } catch (e) {
      onError?.call('Error parsing message: $e');
    }
  }

  void _disconnect() {
    _connected = false;
    _microphoneRunning = false;
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _microphoneSubscription?.cancel();
    _microphoneSubscription = null;
    _recorder?.dispose();
    _recorder = null;
    _channel?.sink.close();
    _channel = null;
    onDisconnected?.call();
  }

  void dispose() {
    _disconnect();
  }
}
