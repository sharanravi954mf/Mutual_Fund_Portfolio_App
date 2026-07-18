import 'dart:math';
import 'package:flutter/material.dart';

class RupeeParticle {
  double x;
  double y;
  double speed;
  double size;
  double opacity;
  double rotation;
  double rotationSpeed;

  RupeeParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.rotation,
    required this.rotationSpeed,
  });
}

class RupeeRainBackground extends StatefulWidget {
  final Widget child;

  const RupeeRainBackground({Key? key, required this.child}) : super(key: key);

  @override
  State<RupeeRainBackground> createState() => _RupeeRainBackgroundState();
}

class _RupeeRainBackgroundState extends State<RupeeRainBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<RupeeParticle> _particles = [];
  final Random _random = Random();
  final int _maxParticles = 30;

  @override
  void initState() {
    super.initState();

    // Loop animation to update particles positions
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(() {
        _updateParticles();
      })..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_particles.isEmpty) {
      _initParticles();
    }
  }

  void _initParticles() {
    final size = MediaQuery.of(context).size;
    for (int i = 0; i < _maxParticles; i++) {
      _particles.add(
        RupeeParticle(
          x: _random.nextDouble() * size.width,
          y: _random.nextDouble() * size.height,
          speed: 1.0 + _random.nextDouble() * 2.0,
          size: 14.0 + _random.nextDouble() * 22.0,
          opacity: 0.05 + _random.nextDouble() * 0.15, // Keep it subtle so it stays in background
          rotation: _random.nextDouble() * pi * 2,
          rotationSpeed: (_random.nextDouble() - 0.5) * 0.02,
        ),
      );
    }
  }

  void _updateParticles() {
    if (!mounted || _particles.isEmpty) return;
    final size = MediaQuery.of(context).size;

    setState(() {
      for (var particle in _particles) {
        particle.y += particle.speed;
        particle.rotation += particle.rotationSpeed;

        // Reset particle to top if it falls off screen
        if (particle.y > size.height) {
          particle.y = -particle.size;
          particle.x = _random.nextDouble() * size.width;
          particle.speed = 1.0 + _random.nextDouble() * 2.0;
          particle.size = 14.0 + _random.nextDouble() * 22.0;
          particle.opacity = 0.05 + _random.nextDouble() * 0.15;
          particle.rotation = _random.nextDouble() * pi * 2;
          particle.rotationSpeed = (_random.nextDouble() - 0.5) * 0.02;
        }
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
    return Stack(
      children: [
        // Dark background base color
        Container(
          color: const Color(0xFF0F0C20),
        ),
        // Custom paint layer drawing falling Rupees
        Positioned.fill(
          child: CustomPaint(
            painter: RupeeRainPainter(particles: _particles),
          ),
        ),
        // Child content on top
        widget.child,
      ],
    );
  }
}

class RupeeRainPainter extends CustomPainter {
  final List<RupeeParticle> particles;

  RupeeRainPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: "₹",
          style: TextStyle(
            fontSize: particle.size,
            color: const Color(0xFFF27121).withOpacity(particle.opacity), // Use themed orange accent for particles
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(particle.x, particle.y);
      canvas.rotate(particle.rotation);
      
      // Paint centered
      textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
