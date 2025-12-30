import 'dart:async';
import 'dart:convert';
import 'dart:math'; // Random va boshqalar uchun

// --- IMPORTS ---
// Asosiy Flutter kutubxonasi (Buni prefixsiz chaqiramiz)
import 'package:flutter/material.dart'; 
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // kIsWeb, debugMode uchun

// Boshqa UI tizimlari (Bularni prefix bilan chaqiramiz)
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:flutter/cupertino.dart' as cupertino;

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

// -----------------------------------------------------------------------------
// MAIN ENTRY POINT
// -----------------------------------------------------------------------------

void main() {
  // Desktop platformalarda window sozlamalari kerak bo'lsa shu yerga yoziladi
  runApp(const IpyUICore());
}

// -----------------------------------------------------------------------------
// CORE APP ORCHESTRATOR
// -----------------------------------------------------------------------------

class IpyUICore extends StatefulWidget {
  const IpyUICore({super.key});

  @override
  State<IpyUICore> createState() => _IpyUICoreState();
}

class _IpyUICoreState extends State<IpyUICore> {
  // Default connection configs
  final String _wsUrl = 'ws://localhost:8080/ws'; // Python server
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String _currentTheme = 'fluent'; // 'fluent', 'material', 'macos', 'cupertino'
  
  // UI Data Store
  Map<String, dynamic>? _uiTree;
  String _windowTitle = "IpyUI App";

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _channel!.stream.listen(
        (message) => _onMessage(message),
        onDone: () {
          if (mounted) setState(() => _isConnected = false);
        },
        onError: (err) {
          if (mounted) setState(() => _isConnected = false);
        },
      );
      if (mounted) setState(() => _isConnected = true);
    } catch (e) {
      if (mounted) setState(() => _isConnected = false);
    }
  }

  void _onMessage(dynamic message) {
    if (!mounted) return;
    try {
      final data = jsonDecode(message);
      final action = data['action'];
      
      if (action == 'update_ui') {
        final payload = data['payload'];
        setState(() {
          _uiTree = payload['tree'];
          if (payload['theme'] != null) _currentTheme = payload['theme'];
          if (payload['title'] != null) _windowTitle = payload['title'];
        });
      }
    } catch (e) {
      if (kDebugMode) print("Protocol Error: $e");
    }
  }

  void _sendEvent(String id, String type, [dynamic value]) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'action': 'event',
        'id': id,
        'type': type,
        'value': value,
      }));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Connection Error Screen
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
                const Text("Python serverga ulanilmoqda..."),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _connect,
                  child: const Text("Qayta urunish"),
                )
              ],
            ),
          ),
        ),
      );
    }

    // 2. Theme Switcher Logic
    Widget content = _uiTree == null
        ? const LoadingWidget()
        : UniversalRenderer(spec: _uiTree!, onEvent: _sendEvent, themeMode: _currentTheme);

    switch (_currentTheme) {
      case 'macos':
        return macos.MacosApp(
          title: _windowTitle,
          theme: macos.MacosThemeData.light(),
          darkTheme: macos.MacosThemeData.dark(),
          home: macos.MacosWindow(
            child: macos.MacosScaffold(
              children: [
                macos.ContentArea(builder: (ctx, scroll) => content),
              ],
            ),
          ),
        );
      
      case 'material':
        return MaterialApp(
          title: _windowTitle,
          theme: ThemeData.light(useMaterial3: true),
          darkTheme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            appBar: AppBar(title: Text(_windowTitle)),
            body: content,
          ),
        );

      case 'cupertino':
        return cupertino.CupertinoApp(
          title: _windowTitle,
          theme: const cupertino.CupertinoThemeData(brightness: Brightness.light),
          home: cupertino.CupertinoPageScaffold(
            navigationBar: cupertino.CupertinoNavigationBar(
              middle: Text(_windowTitle),
            ),
            child: SafeArea(child: content),
          ),
        );

      case 'fluent':
      default:
        return fluent.FluentApp(
          title: _windowTitle,
          themeMode: fluent.ThemeMode.system,
          home: fluent.NavigationView(
            appBar: fluent.NavigationAppBar(
              title: Text(_windowTitle),
              automaticallyImplyLeading: false,
            ),
            content: fluent.ScaffoldPage(
              content: content,
            ),
          ),
        );
    }
  }
}

