// =============================================================================
// FILE: lib/main.dart
// DESC: Universal Python-Driven UI Client (Windows/Mac/Linux/Web)
// STATUS: FULLY FIXED, MACOS_UI COMPATIBLE, ROBUST ERROR HANDLING
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';

// -----------------------------------------------------------------------------
// IMPORTS
// -----------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

// UI Libraries
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:flutter/cupertino.dart' as cupertino;

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

// -----------------------------------------------------------------------------
// ENTRY POINT
// -----------------------------------------------------------------------------

Future<void> main() async {
  // Crash reporting zone
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // macOS uchun maxsus config (faqat macOS da ishlaydi)
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        const config = macos.MacosWindowUtilsConfig();
        await config.apply();
      } catch (e) {
        if (kDebugMode) print("Macos Config Error: $e");
      }
    }

    runApp(const IpyUICore());
  }, (error, stack) {
    if (kDebugMode) {
      print("CRITICAL RUNTIME ERROR: $error");
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
  final String _wsUrl = 'ws://localhost:8080/ws';
  WebSocketChannel? _channel;
  
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

  void _connect() {
    if (!mounted) return;
    setState(() => _statusMessage = "Connecting to $_wsUrl...");

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      
      _channel!.stream.listen(
        (message) => _onMessage(message),
        onDone: () {
          if (mounted) setState(() { _isConnected = false; _statusMessage = "Disconnected."; });
        },
        onError: (error) {
          if (mounted) setState(() { _isConnected = false; _statusMessage = "Error: $error"; });
        },
      );

      setState(() { _isConnected = true; _statusMessage = "Connected!"; });
    } catch (e) {
      if (mounted) setState(() { _isConnected = false; _statusMessage = "Fatal Error: $e"; });
    }
  }

  void _onMessage(dynamic message) {
    if (!mounted) return;
    try {
      final Map<String, dynamic> data = jsonDecode(message);
      
      // 1. Update UI
      if (data['action'] == 'update_ui') {
        final payload = data['payload'];
        setState(() {
          if (payload['tree'] != null) _uiTree = payload['tree'];
          if (payload['theme'] != null) _currentTheme = payload['theme'];
          if (payload['title'] != null) _windowTitle = payload['title'];
        });
      }
      
      // 2. Show Dialog / Alert (Backend driven)
      if (data['action'] == 'dialog') {
        _showDialog(data['payload']);
      }

    } catch (e) {
      debugPrint("Protocol Error: $e");
    }
  }

  void _showDialog(Map<String, dynamic> payload) {
    // Custom dialog logic (Theme aware)
    final title = payload['title'] ?? 'Alert';
    final msg = payload['message'] ?? '';
    
    showDialog(
      context: context, 
      builder: (ctx) {
        if (_currentTheme == 'macos') {
          return macos.MacosAlertDialog(
            appIcon: const FlutterLogo(size: 32),
            title: Text(title),
            message: Text(msg),
            primaryButton: macos.PushButton(
              controlSize: macos.ControlSize.regular,
              child: const Text('OK'),
              onPressed: () => Navigator.pop(ctx),
            ),
          );
        } else {
          return AlertDialog(title: Text(title), content: Text(msg));
        }
      }
    );
  }

  void _sendEvent(String id, String type, [dynamic value]) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(jsonEncode({
          'action': 'event', 'id': id, 'type': type, 'value': value,
        }));
      } catch (e) { debugPrint("Send Error: $e"); }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConnected) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(_statusMessage),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: _connect, child: const Text("Reconnect"))
              ],
            ),
          ),
        ),
      );
    }

    if (_uiTree == null) {
      return _buildWrapper(child: const Center(child: CircularProgressIndicator()));
    }

    return _buildWrapper(
      child: UniversalRenderer(
        spec: _uiTree!,
        onEvent: _sendEvent,
        themeMode: _currentTheme,
      ),
    );
  }

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
              children: [macos.ContentArea(builder: (c, s) => child)],
            ),
          ),
        );
      case 'fluent':
        return fluent.FluentApp(
          title: _windowTitle,
          themeMode: fluent.ThemeMode.system,
          debugShowCheckedModeBanner: false,
          home: fluent.NavigationView(
            appBar: fluent.NavigationAppBar(
              title: Text(_windowTitle), automaticallyImplyLeading: false,
            ),
            content: fluent.ScaffoldPage(content: child),
          ),
        );
      case 'cupertino':
        return cupertino.CupertinoApp(
          title: _windowTitle,
          debugShowCheckedModeBanner: false,
          home: cupertino.CupertinoPageScaffold(
            navigationBar: cupertino.CupertinoNavigationBar(middle: Text(_windowTitle)),
            child: SafeArea(child: child),
          ),
        );
      default:
        return MaterialApp(
          title: _windowTitle,
          debugShowCheckedModeBanner: false,
          home: Scaffold(appBar: AppBar(title: Text(_windowTitle)), body: child),
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
    super.key, required this.spec, required this.onEvent, required this.themeMode,
  });

  @override
  Widget build(BuildContext context) {
    try {
      // 1. Raw Widget
      Widget child = _getRawWidget(context, spec);
      
      // 2. Styling (Animation, Padding, etc)
      if (spec['props'] != null && spec['props']['style'] != null) {
        child = _applyStyle(child, spec['props']['style']);
      }
      return child;
    } catch (e) {
      return ErrorBox(error: e.toString(), spec: spec);
    }
  }

  Widget _getRawWidget(BuildContext context, Map<String, dynamic> widgetSpec) {
    final String type = widgetSpec['type'] ?? 'unknown';
    final String id = widgetSpec['id'] ?? 'no_id';
    final Map<String, dynamic> props = widgetSpec['props'] ?? {};
    final List<dynamic> childrenSpecs = widgetSpec['children'] ?? [];

    // Helper to build children
    List<Widget> children = childrenSpecs.map((c) => 
      UniversalRenderer(spec: c, onEvent: onEvent, themeMode: themeMode)
    ).toList();

    switch (type) {
      // --- LAYOUTS ---
      case 'column':
        return Column(
          mainAxisAlignment: _parseMainAxis(props['main_axis']),
          crossAxisAlignment: _parseCrossAxis(props['cross_axis']),
          children: children,
        );
      case 'row':
        return Row(
          mainAxisAlignment: _parseMainAxis(props['main_axis']),
          crossAxisAlignment: _parseCrossAxis(props['cross_axis']),
          children: children,
        );
      case 'center':
        return Center(child: children.isNotEmpty ? children.first : null);
      case 'expanded':
        return Expanded(flex: props['flex'] ?? 1, child: children.isNotEmpty ? children.first : const SizedBox());

      // --- TEXT & ICONS ---
      case 'text':
        return Text(
          props['value'] ?? '',
          style: TextStyle(
            fontSize: (props['size'] ?? 14).toDouble(),
            color: _parseColor(props['color']),
            fontWeight: props['bold'] == true ? FontWeight.bold : FontWeight.normal,
            fontFamily: props['font'],
          ),
        );
      case 'icon':
         return Icon(
           _parseIcon(props['icon_code']),
           size: (props['size'] ?? 24).toDouble(),
           color: _parseColor(props['color']),
         );

      // --- BUTTONS (Fixed for MacosUI 2.0) ---
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
          // *** FIX: Use 'secondary' named parameter instead of 'isSecondary' ***
          // If the button is NOT primary, we set secondary to true.
          return macos.PushButton(
            controlSize: macos.ControlSize.large, // Replaces ButtonSize
            secondary: !isPrimary,                // Replaces isSecondary
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

      // --- INPUTS ---
      case 'textfield':
        final placeholder = props['placeholder'] ?? '';
        final obscure = props['obscure'] == true;
        
        if (themeMode == 'macos') {
          return macos.MacosTextField(
            placeholder: placeholder,
            obscureText: obscure,
            onChanged: (v) => onEvent(id, 'change', v),
            onSubmitted: (v) => onEvent(id, 'submit', v),
          );
        } else if (themeMode == 'fluent') {
           return fluent.TextBox(
            placeholder: placeholder,
            obscureText: obscure,
            onChanged: (v) => onEvent(id, 'change', v),
            onSubmitted: (v) => onEvent(id, 'submit', v),
          );
        }
        return TextField(decoration: InputDecoration(hintText: placeholder));

      case 'switch':
        final bool val = props['value'] ?? false;
        final handler = (bool v) => onEvent(id, 'change', v);
        
        if (themeMode == 'macos') {
           return macos.MacosSwitch(value: val, onChanged: handler);
        } else if (themeMode == 'fluent') {
           return fluent.ToggleSwitch(checked: val, onChanged: handler);
        }
        return Switch(value: val, onChanged: handler);

      // --- MACOS SPECIFIC / CUSTOM ---
      // Pythondan { "type": "macos_date_picker" } kelsa
      case 'macos_date_picker':
        return macos.MacosDatePicker(
          onDateChanged: (date) => onEvent(id, 'change', date.toIso8601String()),
        );

      case 'macos_indicator':
        // Progress
        if (props['indeterminate'] == true) {
          return const macos.ProgressCircle();
        }
        return macos.ProgressBar(value: (props['value'] ?? 0).toDouble());
        
      case 'macos_slider':
        return macos.MacosSlider(
          value: (props['value'] ?? 0.0).toDouble(),
          min: (props['min'] ?? 0.0).toDouble(),
          max: (props['max'] ?? 100.0).toDouble(),
          onChanged: (v) => onEvent(id, 'change', v),
        );

      default:
        // Agar tanilmagan widget kelsa
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(border: Border.all(color: Colors.orange)),
          child: Text('Unknown Widget: $type', style: const TextStyle(fontSize: 10, color: Colors.orange)),
        );
    }
  }

  Widget _applyStyle(Widget child, Map<String, dynamic> style) {
    // Universal Style parser
    return AnimatedContainer(
      duration: Duration(milliseconds: style['anim_duration'] ?? 300),
      curve: Curves.easeInOut,
      padding: _parsePadding(style['padding']),
      margin: _parsePadding(style['margin']),
      width: style['width']?.toDouble(),
      height: style['height']?.toDouble(),
      alignment: _parseAlignment(style['alignment']),
      decoration: BoxDecoration(
        color: _parseColor(style['bg_color']),
        borderRadius: BorderRadius.circular((style['radius'] ?? 0).toDouble()),
        border: style['border_color'] != null 
          ? Border.all(color: _parseColor(style['border_color'])!, width: (style['border_width'] ?? 1).toDouble())
          : null,
      ),
      child: child,
    );
  }

  // --- SAFE PARSERS ---

  MainAxisAlignment _parseMainAxis(String? val) {
    if (val == 'center') return MainAxisAlignment.center;
    if (val == 'end') return MainAxisAlignment.end;
    if (val == 'space_between') return MainAxisAlignment.spaceBetween;
    return MainAxisAlignment.start;
  }
  
  CrossAxisAlignment _parseCrossAxis(String? val) {
    if (val == 'center') return CrossAxisAlignment.center;
    if (val == 'end') return CrossAxisAlignment.end;
    if (val == 'stretch') return CrossAxisAlignment.stretch;
    return CrossAxisAlignment.center;
  }
  
  EdgeInsets _parsePadding(dynamic val) {
    try {
      if (val is int || val is double) return EdgeInsets.all(val.toDouble());
      if (val is List && val.length == 4) return EdgeInsets.fromLTRB(val[0], val[1], val[2], val[3]);
    } catch (_) {}
    return EdgeInsets.zero;
  }

  Color? _parseColor(String? hex) {
    if (hex == null) return null;
    try {
      return Color(int.parse(hex.replaceAll('#', ''), radix: 16) + 0xFF000000);
    } catch (_) { return null; }
  }
  
  Alignment? _parseAlignment(String? val) {
    if (val == 'center') return Alignment.center;
    if (val == 'top_left') return Alignment.topLeft;
    if (val == 'bottom_right') return Alignment.bottomRight;
    return null;
  }

  IconData _parseIcon(String? name) {
    switch(name) {
      case 'home': return Icons.home;
      case 'settings': return Icons.settings;
      case 'user': return Icons.person;
      case 'search': return Icons.search;
      case 'add': return Icons.add;
      default: return Icons.widgets;
    }
  }
}

class ErrorBox extends StatelessWidget {
  final String error;
  final Map spec;
  const ErrorBox({super.key, required this.error, required this.spec});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.red.shade100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error, color: Colors.red, size: 16),
          Text("Error: ${spec['type']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
          Text(error, style: const TextStyle(fontSize: 8), maxLines: 2),
        ],
      ),
    );
  }
}
