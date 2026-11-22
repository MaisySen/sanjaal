import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'refractive_backdrop.dart';

/// Source preparation only. Disabled in ordinary builds. Enabling this flag is
/// not release approval or evidence that native moving media was accepted.
const refractiveGlassPrepared = bool.fromEnvironment(
  'SANJAAL_REFRACTIVE_GLASS',
  defaultValue: false,
);

class RefractiveGlass extends StatefulWidget {
  const RefractiveGlass({
    super.key,
    required this.enabled,
    required this.radius,
    required this.fallback,
    required this.child,
  });
  final bool enabled;
  final double radius;
  final ui.ImageFilter fallback;
  final Widget child;
  @override
  State<RefractiveGlass> createState() => _RefractiveGlassState();
}

class _RefractiveGlassState extends State<RefractiveGlass> {
  static ui.FragmentProgram? _ready;
  static Future<ui.FragmentProgram>? _loading;
  ui.FragmentShader? shader;
  bool loading = false;
  int generation = 0;
  bool get eligible =>
      refractiveGlassPrepared &&
      widget.enabled &&
      ui.ImageFilter.isShaderFilterSupported &&
      !MediaQuery.highContrastOf(context) &&
      !MediaQuery.disableAnimationsOf(context);
  Future<void> load() async {
    if (loading || shader != null || !eligible) return;
    loading = true;
    final version = ++generation;
    try {
      final program =
          _ready ??
          await (_loading ??= ui.FragmentProgram.fromAsset(
            'shaders/glass_lens.frag',
          ));
      _ready = program;
      if (!mounted || version != generation || !eligible) return;
      final next = program.fragmentShader();
      setState(() => shader = next);
    } catch (_) {
      _loading = null;
    } finally {
      loading = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  @override
  void didUpdateWidget(RefractiveGlass old) {
    super.didUpdateWidget(old);
    load();
  }

  @override
  void dispose() {
    generation++;
    shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = shader;
    if (!eligible || value == null) {
      return BackdropFilter(filter: widget.fallback, child: widget.child);
    }
    return LensBackdrop(
      shader: value,
      fallback: widget.fallback,
      radius: widget.radius,
      strength: 2,
      child: widget.child,
    );
  }
}
