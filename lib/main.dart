// =============================================================================
// FILE: lib/main.dart
// DESC: Universal Python-Driven UI Client (Windows/Mac/Linux/Web)
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';

// -----------------------------------------------------------------------------
// IMPORTS
// -----------------------------------------------------------------------------
// Asosiy Flutter UI (Material) - Prefixsiz
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

// Platform Specific UIs - Prefix bilan
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:flutter/cupertino.dart' as cupertino;

// Networking
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

// -----------------------------------------------------------------------------
// ENTRY POINT
// -----------------------------------------------------------------------------

void main() {
  // Har qanday xatolikni ushlab qolish uchun guard
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const IpyUICore());
  }, (error, stack) {
    if (kDebugMode) {
      print("CRITICAL ERROR: $error");
      print(stack);
    }
  });
}

// -----------------------------------------------------------------------------
// APP CORE
// -----------------------------------------------------------------------------

class IpyUICore extends StatefulWidget {
  const IpyUICore({super.key});

  @override
  State<IpyUICore> createState() => _IpyUICoreState();
}

class _IpyUICoreState extends State<IpyUICore> {
  // CONFIGS
  final String _wsUrl = 'ws://localhost:8080/ws';
  WebSocketChannel? _channel;
  
  // STATE
  bool _isConnected = false;
  String _currentTheme = 'fluent'; // Options: fluent, macos, material, cupertino
  Map<String, dynamic>? _uiTree;
  String _windowTitle = "IpyUI App";
  String _statusMessage = "Connecting...";

  @override
  void initState() {
    super.initState();
    _connect();
  }

  /// Serverga ulanish
  void _connect() {
    setState(() {
      _statusMessage = "Connecting to $_wsUrl...";
    });

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      
      _channel!.stream.listen(
        (message) => _onMessage(message),
        onDone: () {
          if (mounted) {
            setState(() {
              _isConnected = false;
              _statusMessage = "Disconnected from server.";
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isConnected = false;
              _statusMessage = "Connection error: $error";
            });
          }
        },
      );

      // Agar stream error bermasa, ulandik deb hisoblaymiz (optimistic)
      setState(() {
        _isConnected = true;
        _statusMessage = "Connected!";
      });

    } catch (e) {
      setState(() {
        _isConnected = false;
        _statusMessage = "Fatal Connection Error: $e";
      });
    }
  }

  /// Serverdan kelgan xabarni ishlash
  void _onMessage(dynamic message) {
    if (!mounted) return;
    try {
      final Map<String, dynamic> data = jsonDecode(message);
      final String action = data['action'] ?? 'unknown';

      switch (action) {
        case 'update_ui':
          final payload = data['payload'];
          setState(() {
            if (payload['tree'] != null) _uiTree = payload['tree'];
            if (payload['theme'] != null) _currentTheme = payload['theme'];
            if (payload['title'] != null) _windowTitle = payload['title'];
          });
          break;
        
        case 'toast':
          // Kelajakda toast xabar chiqarish uchun
          debugPrint("Toast: ${data['message']}");
          break;
      }
    } catch (e) {
      debugPrint("Protocol Error: $e");
    }
  }

  /// Serverga event yuborish
  void _sendEvent(String id, String type, [dynamic value]) {
    if (_channel != null && _isConnected) {
      try {
        final jsonStr = jsonEncode({
          'action': 'event',
          'id': id,
          'type': type,
          'value': value,
        });
        _channel!.sink.add(jsonStr);
      } catch (e) {
        debugPrint("Send Error: $e");
      }
    }
  }

  @override
  void dispose() {
    _channel?.sink.close(status.goingAway);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Connection Screen
    if (!_isConnected) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.system,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(_statusMessage, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _connect,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Reconnect"),
                )
              ],
            ),
          ),
        ),
      );
    }

    // 2. Loading Screen
    if (_uiTree == null) {
      return _buildWrapper(
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // 3. Main UI Renderer
    final content = UniversalRenderer(
      spec: _uiTree!,
      onEvent: _sendEvent,
      themeMode: _currentTheme,
    );

    return _buildWrapper(child: content);
  }

  /// Har xil Theme lar uchun wrapper
  Widget _buildWrapper({required Widget child}) {
    switch (_currentTheme) {
      case 'macos':
        return macos.MacosApp(
          title: _windowTitle,
          theme: macos.MacosThemeData.light(),
          darkTheme: macos.MacosThemeData.dark(),
          debugShowCheckedModeBanner: false,
          home: macos.MacosWindow(
            child: macos.MacosScaffold(
              children: [
                macos.ContentArea(builder: (context, scrollController) => child),
              ],
            ),
          ),
        );

      case 'cupertino':
        return cupertino.CupertinoApp(
          title: _windowTitle,
          theme: const cupertino.CupertinoThemeData(brightness: Brightness.light),
          debugShowCheckedModeBanner: false,
          home: cupertino.CupertinoPageScaffold(
            navigationBar: cupertino.CupertinoNavigationBar(
              middle: Text(_windowTitle),
            ),
            child: SafeArea(child: child),
          ),
        );

      case 'fluent':
        return fluent.FluentApp(
          title: _windowTitle,
          themeMode: fluent.ThemeMode.system,
          debugShowCheckedModeBanner: false,
          home: fluent.NavigationView(
            appBar: fluent.NavigationAppBar(
              title: Text(_windowTitle),
              automaticallyImplyLeading: false,
            ),
            content: fluent.ScaffoldPage(content: child),
          ),
        );

      case 'material':
      default:
        return MaterialApp(
          title: _windowTitle,
          theme: ThemeData.light(useMaterial3: true),
          darkTheme: ThemeData.dark(useMaterial3: true),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            appBar: AppBar(title: Text(_windowTitle)),
            body: child,
          ),
        );
    }
  }
}