// -----------------------------------------------------------------------------
// UNIVERSAL RENDERER (The Engine)
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
    try {
      return _buildWidget(context, spec);
    } catch (e) {
      return ErrorBox(error: e.toString(), spec: spec);
    }
  }

  Widget _buildWidget(BuildContext context, Map<String, dynamic> widgetSpec) {
    final String type = widgetSpec['type'] ?? 'unknown';
    final String id = widgetSpec['id'] ?? 'no_id';
    final Map<String, dynamic> props = widgetSpec['props'] ?? {};
    final List<dynamic> childrenSpecs = widgetSpec['children'] ?? [];

    Widget child = _getRawWidget(context, type, id, props, childrenSpecs);

    // Animatsiya va Style wrapper
    if (props.containsKey('style')) {
      final style = props['style'];
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
              ? Border.all(color: _parseColor(style['border_color'])!, width: (style['border_width'] ?? 1).toDouble())
              : null,
          boxShadow: style['shadow'] == true ? [
             const BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
          ] : null,
        ),
        child: child,
      );
    }

    return child;
  }

  Widget _getRawWidget(BuildContext context, String type, String id, Map<String, dynamic> props, List childrenSpecs) {
    List<Widget> children = childrenSpecs.map((c) => _buildWidget(context, c)).toList();

    switch (type) {
      // --- LAYOUT WIDGETS ---
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
      case 'listview':
        return ListView(
          padding: _parsePadding(props['padding']),
          children: children,
        );
      case 'expanded':
        return Expanded(
          flex: props['flex'] ?? 1,
          child: children.isNotEmpty ? children.first : const SizedBox(),
        );

      // --- BASIC WIDGETS ---
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

      case 'image':
        return Image.network(
          props['src'] ?? '',
          width: props['width']?.toDouble(),
          height: props['height']?.toDouble(),
          fit: _parseBoxFit(props['fit']),
        );

      // --- INTERACTIVE WIDGETS (ADAPTIVE) ---
      case 'button':
        final text = props['text'] ?? 'Button';
        final onPressed = props['disabled'] == true ? null : () => onEvent(id, 'click');
        
        if (themeMode == 'fluent') {
          return props['primary'] == true
              ? fluent.FilledButton(onPressed: onPressed, child: Text(text))
              : fluent.Button(onPressed: onPressed, child: Text(text));
        } else if (themeMode == 'macos') {
          return macos.PushButton(
            buttonSize: macos.ButtonSize.large,
            isSecondary: !(props['primary'] == true),
            onPressed: onPressed, 
            child: Text(text)
          );
        } else if (themeMode == 'cupertino') {
          return cupertino.CupertinoButton(
            color: props['primary'] == true ? cupertino.CupertinoColors.activeBlue : null,
            onPressed: onPressed,
            child: Text(text),
          );
        } else {
          return props['primary'] == true
              ? ElevatedButton(onPressed: onPressed, child: Text(text))
              : OutlinedButton(onPressed: onPressed, child: Text(text));
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
         final bool value = props['value'] ?? false;
         final onChanged = (bool v) => onEvent(id, 'change', v);
         
         if (themeMode == 'fluent') {
           return fluent.ToggleSwitch(checked: value, onChanged: onChanged);
         } else if (themeMode == 'macos') {
           return macos.MacosSwitch(value: value, onChanged: onChanged);
         } else if (themeMode == 'cupertino') {
           return cupertino.CupertinoSwitch(value: value, onChanged: onChanged);
         } else {
           return Switch(value: value, onChanged: onChanged);
         }

      case 'slider':
         final double value = (props['value'] ?? 0).toDouble();
         final double min = (props['min'] ?? 0).toDouble();
         final double max = (props['max'] ?? 100).toDouble();
         
         if (themeMode == 'fluent') {
           return fluent.Slider(value: value, min: min, max: max, onChanged: (v) => onEvent(id, 'change', v));
         } else {
           return Slider(value: value, min: min, max: max, onChanged: (v) => onEvent(id, 'change', v));
         }
      
      // Default fallback
      default:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border.all(color: Colors.red)),
          child: Text('Unknown widget: $type', style: const TextStyle(color: Colors.red)),
        );
    }
  }

  // --- PARSERS ---

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
      case 'bottom_right': return Alignment.bottomRight;
      default: return null;
    }
  }

  EdgeInsets _parsePadding(dynamic val) {
    if (val is int || val is double) {
      return EdgeInsets.all(val.toDouble());
    }
    if (val is List && val.length == 4) {
      return EdgeInsets.fromLTRB(
        val[0].toDouble(), val[1].toDouble(), val[2].toDouble(), val[3].toDouble()
      );
    }
    return EdgeInsets.zero;
  }

  Color? _parseColor(String? hex) {
    if (hex == null) return null;
    try {
      hex = hex.replaceAll('#', '');
      if (hex.length == 6) hex = "FF$hex";
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return Colors.transparent;
    }
  }

  Curve _parseCurve(String? val) {
    switch(val) {
      case 'bounce': return Curves.bounceOut;
      case 'ease_in': return Curves.easeIn;
      case 'linear': return Curves.linear;
      default: return Curves.easeInOut;
    }
  }

  BoxFit _parseBoxFit(String? val) {
     switch(val) {
       case 'cover': return BoxFit.cover;
       case 'contain': return BoxFit.contain;
       default: return BoxFit.fill;
     }
  }
  
  TextAlign _parseTextAlign(String? val) {
    switch(val) {
      case 'center': return TextAlign.center;
      case 'right': return TextAlign.right;
      default: return TextAlign.left;
    }
  }

  IconData _parseIcon(String? name) {
    switch(name) {
      case 'home': return Icons.home;
      case 'settings': return Icons.settings;
      case 'add': return Icons.add;
      case 'delete': return Icons.delete;
      case 'user': return Icons.person;
      case 'c_home': return cupertino.CupertinoIcons.home;
      default: return Icons.help_outline;
    }
  }
}

// -----------------------------------------------------------------------------
// UTILS
// -----------------------------------------------------------------------------

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class ErrorBox extends StatelessWidget {
  final String error;
  final Map spec;
  const ErrorBox({super.key, required this.error, required this.spec});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(8),
      color: Colors.red.shade100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error, color: Colors.red),
          Text(error, style: const TextStyle(fontSize: 10)),
          Text("Widget Type: ${spec['type']}", style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
