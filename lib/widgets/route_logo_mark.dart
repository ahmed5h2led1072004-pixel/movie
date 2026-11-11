import 'package:flutter/material.dart';

class RouteLogoMark extends StatelessWidget {
  const RouteLogoMark({
    super.key,
    required this.size,
    required this.color,
    required this.background,
  });

  final double size;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _RouteMarkPainter(color: color, background: background),
    );
  }
}

class _RouteMarkPainter extends CustomPainter {
  const _RouteMarkPainter({required this.color, required this.background});

  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 112;
    canvas.save();
    canvas.scale(scale);

    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(const Offset(56, 56), 51, ringPaint);

    final mark = Path()
      ..moveTo(7, 18)
      ..cubicTo(7, 9, 14, 8, 22, 14)
      ..lineTo(79, 51)
      ..cubicTo(88, 57, 88, 64, 79, 70)
      ..lineTo(22, 107)
      ..cubicTo(14, 113, 7, 110, 7, 101)
      ..close()
      ..moveTo(27, 36)
      ..lineTo(56, 56)
      ..lineTo(27, 76)
      ..close()
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(mark, Paint()..color = color);

    final cutout = Path()
      ..moveTo(27, 36)
      ..lineTo(56, 56)
      ..lineTo(27, 76)
      ..close();
    canvas.drawPath(cutout, Paint()..color = background);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RouteMarkPainter oldDelegate) =>
      color != oldDelegate.color || background != oldDelegate.background;
}
