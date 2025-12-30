import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

// -----------------------------------------------------------------------------
// MAIN ENTRY POINT
// -----------------------------------------------------------------------------

void main() {
  // MacOS uchun maxsus config
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    // macos_ui configlari kerak bo'lsa shu yerda
  }
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
        onDone: () => setState(() => _isConnected = false),
        onError: (err) => setState(() => _isConnected = false),
      );
      setState(() => _isConnected = true);
    } catch (e) {
      // Retry logic could go here
      setState(() => _isConnected = false);
    }
  }

  void _onMessage(dynamic message) {
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
      } else if (action == 'toast') {
        // Show toast notifications logic here
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
      return material.MaterialApp(
        debugShowCheckedModeBanner: false,
        home: material.Scaffold(
          body: material.Center(
            child: material.Column(
              mainAxisAlignment: material.MainAxisAlignment.center,
              children: [
                const material.CircularProgressIndicator(),
                const material.SizedBox(height: 20),
                const material.Text("Python serverga ulanilmoqda..."),
                material.TextButton(
                  onPressed: _connect,
                  child: const material.Text("Qayta urunish"),
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
        : UniversalRenderer(
            spec: _uiTree!, onEvent: _sendEvent, themeMode: _currentTheme);

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
        return material.MaterialApp(
          title: _windowTitle,
          theme: material.ThemeData.light(useMaterial3: true),
          darkTheme: material.ThemeData.dark(useMaterial3: true),
          home: material.Scaffold(
            appBar: material.AppBar(title: material.Text(_windowTitle)),
            body: content,
          ),
        );

      case 'cupertino':
        return cupertino.CupertinoApp(
          title: _windowTitle,
          theme:
              const cupertino.CupertinoThemeData(brightness: Brightness.light),
          home: cupertino.CupertinoPageScaffold(
            navigationBar: cupertino.CupertinoNavigationBar(
              middle: material.Text(_windowTitle),
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
              title: material.Text(_windowTitle),
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
    // Error Boundary: Agar birorta widget buzilsa, butun app qulamasin
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

    // --- ANIMATSIYA VA STYLING WRAPPER ---
    // Har bir widgetni AnimatedContainer ichiga o'rash orqali
    // Python o'lcham/rangni o'zgartirganda avtomatik animatsiya bo'ladi.

    Widget child = _getRawWidget(context, type, id, props, childrenSpecs);

    // Agar maxsus "style" berilgan bo'lsa (padding, margin, opacity)
    if (props.containsKey('style')) {
      final style = props['style'];
      return material.AnimatedContainer(
        duration: Duration(milliseconds: style['anim_duration'] ?? 300),
        curve: _parseCurve(style['anim_curve']),
        padding: _parsePadding(style['padding']),
        margin: _parsePadding(style['margin']),
        width: style['width']?.toDouble(),
        height: style['height']?.toDouble(),
        alignment: _parseAlignment(style['alignment']),
        decoration: BoxDecoration(
          color: _parseColor(style['bg_color']),
          borderRadius:
              BorderRadius.circular((style['radius'] ?? 0).toDouble()),
          border: style['border_color'] != null
              ? Border.all(
                  color: _parseColor(style['border_color'])!,
                  width: (style['border_width'] ?? 1).toDouble())
              : null,
          boxShadow: style['shadow'] == true
              ? [
                  const BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 4))
                ]
              : null,
        ),
        child: child,
      );
    }

    return child;
  }

  Widget _getRawWidget(BuildContext context, String type, String id,
      Map<String, dynamic> props, List childrenSpecs) {
    // Bolalarini rekursiv render qilish
    List<Widget> children =
        childrenSpecs.map((c) => _buildWidget(context, c)).toList();

    switch (type) {
      // --- LAYOUT WIDGETS ---
      case 'column':
        return material.Column(
          mainAxisAlignment: _parseMainAxis(props['main_axis']),
          crossAxisAlignment: _parseCrossAxis(props['cross_axis']),
          mainAxisSize:
              props['main_size'] == 'min' ? MainAxisSize.min : MainAxisSize.max,
          children: children,
        );
      case 'row':
        return material.Row(
          mainAxisAlignment: _parseMainAxis(props['main_axis']),
          crossAxisAlignment: _parseCrossAxis(props['cross_axis']),
          mainAxisSize:
              props['main_size'] == 'min' ? MainAxisSize.min : MainAxisSize.max,
          children: children,
        );
      case 'stack':
        return material.Stack(
          alignment: _parseAlignment(props['alignment']) ?? Alignment.topLeft,
          children: children,
        );
      case 'listview':
        return material.ListView(
          padding: _parsePadding(props['padding']),
          children: children,
        );
      case 'expanded':
        return material.Expanded(
          flex: props['flex'] ?? 1,
          child: children.isNotEmpty ? children.first : const SizedBox(),
        );

      // --- BASIC WIDGETS ---
      case 'text':
        return material.Text(
          props['value'] ?? '',
          textAlign: _parseTextAlign(props['align']),
          style: material.TextStyle(
            fontSize: (props['size'] ?? 14).toDouble(),
            color: _parseColor(props['color']),
            fontWeight:
                props['bold'] == true ? FontWeight.bold : FontWeight.normal,
            fontStyle:
                props['italic'] == true ? FontStyle.italic : FontStyle.normal,
            fontFamily: props['font'], // Custom font support
          ),
        );

      case 'icon':
        return material.Icon(
          _parseIcon(props['icon_code']), // Icon name or code
          size: (props['size'] ?? 24).toDouble(),
          color: _parseColor(props['color']),
        );

      case 'image':
        return material.Image.network(
          props['src'] ?? '',
          width: props['width']?.toDouble(),
          height: props['height']?.toDouble(),
          fit: _parseBoxFit(props['fit']),
        );

      // --- INTERACTIVE WIDGETS (ADAPTIVE) ---
      case 'button':
        final text = props['text'] ?? 'Button';
        final onPressed =
            props['disabled'] == true ? null : () => onEvent(id, 'click');

        // Theme ga qarab o'zgaradigan button
        if (themeMode == 'fluent') {
          return props['primary'] == true
              ? fluent.FilledButton(onPressed: onPressed, child: Text(text))
              : fluent.Button(onPressed: onPressed, child: Text(text));
        } else if (themeMode == 'macos') {
          return macos.PushNativeWindowButton(
            // PushNativeWindowButton shunchaki misol, aslida PushButton ishlatiladi
            onPressed: onPressed, label: text,
            isSecondary: !(props['primary'] == true),
          );
          // Macos UI da oddiy button
          // return macos.PushButton(buttonSize: macos.ButtonSize.large, onPressed: onPressed, child: Text(text));
        } else if (themeMode == 'cupertino') {
          return cupertino.CupertinoButton(
            color: props['primary'] == true
                ? cupertino.CupertinoColors.activeBlue
                : null,
            onPressed: onPressed,
            child: Text(text),
          );
        } else {
          // Material
          return props['primary'] == true
              ? material.ElevatedButton(onPressed: onPressed, child: Text(text))
              : material.OutlinedButton(
                  onPressed: onPressed, child: Text(text));
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
          return material.TextField(
            decoration: material.InputDecoration(
              hintText: placeholder,
              border: const material.OutlineInputBorder(),
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
          return material.Switch(value: value, onChanged: onChanged);
        }

      case 'slider':
        final double value = (props['value'] ?? 0).toDouble();
        final double min = (props['min'] ?? 0).toDouble();
        final double max = (props['max'] ?? 100).toDouble();

        if (themeMode == 'fluent') {
          return fluent.Slider(
              value: value,
              min: min,
              max: max,
              onChanged: (v) => onEvent(id, 'change', v));
        } else {
          return material.Slider(
              value: value,
              min: min,
              max: max,
              onChanged: (v) => onEvent(id, 'change', v));
        }

      // Default fallback
      default:
        return material.Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border.all(color: Colors.red)),
          child: material.Text('Unknown widget: $type',
              style: const TextStyle(color: Colors.red)),
        );
    }
  }

  // --- PARSERS (Helper Functions) ---

  material.MainAxisAlignment _parseMainAxis(String? val) {
    switch (val) {
      case 'start':
        return material.MainAxisAlignment.start;
      case 'end':
        return material.MainAxisAlignment.end;
      case 'center':
        return material.MainAxisAlignment.center;
      case 'space_between':
        return material.MainAxisAlignment.spaceBetween;
      case 'space_around':
        return material.MainAxisAlignment.spaceAround;
      default:
        return material.MainAxisAlignment.start;
    }
  }

  material.CrossAxisAlignment _parseCrossAxis(String? val) {
    switch (val) {
      case 'start':
        return material.CrossAxisAlignment.start;
      case 'end':
        return material.CrossAxisAlignment.end;
      case 'center':
        return material.CrossAxisAlignment.center;
      case 'stretch':
        return material.CrossAxisAlignment.stretch;
      default:
        return material.CrossAxisAlignment.center;
    }
  }

  material.Alignment? _parseAlignment(String? val) {
    switch (val) {
      case 'center':
        return material.Alignment.center;
      case 'top_left':
        return material.Alignment.topLeft;
      case 'bottom_right':
        return material.Alignment.bottomRight;
      // ... boshqa alignmentlar
      default:
        return null;
    }
  }

  material.EdgeInsets _parsePadding(dynamic val) {
    if (val is int || val is double) {
      return material.EdgeInsets.all(val.toDouble());
    }
    if (val is List && val.length == 4) {
      // [left, top, right, bottom]
      return material.EdgeInsets.fromLTRB(val[0].toDouble(), val[1].toDouble(),
          val[2].toDouble(), val[3].toDouble());
    }
    // "10 20" string formati uchun parser yozsa bo'ladi
    return material.EdgeInsets.zero;
  }

  material.Color? _parseColor(String? hex) {
    if (hex == null) return null;
    try {
      hex = hex.replaceAll('#', '');
      if (hex.length == 6) hex = "FF$hex";
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return Colors.transparent;
    }
  }

  material.Curve _parseCurve(String? val) {
    switch (val) {
      case 'bounce':
        return material.Curves.bounceOut;
      case 'ease_in':
        return material.Curves.easeIn;
      case 'linear':
        return material.Curves.linear;
      default:
        return material.Curves.easeInOut;
    }
  }

  material.BoxFit _parseBoxFit(String? val) {
    switch (val) {
      case 'cover':
        return BoxFit.cover;
      case 'contain':
        return BoxFit.contain;
      default:
        return BoxFit.fill;
    }
  }

  TextAlign _parseTextAlign(String? val) {
    switch (val) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }

  IconData _parseIcon(String? name) {
    // Bu yerda kattaroq MAP qilish kerak. Hozircha misol uchun:
    switch (name) {
      case 'home':
        return material.Icons.home;
      case 'settings':
        return material.Icons.settings;
      case 'add':
        return material.Icons.add;
      case 'delete':
        return material.Icons.delete;
      case 'user':
        return material.Icons.person;
      // Cupertino icons uchun
      case 'c_home':
        return cupertino.CupertinoIcons.home;
      default:
        return material.Icons.help_outline;
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
    return const material.Center(child: material.CircularProgressIndicator());
  }
}

class ErrorBox extends StatelessWidget {
  final String error;
  final Map spec;
  const ErrorBox({super.key, required this.error, required this.spec});

  @override
  Widget build(BuildContext context) {
    return material.Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(8),
      color: Colors.red.shade100,
      child: material.Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const material.Icon(Icons.error, color: Colors.red),
          material.Text(error, style: const TextStyle(fontSize: 10)),
          material.Text("Widget Type: ${spec['type']}",
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