// -----------------------------------------------------------------------------
// UNIVERSAL RENDERER (THE ENGINE)
// -----------------------------------------------------------------------------

class UniversalRenderer extends StatelessWidget {
  final Map<String, dynamic> spec;
  final Function(String, String, [dynamic]) onEvent;
  final String themeMode;

  const UniversalRenderer({
    super.key,
    required this.spec,
    required this.onEvent,
    required this.themeMode,
  });

  @override
  Widget build(BuildContext context) {
    // TOP LEVEL TRY-CATCH: Butun app qulashini oldini oladi
    try {
      return _buildWidget(context, spec);
    } catch (e, stack) {
      return ErrorBox(error: e.toString(), stack: stack.toString(), spec: spec);
    }
  }

  Widget _buildWidget(BuildContext context, Map<String, dynamic> widgetSpec) {
    // Har bir widget uchun alohida himoya
    try {
      final String type = widgetSpec['type'] ?? 'unknown';
      final String id = widgetSpec['id'] ?? 'no_id';
      final Map<String, dynamic> props = widgetSpec['props'] ?? {};
      final List<dynamic> childrenSpecs = widgetSpec['children'] ?? [];

      // 1. Raw Widget yaratish
      Widget child = _getRawWidget(context, type, id, props, childrenSpecs);

      // 2. Agar 'style' berilgan bo'lsa, animatsiya va bezak qo'shish
      if (props.containsKey('style')) {
        child = _applyStyle(child, props['style']);
      }

      return child;
    } catch (e) {
      // Agar shu widget buzilsa, o'rniga qizil quti chiqaramiz
      return ErrorBox(error: e.toString(), spec: widgetSpec);
    }
  }

  Widget _applyStyle(Widget child, Map<String, dynamic> style) {
    return AnimatedContainer(
      duration: Duration(milliseconds: style['anim_duration'] ?? 300),
      curve: _parseCurve(style['anim_curve']),
      padding: _parsePadding(style['padding']),
      margin: _parsePadding(style['margin']),
      width: style['width']?.toDouble(),
      height: style['height']?.toDouble(),
      alignment: _parseAlignment(style['alignment']),
      decoration: BoxDecoration(
        color: _parseColor(style['bg_color']),
        borderRadius: BorderRadius.circular((style['radius'] ?? 0).toDouble()),
        border: style['border_color'] != null 
            ? Border.all(
                color: _parseColor(style['border_color'])!, 
                width: (style['border_width'] ?? 1).toDouble()
              )
            : null,
        boxShadow: style['shadow'] == true ? [
            const BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
        ] : null,
      ),
      child: child,
    );
  }

