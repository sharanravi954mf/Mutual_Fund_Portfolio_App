import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class MoneyParticle {
  double x;
  double y;
  double speed;
  double size;
  double opacity;
  double rotation;
  double rotationSpeed;
  String symbol;
  Color color;

  MoneyParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.rotation,
    required this.rotationSpeed,
    required this.symbol,
    required this.color,
  });
}

class WealthOrb {
  double x;
  double y;
  double radius;
  double dx;
  double dy;
  double opacity;
  Color color;

  WealthOrb({
    required this.x,
    required this.y,
    required this.radius,
    required this.dx,
    required this.dy,
    required this.opacity,
    required this.color,
  });
}

class RupeeRainBackground extends StatefulWidget {
  final Widget child;

  const RupeeRainBackground({super.key, required this.child});

  @override
  State<RupeeRainBackground> createState() => _RupeeRainBackgroundState();
}

class _RupeeRainBackgroundState extends State<RupeeRainBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<MoneyParticle> _moneyParticles = [];
  final List<WealthOrb> _wealthOrbs = [];
  final Random _random = Random();
  final int _maxParticles = 35;
  final int _maxOrbs = 12;

  final List<String> _symbols = ['₹', '\$', '€', '£', '%', '📈', '✨', '💰'];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(() {
        _updateAnimation();
      })..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_moneyParticles.isEmpty) {
      _initMoneyParticles();
    }
    if (_wealthOrbs.isEmpty) {
      _initWealthOrbs();
    }
  }

  void _initMoneyParticles() {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final colors = isDark
        ? [const Color(0xFFC9B4BC), const Color(0xFF00E676), const Color(0xFFFFD54F), const Color(0xFF81D4FA)]
        : [const Color(0xFF7D5C69), const Color(0xFF059669), const Color(0xFFD97706), const Color(0xFF0284C7)];

    for (int i = 0; i < _maxParticles; i++) {
      _moneyParticles.add(
        MoneyParticle(
          x: _random.nextDouble() * size.width,
          y: _random.nextDouble() * size.height,
          speed: 0.8 + _random.nextDouble() * 2.0,
          size: 14.0 + _random.nextDouble() * 20.0,
          opacity: 0.08 + _random.nextDouble() * 0.18,
          rotation: _random.nextDouble() * pi * 2,
          rotationSpeed: (_random.nextDouble() - 0.5) * 0.02,
          symbol: _symbols[_random.nextInt(_symbols.length)],
          color: colors[_random.nextInt(colors.length)],
        ),
      );
    }
  }

  void _initWealthOrbs() {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final colors = isDark
        ? [const Color(0xFFC9B4BC), const Color(0xFF00C853), const Color(0xFFFFB300)]
        : [const Color(0xFF7D5C69), const Color(0xFF10B981), const Color(0xFFF59E0B)];

    for (int i = 0; i < _maxOrbs; i++) {
      _wealthOrbs.add(
        WealthOrb(
          x: _random.nextDouble() * size.width,
          y: _random.nextDouble() * size.height,
          radius: 30.0 + _random.nextDouble() * 70.0,
          dx: (_random.nextDouble() - 0.5) * 0.6,
          dy: (_random.nextDouble() - 0.5) * 0.6,
          opacity: 0.05 + _random.nextDouble() * 0.12,
          color: colors[_random.nextInt(colors.length)],
        ),
      );
    }
  }

  void _updateAnimation() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;

    setState(() {
      // Update falling currency particles
      for (var particle in _moneyParticles) {
        particle.y += particle.speed;
        particle.x += sin(particle.y * 0.01) * 0.5;
        particle.rotation += particle.rotationSpeed;

        if (particle.y > size.height) {
          particle.y = -particle.size;
          particle.x = _random.nextDouble() * size.width;
          particle.speed = 0.8 + _random.nextDouble() * 2.0;
          particle.size = 14.0 + _random.nextDouble() * 20.0;
          particle.symbol = _symbols[_random.nextInt(_symbols.length)];
        }
      }

      // Update floating wealth orbs
      for (var orb in _wealthOrbs) {
        orb.x += orb.dx;
        orb.y += orb.dy;

        if (orb.x < -orb.radius || orb.x > size.width + orb.radius) orb.dx = -orb.dx;
        if (orb.y < -orb.radius || orb.y > size.height + orb.radius) orb.dy = -orb.dy;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final option = themeProvider.wallpaperOption;

    if (option == MoneyWallpaperOption.disabled) {
      return widget.child;
    }

    return Stack(
      children: [
        // Live Money Wallpaper Canvas Layer
        Positioned.fill(
          child: CustomPaint(
            painter: MoneyWallpaperPainter(
              option: option,
              particles: _moneyParticles,
              orbs: _wealthOrbs,
              animValue: _controller.value,
            ),
          ),
        ),
        // Child Content (Dashboard / View UI)
        widget.child,
      ],
    );
  }
}

class MoneyWallpaperPainter extends CustomPainter {
  final MoneyWallpaperOption option;
  final List<MoneyParticle> particles;
  final List<WealthOrb> orbs;
  final double animValue;

  MoneyWallpaperPainter({
    required this.option,
    required this.particles,
    required this.orbs,
    required this.animValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (option == MoneyWallpaperOption.rupeeRain) {
      _paintRupeeRain(canvas, size);
    } else if (option == MoneyWallpaperOption.goldenWealth) {
      _paintGoldenWealth(canvas, size);
    }
  }

  void _paintRupeeRain(Canvas canvas, Size size) {
    for (var particle in particles) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: particle.symbol,
          style: TextStyle(
            fontSize: particle.size,
            color: particle.color.withValues(alpha: particle.opacity),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(particle.x, particle.y);
      canvas.rotate(particle.rotation);
      textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
      canvas.restore();
    }
  }

  void _paintGoldenWealth(Canvas canvas, Size size) {
    // 1. Draw glowing ambient wealth orbs
    for (var orb in orbs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            orb.color.withValues(alpha: orb.opacity),
            orb.color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(orb.x, orb.y), radius: orb.radius));

      canvas.drawCircle(Offset(orb.x, orb.y), orb.radius, paint);
    }

    // 2. Draw subtle wave curve representing financial growth
    final path = Path();
    final waveY = size.height * 0.75;
    path.moveTo(0, waveY);

    for (double x = 0; x <= size.width; x += 20) {
      final y = waveY + sin((x / size.width * 2 * pi) + (animValue * 2 * pi)) * 25.0;
      path.lineTo(x, y);
    }

    final wavePaint = Paint()
      ..color = const Color(0xFFC9B4BC).withValues(alpha: 0.12)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, wavePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
