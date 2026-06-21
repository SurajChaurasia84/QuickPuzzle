import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const QuickPuzzleApp());
}

class QuickPuzzleApp extends StatelessWidget {
  const QuickPuzzleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickPuzzle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.amberAccent,
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// Jigsaw side contour type
enum JigsawEdgeType {
  flat,
  tab,    // points outward (outside piece bounds)
  blank,  // points inward (inside piece bounds)
}

// Configuration of the 4 edges of a piece
class JigsawPieceDesign {
  final JigsawEdgeType top;
  final JigsawEdgeType right;
  final JigsawEdgeType bottom;
  final JigsawEdgeType left;

  const JigsawPieceDesign({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });
}

// Game model for each individual piece
class JigsawPieceModel {
  final int row;
  final int col;
  final JigsawPieceDesign design;
  Offset currentPosition;
  bool isSnapped;

  JigsawPieceModel({
    required this.row,
    required this.col,
    required this.design,
    required this.currentPosition,
    this.isSnapped = false,
  });
}

class JigsawGameScreen extends StatefulWidget {
  const JigsawGameScreen({super.key});

  @override
  State<JigsawGameScreen> createState() => _JigsawGameScreenState();
}

class _JigsawGameScreenState extends State<JigsawGameScreen> {
  // Grid size
  int _rows = 3;
  int _cols = 3;

  // Game stats
  int _moves = 0;
  int _secondsElapsed = 0;
  Timer? _timer;
  bool _showHint = false;
  bool _hasWon = false;

  // Layout metrics
  double _screenWidth = 0.0;
  double _screenHeight = 0.0;
  double _boardSize = 0.0;
  double _boardLeft = 0.0;
  double _boardTop = 0.0;
  double _trayTop = 0.0;
  double _trayHeight = 0.0;