  Widget _getRawWidget(BuildContext context, String type, String id, Map<String, dynamic> props, List childrenSpecs) {
    // Bolalarini rekursiv yaratish
    List<Widget> children = childrenSpecs.map((c) => _buildWidget(context, c)).toList();

    switch (type) {
      // --- LAYOUTS ---
      case 'column':
        return Column(
          mainAxisAlignment: _parseMainAxis(props['main_axis']),
          crossAxisAlignment: _parseCrossAxis(props['cross_axis']),
          mainAxisSize: props['main_size'] == 'min' ? MainAxisSize.min : MainAxisSize.max,
          children: children,
        );
      
      case 'row':
        return Row(
          mainAxisAlignment: _parseMainAxis(props['main_axis']),
          crossAxisAlignment: _parseCrossAxis(props['cross_axis']),
          mainAxisSize: props['main_size'] == 'min' ? MainAxisSize.min : MainAxisSize.max,
          children: children,
        );
      
      case 'stack':
        return Stack(
          alignment: _parseAlignment(props['alignment']) ?? Alignment.topLeft,
          children: children,
        );

      case 'expanded':
        return Expanded(
          flex: props['flex'] ?? 1,
          child: children.isNotEmpty ? children.first : const SizedBox(),
        );
      
      case 'listview':
        return ListView(
          padding: _parsePadding(props['padding']),
          children: children,
        );

      case 'center':
        return Center(
          child: children.isNotEmpty ? children.first : null,
        );

      // --- BASICS ---
      case 'text':
        return Text(
          props['value'] ?? '',
          textAlign: _parseTextAlign(props['align']),
          style: TextStyle(
            fontSize: (props['size'] ?? 14).toDouble(),
            color: _parseColor(props['color']),
            fontWeight: props['bold'] == true ? FontWeight.bold : FontWeight.normal,
            fontStyle: props['italic'] == true ? FontStyle.italic : FontStyle.normal,
            fontFamily: props['font'],
          ),
        );

      case 'icon':
        return Icon(
          _parseIcon(props['icon_code']),
          size: (props['size'] ?? 24).toDouble(),
          color: _parseColor(props['color']),
        );

      // --- INPUTS & BUTTONS ---
      case 'button':
        final text = props['text'] ?? 'Button';
        final enabled = props['disabled'] != true;
        final VoidCallback? handler = enabled ? () => onEvent(id, 'click') : null;
        final bool isPrimary = props['primary'] == true;

        if (themeMode == 'fluent') {
          return isPrimary 
              ? fluent.FilledButton(onPressed: handler, child: Text(text))
              : fluent.Button(onPressed: handler, child: Text(text));
        } else if (themeMode == 'macos') {
          // --- FIX: ButtonSize -> ControlSize ga o'zgartirildi ---
          return macos.PushButton(
            controlSize: macos.ControlSize.large, // FIXED HERE
            isSecondary: !isPrimary,
            onPressed: handler,
            child: Text(text),
          );
        } else if (themeMode == 'cupertino') {
          return cupertino.CupertinoButton(
            color: isPrimary ? cupertino.CupertinoColors.activeBlue : null,
            onPressed: handler,
            child: Text(text),
          );
        } else {
          return isPrimary
              ? ElevatedButton(onPressed: handler, child: Text(text))
              : OutlinedButton(onPressed: handler, child: Text(text));
        }

      case 'textfield':
        final placeholder = props['placeholder'] ?? '';
        final obscure = props['obscure'] == true;
        
        if (themeMode == 'fluent') {
          return fluent.TextBox(
            placeholder: placeholder,
            obscureText: obscure,
            onChanged: (v) => onEvent(id, 'change', v),
            onSubmitted: (v) => onEvent(id, 'submit', v),
          );
        } else if (themeMode == 'macos') {
          return macos.MacosTextField(
            placeholder: placeholder,
            obscureText: obscure,
            onChanged: (v) => onEvent(id, 'change', v),
            onSubmitted: (v) => onEvent(id, 'submit', v),
          );
        } else {
          return TextField(
            decoration: InputDecoration(
              hintText: placeholder,
              border: const OutlineInputBorder(),
            ),
            obscureText: obscure,
            onChanged: (v) => onEvent(id, 'change', v),
            onSubmitted: (v) => onEvent(id, 'submit', v),
          );
        }

      case 'switch':
        final bool val = props['value'] ?? false;
        final handler = (bool v) => onEvent(id, 'change', v);

        if (themeMode == 'fluent') {
          return fluent.ToggleSwitch(checked: val, onChanged: handler);
        } else if (themeMode == 'macos') {
          return macos.MacosSwitch(value: val, onChanged: handler);
        } else {
          return Switch(value: val, onChanged: handler);
        }

      case 'slider':
        final double val = (props['value'] ?? 0).toDouble();
        final double min = (props['min'] ?? 0).toDouble();
        final double max = (props['max'] ?? 100).toDouble();
        final handler = (double v) => onEvent(id, 'change', v);

        if (themeMode == 'fluent') {
          return fluent.Slider(value: val, min: min, max: max, onChanged: handler);
        } else {
          return Slider(value: val, min: min, max: max, onChanged: handler);
        }

      default:
        // Noma'lum widget kelsa ham qulamaslik uchun
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(border: Border.all(color: Colors.orange)),
          child: Text('Unknown: $type', style: const TextStyle(fontSize: 10)),
        );
    }
  }

  // --- PARSERS (Safe Parsing) ---
  // Hech qachon null error bermasligi kerak

  MainAxisAlignment _parseMainAxis(String? val) {
    switch (val) {
      case 'start': return MainAxisAlignment.start;
      case 'end': return MainAxisAlignment.end;
      case 'center': return MainAxisAlignment.center;
      case 'space_between': return MainAxisAlignment.spaceBetween;
      case 'space_around': return MainAxisAlignment.spaceAround;
      default: return MainAxisAlignment.start;
    }
  }

  CrossAxisAlignment _parseCrossAxis(String? val) {
    switch (val) {
      case 'start': return CrossAxisAlignment.start;
      case 'end': return CrossAxisAlignment.end;
      case 'center': return CrossAxisAlignment.center;
      case 'stretch': return CrossAxisAlignment.stretch;
      default: return CrossAxisAlignment.center;
    }
  }

  Alignment? _parseAlignment(String? val) {
    switch (val) {
      case 'center': return Alignment.center;
      case 'top_left': return Alignment.topLeft;
      case 'top_right': return Alignment.topRight;
      case 'bottom_left': return Alignment.bottomLeft;
      case 'bottom_right': return Alignment.bottomRight;
      default: return null;
    }
  }

  EdgeInsets _parsePadding(dynamic val) {
    try {
      if (val is int || val is double) {
        return EdgeInsets.all(val.toDouble());
      }
      if (val is List && val.length == 4) {
        return EdgeInsets.fromLTRB(
          val[0].toDouble(), val[1].toDouble(), val[2].toDouble(), val[3].toDouble()
        );
      }
    } catch (_) {}
    return EdgeInsets.zero;
  }

  Color? _parseColor(String? hex) {
    if (hex == null) return null;
    try {
      hex = hex.replaceAll('#', '');
      if (hex.length == 6) hex = "FF$hex";
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return null;
    }
  }

  Curve _parseCurve(String? val) {
    switch(val) {
      case 'bounce': return Curves.bounceOut;
      case 'ease_in': return Curves.easeIn;
      case 'ease_out': return Curves.easeOut;
      case 'linear': return Curves.linear;
      default: return Curves.easeInOut;
    }
  }

  TextAlign _parseTextAlign(String? val) {
    switch(val) {
      case 'center': return TextAlign.center;
      case 'right': return TextAlign.right;
      case 'justify': return TextAlign.justify;
      default: return TextAlign.left;
    }
  }

  IconData _parseIcon(String? name) {
    // Kengaytirilgan Iconlar to'plami
    switch(name) {
      // Basic
      case 'home': return Icons.home;
      case 'settings': return Icons.settings;
      case 'user': return Icons.person;
      case 'search': return Icons.search;
      case 'menu': return Icons.menu;
      case 'close': return Icons.close;
      case 'add': return Icons.add;
      case 'delete': return Icons.delete;
      case 'edit': return Icons.edit;
      case 'check': return Icons.check;
      case 'info': return Icons.info;
      case 'warning': return Icons.warning;
      case 'error': return Icons.error;
      // Social
      case 'share': return Icons.share;
      case 'favorite': return Icons.favorite;
      // Media
      case 'play': return Icons.play_arrow;
      case 'pause': return Icons.pause;
      case 'stop': return Icons.stop;
      default: return Icons.widgets; // Fallback icon
    }
  }
}

// -----------------------------------------------------------------------------
// ERROR & LOADING WIDGETS
// -----------------------------------------------------------------------------

class ErrorBox extends StatelessWidget {
  final String error;
  final String? stack;
  final Map spec;

  const ErrorBox({super.key, required this.error, required this.spec, this.stack});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report, color: Colors.red, size: 16),
              const SizedBox(width: 4),
              Text("Render Error (${spec['type']})", 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(error, style: const TextStyle(fontSize: 10, color: Colors.black87), maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