  // Active pieces
  List<JigsawPieceModel> _pieces = [];
  int? _activeDraggingIndex;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Starts/resets the game timer
  void _startTimer() {
    _timer?.cancel();
    _secondsElapsed = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && !_hasWon) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });
  }

  // Generates jigsaw pieces with complementary fitting edges
  void _generateAndShufflePieces() {
    final vEdges = List.generate(
      _rows,
      (_) => List.generate(_cols - 1, (_) => math.Random().nextBool() ? JigsawEdgeType.tab : JigsawEdgeType.blank),
    );

    final hEdges = List.generate(
      _rows - 1,
      (_) => List.generate(_cols, (_) => math.Random().nextBool() ? JigsawEdgeType.tab : JigsawEdgeType.blank),
    );

    final List<JigsawPieceModel> generated = [];

    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        final JigsawEdgeType top = (r == 0)
            ? JigsawEdgeType.flat
            : (hEdges[r - 1][c] == JigsawEdgeType.tab ? JigsawEdgeType.blank : JigsawEdgeType.tab);

        final JigsawEdgeType bottom = (r == _rows - 1) ? JigsawEdgeType.flat : hEdges[r][c];

        final JigsawEdgeType left = (c == 0)
            ? JigsawEdgeType.flat
            : (vEdges[r][c - 1] == JigsawEdgeType.tab ? JigsawEdgeType.blank : JigsawEdgeType.tab);

        final JigsawEdgeType right = (c == _cols - 1) ? JigsawEdgeType.flat : vEdges[r][c];

        generated.add(JigsawPieceModel(
          row: r,
          col: c,
          design: JigsawPieceDesign(top: top, right: right, bottom: bottom, left: left),
          currentPosition: Offset.zero,
        ));
      }
    }

    _pieces = generated;
    _organizeTrayPieces();
  }

  // Arranges all unsnapped pieces in neat grid slots inside the bottom tray
  void _organizeTrayPieces() {
    final trayWidth = _screenWidth - 32.0;
    final trayLeft = 16.0;

    final unsnapped = _pieces.where((p) => !p.isSnapped).toList();
    final count = unsnapped.length;
    if (count == 0) return;

    // Determine grid columns inside tray based on total pieces
    int cols = 4;
    if (count > 4) cols = 5;
    if (count > 10) cols = 6;

    int rows = (count / cols).ceil();
    double slotWidth = trayWidth / cols;
    double slotHeight = _trayHeight / math.max(rows, 1);

    final w = _boardSize / _cols;
    final h = _boardSize / _rows;
    final pw = w * 1.4;
    final ph = h * 1.4;

    // Shuffle slot assignments so they aren't arranged in visual order
    final indices = List<int>.generate(count, (i) => i)..shuffle();

    setState(() {
      for (int i = 0; i < count; i++) {
        final idx = indices[i];
        final piece = unsnapped[idx];

        final gridRow = i ~/ cols;
        final gridCol = i % cols;

        final posX = trayLeft + gridCol * slotWidth + (slotWidth - pw) / 2;
        final posY = _trayTop + gridRow * slotHeight + (slotHeight - ph) / 2;

        piece.currentPosition = Offset(posX, posY);
      }
    });
  }

  // Checks if a dropped piece is near its correct board coordinates to snap it
  void _checkSnap(int index) {
    final piece = _pieces[index];
    final w = _boardSize / _cols;
    final h = _boardSize / _rows;

    final targetLeft = _boardLeft + piece.col * w - 0.20 * w;
    final targetTop = _boardTop + piece.row * h - 0.20 * h;

    final dist = (piece.currentPosition - Offset(targetLeft, targetTop)).distance;

    setState(() {
      _moves++;
      // Snap tolerance of 22 pixels
      if (dist < 22.0) {
        piece.currentPosition = Offset(targetLeft, targetTop);
        piece.isSnapped = true;
        HapticFeedback.mediumImpact();

        // Check victory
        if (_pieces.every((p) => p.isSnapped)) {
          _hasWon = true;
          _timer?.cancel();
        }
      }
      _activeDraggingIndex = null;
    });
  }

  // Resets the puzzle layout completely
  void _resetPuzzle() {
    setState(() {
      _hasWon = false;
      _generateAndShufflePieces();
      _startTimer();
      _moves = 0;
    });
  }

  // Handles difficulty toggling
  void _setDifficulty(int gridDimension) {
    setState(() {
      _rows = gridDimension;
      _cols = gridDimension;
      _resetPuzzle();
    });
  }

  // Formats the elapsed seconds into mm:ss format
  String _formatTime(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _screenWidth = constraints.maxWidth;
              _screenHeight = constraints.maxHeight;

              // Top HUD and Bottom Tray space allocation
              final availableHeight = _screenHeight - 120.0 - 150.0;
              _boardSize = math.min(_screenWidth * 0.85, math.min(availableHeight, 320.0));
              _boardLeft = (_screenWidth - _boardSize) / 2;
              _boardTop = 100.0 + (availableHeight - _boardSize) / 2;

              _trayTop = _screenHeight - 145.0;
              _trayHeight = 120.0;

              // Generate pieces once we have dynamic screen sizes
              if (_pieces.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _pieces.isEmpty) {
                    _generateAndShufflePieces();
                    _startTimer();
                  }
                });
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. HUD Top Dashboard
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: _buildHeaderHUD(),
                  ),

                  // 2. Main Game Board Target
                  Positioned(
                    left: _boardLeft,
                    top: _boardTop,
                    child: _buildGameBoard(),
                  ),

                  // 3. Bottom Tray visual card
                  Positioned(
                    left: 16,
                    top: _trayTop - 8,
                    right: 16,
                    height: _trayHeight + 16,
                    child: _buildTrayBackground(),
                  ),

                  // 4. Render snapped pieces first (bottom of stack)
                  ..._buildPuzzlePieces(snappedOnly: true),

                  // 5. Render unsnapped pieces (top of stack)
                  ..._buildPuzzlePieces(snappedOnly: false),

                  // 6. Victory Overlay dialog
                  if (_hasWon) _buildVictoryOverlay(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // Renders the transparent HUD control and status card
  Widget _buildHeaderHUD() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Time & Moves
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TIME: ${_formatTime(_secondsElapsed)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: Colors.cyanAccent,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'MOVES: $_moves',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ],
          ),

          // Difficulty Selector Button Group
          Row(
            children: [
              _buildDiffButton('2x2', 2),
              const SizedBox(width: 4),
              _buildDiffButton('3x3', 3),
              const SizedBox(width: 4),
              _buildDiffButton('4x4', 4),
            ],
          ),

          // Action buttons
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _showHint ? Icons.visibility : Icons.visibility_off,
                  color: _showHint ? Colors.amberAccent : Colors.white70,
                ),
                tooltip: 'Toggle Hint Image',
                onPressed: () {
                  setState(() {
                    _showHint = !_showHint;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
                tooltip: 'Reset Puzzle',
                onPressed: _resetPuzzle,
              ),
            ],
          )
        ],
      ),
    );
  }

  // Individual difficulty selector button
  Widget _buildDiffButton(String text, int size) {
    final isActive = (_rows == size);
    return InkWell(
      onTap: () => _setDifficulty(size),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.cyanAccent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.cyanAccent : Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.cyanAccent : Colors.white70,
          ),
        ),
      ),
    );
  }

  // Renders the board backdrop showing layout hints
  Widget _buildGameBoard() {
    return Container(
      width: _boardSize,
      height: _boardSize,
      decoration: BoxDecoration(
        color: const Color(0xFF020617).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.01),
            blurRadius: 20,
            spreadRadius: 2,
          )
        ],
      ),
      child: Stack(
        children: [
          // Background Hint Image (Toggleable)
          if (_showHint)
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Opacity(
                opacity: 0.20,
                child: Image.asset(
                  'assets/puzzle.png',
                  width: _boardSize,
                  height: _boardSize,
                  fit: BoxFit.fill,
                ),
              ),
            ),

          // Faint inner grid borders
          CustomPaint(
            size: Size(_boardSize, _boardSize),
            painter: BoardGridPainter(rows: _rows, cols: _cols),
          ),
        ],
      ),
    );
  }

  // Background visual container for the bottom tray
  Widget _buildTrayBackground() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: Stack(
        children: [
          // Tray Label
          Positioned(
            top: 8,
            left: 16,
            child: Text(
              'TRAY / DRAWER',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: Colors.white.withOpacity(0.3),
              ),
            ),
          ),

          // Tray Clean Up Helper Button
          Positioned(
            top: 2,
            right: 4,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.auto_awesome_motion, size: 12, color: Colors.amberAccent),
              label: const Text(
                'ORGANIZE',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amberAccent),
              ),
              onPressed: _organizeTrayPieces,
            ),
          ),
        ],
      ),
    );
  }

  // Dynamic stack of Jigsaw Pieces
  List<Widget> _buildPuzzlePieces({required bool snappedOnly}) {
    final w = _boardSize / _cols;
    final h = _boardSize / _rows;
    final pw = w * 1.4;
    final ph = h * 1.4;

    final List<Widget> list = [];

    for (int i = 0; i < _pieces.length; i++) {
      final piece = _pieces[i];
      if (piece.isSnapped != snappedOnly) continue;

      list.add(
        Positioned(
          left: piece.currentPosition.dx,
          top: piece.currentPosition.dy,
          child: GestureDetector(
            onPanStart: (details) {
              if (piece.isSnapped) return;
              setState(() {
                _activeDraggingIndex = i;
              });
            },
            onPanUpdate: (details) {
              if (piece.isSnapped) return;
              setState(() {
                piece.currentPosition += details.delta;
              });
            },
            onPanEnd: (details) {
              if (piece.isSnapped) return;
              _checkSnap(i);
            },
            child: SizedBox(
              width: pw,
              height: ph,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. Drop shadow layer
                  CustomPaint(
                    size: Size(pw, ph),
                    painter: JigsawPieceShadowPainter(
                      design: piece.design,
                      elevation: piece.isSnapped
                          ? 0.0
                          : (_activeDraggingIndex == i ? 10.0 : 4.0),
                    ),
                  ),

                  // 2. Clipped puzzle image slice
                  ClipPath(
                    clipper: JigsawPieceClipper(piece.design),
                    child: Stack(
                      children: [
                        Positioned(
                          left: -piece.col * w + 0.20 * w,
                          top: -piece.row * h + 0.20 * h,
                          child: Image.asset(
                            'assets/puzzle.png',
                            width: _boardSize,
                            height: _boardSize,
                            fit: BoxFit.fill,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. Glowing border/frame overlay on top of image
                  CustomPaint(
                    size: Size(pw, ph),
                    painter: JigsawPieceBorderPainter(
                      design: piece.design,
                      color: piece.isSnapped
                          ? Colors.white.withOpacity(0.08)
                          : (_activeDraggingIndex == i ? Colors.cyanAccent : Colors.white60),
                      strokeWidth: piece.isSnapped ? 1.0 : 2.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return list;
  }

  // Blur overlay showing congratulations dialog when user solves the puzzle
  Widget _buildVictoryOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withOpacity(0.9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.15),
                  blurRadius: 30,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.emoji_events,
                  color: Colors.amberAccent,
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'VICTORY!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    color: Colors.cyanAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Congratulations! You assembled the puzzle successfully.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),
                // Statistics
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatCard('TIME', _formatTime(_secondsElapsed)),
                    _buildStatCard('MOVES', '$_moves'),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _resetPuzzle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  icon: const Icon(Icons.replay),
                  label: const Text('PLAY AGAIN'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Small metrics display inside the victory modal
  Widget _buildStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.4),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Clipper that defines the jigsaw edge shapes
class JigsawPieceClipper extends CustomClipper<Path> {
  final JigsawPieceDesign design;

  JigsawPieceClipper(this.design);

  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width / 1.4;
    final h = size.height / 1.4;

    final ox = w * 0.20;
    final oy = h * 0.20;

    final pTL = Offset(ox, oy);
    final pTR = Offset(ox + w, oy);
    final pBR = Offset(ox + w, oy + h);
    final pBL = Offset(ox, oy + h);

    path.moveTo(pTL.dx, pTL.dy);

    _drawJigsawEdge(path, pTL, pTR, design.top);
    _drawJigsawEdge(path, pTR, pBR, design.right);
    _drawJigsawEdge(path, pBR, pBL, design.bottom);
    _drawJigsawEdge(path, pBL, pTL, design.left);

    path.close();
    return path;
  }

  void _drawJigsawEdge(Path path, Offset p1, Offset p2, JigsawEdgeType type) {
    if (type == JigsawEdgeType.flat) {
      path.lineTo(p2.dx, p2.dy);
      return;
    }

    final v = p2 - p1;
    final l = v.distance;
    final t = v / l;
    final n = Offset(-t.dy, t.dx); // Perpendicular vector pointing inward

    final sign = (type == JigsawEdgeType.tab) ? -1.0 : 1.0;

    // Segment points
    final pA = p1 + t * (l * 0.35);
    final pB = p1 + t * (l * 0.65);

    // Curve controls to create the bulb head
    final c1 = p1 + t * (l * 0.38) + n * (l * 0.05 * sign);
    final c2 = p1 + t * (l * 0.32) + n * (l * 0.18 * sign);
    final pC = p1 + t * (l * 0.50) + n * (l * 0.20 * sign);
    final c3 = p1 + t * (l * 0.68) + n * (l * 0.18 * sign);
    final c4 = p1 + t * (l * 0.62) + n * (l * 0.05 * sign);

    path.lineTo(pA.dx, pA.dy);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, pC.dx, pC.dy);
    path.cubicTo(c3.dx, c3.dy, c4.dx, c4.dy, pB.dx, pB.dy);
    path.lineTo(p2.dx, p2.dy);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => true;
}

// Custom Painter to draw the outer border outline of a piece
class JigsawPieceBorderPainter extends CustomPainter {
  final JigsawPieceDesign design;
  final Color color;
  final double strokeWidth;

  JigsawPieceBorderPainter({
    required this.design,
    required this.color,
    this.strokeWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final w = size.width / 1.4;
    final h = size.height / 1.4;

    final ox = w * 0.20;
    final oy = h * 0.20;

    final pTL = Offset(ox, oy);
    final pTR = Offset(ox + w, oy);
    final pBR = Offset(ox + w, oy + h);
    final pBL = Offset(ox, oy + h);

    path.moveTo(pTL.dx, pTL.dy);
    _drawJigsawEdge(path, pTL, pTR, design.top);
    _drawJigsawEdge(path, pTR, pBR, design.right);
    _drawJigsawEdge(path, pBR, pBL, design.bottom);
    _drawJigsawEdge(path, pBL, pTL, design.left);
    path.close();

    canvas.drawPath(path, paint);
  }

  void _drawJigsawEdge(Path path, Offset p1, Offset p2, JigsawEdgeType type) {
    if (type == JigsawEdgeType.flat) {
      path.lineTo(p2.dx, p2.dy);
      return;
    }

    final v = p2 - p1;
    final l = v.distance;
    final t = v / l;
    final n = Offset(-t.dy, t.dx);

    final sign = (type == JigsawEdgeType.tab) ? -1.0 : 1.0;

    final pA = p1 + t * (l * 0.35);
    final pB = p1 + t * (l * 0.65);

    final c1 = p1 + t * (l * 0.38) + n * (l * 0.05 * sign);
    final c2 = p1 + t * (l * 0.32) + n * (l * 0.18 * sign);
    final pC = p1 + t * (l * 0.50) + n * (l * 0.20 * sign);
    final c3 = p1 + t * (l * 0.68) + n * (l * 0.18 * sign);
    final c4 = p1 + t * (l * 0.62) + n * (l * 0.05 * sign);

    path.lineTo(pA.dx, pA.dy);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, pC.dx, pC.dy);
    path.cubicTo(c3.dx, c3.dy, c4.dx, c4.dy, pB.dx, pB.dy);
    path.lineTo(p2.dx, p2.dy);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Custom Painter to draw a drop shadow behind a piece
class JigsawPieceShadowPainter extends CustomPainter {
  final JigsawPieceDesign design;
  final double elevation;

  JigsawPieceShadowPainter({
    required this.design,
    required this.elevation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (elevation <= 0) return;

    final path = Path();
    final w = size.width / 1.4;
    final h = size.height / 1.4;

    final ox = w * 0.20;
    final oy = h * 0.20;

    final pTL = Offset(ox, oy);
    final pTR = Offset(ox + w, oy);
    final pBR = Offset(ox + w, oy + h);
    final pBL = Offset(ox, oy + h);

    path.moveTo(pTL.dx, pTL.dy);
    _drawJigsawEdge(path, pTL, pTR, design.top);
    _drawJigsawEdge(path, pTR, pBR, design.right);
    _drawJigsawEdge(path, pBR, pBL, design.bottom);
    _drawJigsawEdge(path, pBL, pTL, design.left);
    path.close();

    canvas.drawShadow(path, Colors.black, elevation, true);
  }

  void _drawJigsawEdge(Path path, Offset p1, Offset p2, JigsawEdgeType type) {
    if (type == JigsawEdgeType.flat) {
      path.lineTo(p2.dx, p2.dy);
      return;
    }

    final v = p2 - p1;
    final l = v.distance;
    final t = v / l;
    final n = Offset(-t.dy, t.dx);

    final sign = (type == JigsawEdgeType.tab) ? -1.0 : 1.0;

    final pA = p1 + t * (l * 0.35);
    final pB = p1 + t * (l * 0.65);

    final c1 = p1 + t * (l * 0.38) + n * (l * 0.05 * sign);
    final c2 = p1 + t * (l * 0.32) + n * (l * 0.18 * sign);
    final pC = p1 + t * (l * 0.50) + n * (l * 0.20 * sign);
    final c3 = p1 + t * (l * 0.68) + n * (l * 0.18 * sign);
    final c4 = p1 + t * (l * 0.62) + n * (l * 0.05 * sign);

    path.lineTo(pA.dx, pA.dy);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, pC.dx, pC.dy);
    path.cubicTo(c3.dx, c3.dy, c4.dx, c4.dy, pB.dx, pB.dy);
    path.lineTo(p2.dx, p2.dy);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Paints faint grid borders inside the game board
class BoardGridPainter extends CustomPainter {
  final int rows;
  final int cols;

  BoardGridPainter({required this.rows, required this.cols});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final cellWidth = size.width / cols;
    final cellHeight = size.height / rows;

    // Draw vertical lines
    for (int i = 1; i < cols; i++) {
      canvas.drawLine(
        Offset(i * cellWidth, 0),
        Offset(i * cellWidth, size.height),
        paint,
      );
    }

    // Draw horizontal lines
    for (int i = 1; i < rows; i++) {
      canvas.drawLine(
        Offset(0, i * cellHeight),
        Offset(size.width, i * cellHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BoardGridPainter oldDelegate) =>
      oldDelegate.rows != rows || oldDelegate.cols != cols;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  double _progressValue = 0.0;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  void _startLoading() {
    const totalDuration = Duration(milliseconds: 3000);
    const stepDuration = Duration(milliseconds: 30);
    final steps = totalDuration.inMilliseconds / stepDuration.inMilliseconds;
    var currentStep = 0;

    _progressTimer = Timer.periodic(stepDuration, (timer) {
      currentStep++;
      setState(() {
        _progressValue = (currentStep / steps).clamp(0.0, 1.0);
      });

      if (currentStep >= steps) {
        timer.cancel();
        _navigateToGame();
      }
    });
  }

  void _navigateToGame() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const JigsawGameScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeInOut),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (_progressValue * 100).toInt();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Background Glow effect
          Positioned(
            top: MediaQuery.of(context).size.height * 0.25,
            left: MediaQuery.of(context).size.width * 0.1,
            right: MediaQuery.of(context).size.width * 0.1,
            child: Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.03),
                      blurRadius: 80,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Main Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo Image with premium glowing borders
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withOpacity(0.15),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                    border: Border.all(
                      color: Colors.cyanAccent.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Image.asset(
                      'assets/icon.jpeg',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: const Color(0xFF1E293B),
                          child: const Icon(
                            Icons.videogame_asset_rounded,
                            size: 64,
                            color: Colors.cyanAccent,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                
                // Loading Progress and Text
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48.0),
                  child: Column(
                    children: [
                      // Linear Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          height: 6,
                          child: LinearProgressIndicator(
                            value: _progressValue,
                            backgroundColor: Colors.white.withOpacity(0.05),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Percentage Text
                      Text(
                        '$percent%',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.cyanAccent,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Bottom sponsored logo/text
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Sponsored by",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.4),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "KEYWATER",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withOpacity(0.9),
                    letterSpacing: 3.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
