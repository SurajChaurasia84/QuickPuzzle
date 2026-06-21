import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF0F172A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
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
  final String imageUrl;

  const JigsawGameScreen({super.key, required this.imageUrl});

  @override
  State<JigsawGameScreen> createState() => _JigsawGameScreenState();
}

class _JigsawGameScreenState extends State<JigsawGameScreen> {
  // Grid size
  int _rows = 3;
  int _cols = 3;

  // Game stats
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
  double _trayScrollOffset = 0.0;

  // Active pieces
  List<JigsawPieceModel> _pieces = [];
  int? _activeDraggingIndex;
  bool _isScrollingTray = false;
  bool _isDraggingPiece = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
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

  // Arranges all unsnapped pieces in a horizontally scrolling line inside the bottom tray (fixed 75x75 slots)
  void _organizeTrayPieces() {
    final count = _pieces.length;
    if (count == 0) return;

    // Fixed drawer size (same for all difficulties)
    const drawerPw = 75.0;
    const drawerPh = 75.0;

    final trayLeft = 48.0; // leave space for left padding
    final trayWidth = _screenWidth - 96.0;

    // Clamp scroll offset to valid bounds based on total slots (all pieces)
    final totalWidth = count * (drawerPw + 16.0);
    final maxScroll = math.max(0.0, totalWidth - trayWidth);
    _trayScrollOffset = _trayScrollOffset.clamp(0.0, maxScroll);

    setState(() {
      for (int i = 0; i < count; i++) {
        final piece = _pieces[i];
        if (piece.isSnapped) continue;
        
        // If this piece is currently being dragged up/out, don't override its position!
        if (_isDraggingPiece && _activeDraggingIndex != null && _activeDraggingIndex! < _pieces.length && _pieces[_activeDraggingIndex!] == piece) {
          continue;
        }

        final posX = trayLeft + i * (drawerPw + 16.0) - _trayScrollOffset;
        final posY = _trayTop + (_trayHeight - drawerPh) / 2;

        piece.currentPosition = Offset(posX, posY);
      }
    });
  }

  void _scrollTray(double delta) {
    final count = _pieces.length;
    if (count == 0) return;

    // Fixed drawer size
    const drawerPw = 75.0;

    final trayWidth = _screenWidth - 96.0;
    final totalWidth = count * (drawerPw + 16.0);
    final maxScroll = math.max(0.0, totalWidth - trayWidth);

    setState(() {
      _trayScrollOffset = (_trayScrollOffset + delta).clamp(0.0, maxScroll);
      _organizeTrayPieces();
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
      // Snap tolerance of 22 pixels
      if (dist < 22.0) {
        piece.currentPosition = Offset(targetLeft, targetTop);
        piece.isSnapped = true;
        HapticFeedback.mediumImpact();

        // Check victory
        if (_pieces.every((p) => p.isSnapped)) {
          _hasWon = true;
        }
      } else {
        // Return to its tray slot position
        _organizeTrayPieces();
      }
      _activeDraggingIndex = null;
    });
  }

  // Resets the puzzle layout completely
  void _resetPuzzle() {
    setState(() {
      _hasWon = false;
      _trayScrollOffset = 0.0;
      _generateAndShufflePieces();
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
              _boardSize = math.min(_screenWidth * 0.92, math.min(availableHeight, 380.0));
              _boardLeft = (_screenWidth - _boardSize) / 2;
              _boardTop = 100.0 + (availableHeight - _boardSize) / 2;

              _trayTop = _screenHeight - 145.0;
              _trayHeight = 120.0;

              // Generate pieces once we have dynamic screen sizes
              if (_pieces.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _pieces.isEmpty) {
                    _generateAndShufflePieces();
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

                  // 2.5 Difficulty Selector Below the HUD (App Bar)
                  Positioned(
                    top: 68,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _buildDifficultySelector(),
                    ),
                  ),

                  // 3. Bottom Tray visual card
                  Positioned(
                    left: 0,
                    top: _trayTop - 8,
                    right: 0,
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

  Widget _buildDifficultySelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDiffButton('2x2', 2),
            const SizedBox(width: 6),
            _buildDiffButton('3x3', 3),
            const SizedBox(width: 6),
            _buildDiffButton('4x4', 4),
            const SizedBox(width: 6),
            _buildDiffButton('5x5', 5),
            const SizedBox(width: 6),
            _buildDiffButton('6x6', 6),
            const SizedBox(width: 6),
            _buildDiffButton('7x7', 7),
            const SizedBox(width: 6),
            _buildDiffButton('8x8', 8),
          ],
        ),
      ),
    );
  }

  // Renders the transparent HUD control and status card
  Widget _buildHeaderHUD() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Back Button
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.cyanAccent,
            size: 20,
          ),
          tooltip: 'Back to Menu',
          onPressed: () {
            Navigator.of(context).pop();
          },
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
    return Hero(
      tag: widget.imageUrl,
      child: Container(
        width: _boardSize,
        height: _boardSize,
        decoration: BoxDecoration(
          color: const Color(0xFF020617).withOpacity(0.5),
          borderRadius: BorderRadius.zero,
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
              borderRadius: BorderRadius.zero,
              child: Opacity(
                opacity: 0.20,
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  width: _boardSize,
                  height: _boardSize,
                  fit: BoxFit.fill,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: const Color(0xFF1E293B),
                    child: const Icon(Icons.broken_image, color: Colors.cyanAccent, size: 48),
                  ),
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
     ),
    );
  }



  // Background visual container for the bottom tray (no text, direct drag scrolling)
  Widget _buildTrayBackground() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Divider Line
        Container(
          height: 1.0,
          color: Colors.white.withOpacity(0.08),
        ),

        // 2. Transparent Touch Target for scrolling (opaque behavior to catch all touches)
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              _scrollTray(-details.delta.dx);
            },
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
  // Dynamic stack of Jigsaw Pieces
  List<Widget> _buildPuzzlePieces({required bool snappedOnly}) {
    final w = _boardSize / _cols;
    final h = _boardSize / _rows;
    final boardPw = w * 1.4;
    final boardPh = h * 1.4;

    // Fixed drawer piece size (same for all difficulties)
    const drawerPw = 75.0;
    const drawerPh = 75.0;

    final List<Widget> list = [];

    for (int i = 0; i < _pieces.length; i++) {
      final piece = _pieces[i];
      if (piece.isSnapped != snappedOnly) continue;

      final isDraggingThis = _isDraggingPiece && _activeDraggingIndex == i;
      final pw = (piece.isSnapped || isDraggingThis) ? boardPw : drawerPw;
      final ph = (piece.isSnapped || isDraggingThis) ? boardPh : drawerPh;
      final scale = (piece.isSnapped || isDraggingThis) ? 1.0 : (drawerPw / boardPw);

      list.add(
        Positioned(
          left: piece.currentPosition.dx,
          top: piece.currentPosition.dy,
          child: GestureDetector(
            onPanStart: (details) {
              if (piece.isSnapped) return;
              _isScrollingTray = false;
              _isDraggingPiece = false;
              setState(() {
                _activeDraggingIndex = i;
              });
            },
            onPanUpdate: (details) {
              if (piece.isSnapped) return;
              if (!_isScrollingTray && !_isDraggingPiece) {
                final dx = details.delta.dx.abs();
                final dy = details.delta.dy.abs();
                if (dx > dy * 1.2) {
                  _isScrollingTray = true;
                } else if (dy > dx * 1.2 || details.delta.dy < -0.5) {
                  _isDraggingPiece = true;
                  // Adjust currentPosition to prevent visual jump due to scaling up
                  setState(() {
                    piece.currentPosition = Offset(
                      piece.currentPosition.dx - (boardPw - drawerPw) / 2,
                      piece.currentPosition.dy - (boardPh - drawerPh) / 2,
                    );
                  });
                }
              }

              if (_isScrollingTray) {
                _scrollTray(-details.delta.dx);
              } else if (_isDraggingPiece) {
                setState(() {
                  piece.currentPosition += details.delta;
                });
              }
            },
            onPanEnd: (details) {
              if (piece.isSnapped) return;
              final wasDragging = _isDraggingPiece;
              setState(() {
                _activeDraggingIndex = null;
                _isScrollingTray = false;
                _isDraggingPiece = false;
              });
              if (wasDragging) {
                _checkSnap(i);
              } else {
                _organizeTrayPieces();
              }
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
                          left: (-piece.col * w + 0.20 * w) * scale,
                          top: (-piece.row * h + 0.20 * h) * scale,
                          child: CachedNetworkImage(
                            imageUrl: widget.imageUrl,
                            width: _boardSize * scale,
                            height: _boardSize * scale,
                            fit: BoxFit.fill,
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFF1E293B),
                              child: const Icon(Icons.broken_image, color: Colors.cyanAccent),
                            ),
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Custom Title / Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                'assets/puzzle.png',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: const Color(0xFF1E293B),
                                    child: const Icon(
                                      Icons.grid_view_rounded,
                                      color: Colors.cyanAccent,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "QuickPuzzle",
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Choose a puzzle image to start",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(0.5),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.settings_rounded,
                              color: Colors.amberAccent,
                              size: 28,
                            ),
                            tooltip: 'Settings',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const SettingsScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Firestore Stream Builder
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('puzzle_images')
                    .orderBy('uploadedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: _buildErrorWidget(snapshot.error.toString()),
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                        ),
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: _buildEmptyStateWidget(),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.0,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final imageUrl = data['url'] as String? ?? '';
                          final fileName = data['fileName'] as String? ?? 'Unnamed Puzzle';
                          
                          // Format Upload Date
                          String uploadDateStr = 'Unknown Date';
                          if (data['uploadedAt'] != null && data['uploadedAt'] is Timestamp) {
                            final timestamp = data['uploadedAt'] as Timestamp;
                            final date = timestamp.toDate();
                            uploadDateStr = "${date.day}/${date.month}/${date.year}";
                          }

                          return _buildPuzzleCard(imageUrl, fileName, uploadDateStr);
                        },
                        childCount: docs.length,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPuzzleCard(String imageUrl, String fileName, String uploadDateStr) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _navigateToGame(imageUrl),
          child: Hero(
            tag: imageUrl,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.cyanAccent.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFF0F172A),
                child: const Icon(
                  Icons.broken_image_rounded,
                  color: Colors.cyanAccent,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStateWidget() {
    return Container(
      padding: const EdgeInsets.all(32),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.05),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.2),
              ),
            ),
            child: const Icon(
              Icons.image_not_supported_rounded,
              color: Colors.cyanAccent,
              size: 48,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "No Puzzles Uploaded",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Please use the Admin App to upload images and they will show up here dynamically.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.5),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String errorMsg) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.redAccent.withOpacity(0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            "Connection Error",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            errorMsg.contains('PERMISSION_DENIED')
                ? "Access denied. Please check Firestore Security Rules on Firebase Console."
                : "Failed to connect: $errorMsg",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.6),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToGame(String imageUrl) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => JigsawGameScreen(imageUrl: imageUrl),
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
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }
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
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.cyanAccent),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'SETTINGS',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                _buildSettingsCard(
                  context: context,
                  title: 'Privacy Policy',
                  icon: Icons.privacy_tip_rounded,
                  onTap: () async {
                    final url = Uri.parse('https://surajchaurasia84.github.io/QuickPuzzle/');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    } else {
                      if (context.mounted) {
                        _showContentDialog(
                          context,
                          'Privacy Policy',
                          'Could not open the Privacy Policy link. Please visit:\n\nhttps://surajchaurasia84.github.io/QuickPuzzle/',
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildSettingsCard(
                  context: context,
                  title: 'Help & Support',
                  icon: Icons.help_outline_rounded,
                  onTap: () async {
                    final emailUri = Uri(
                      scheme: 'mailto',
                      path: 'puzzle0798@gmail.com',
                      queryParameters: {
                        'subject': 'QuickPuzzle Help & Support',
                      },
                    );
                    if (await canLaunchUrl(emailUri)) {
                      await launchUrl(emailUri);
                    } else {
                      if (context.mounted) {
                        _showContentDialog(
                          context,
                          'Help & Support',
                          'For help and support, please contact us at:\n\npuzzle0798@gmail.com\n\n(We could not open your email application automatically.)',
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildSettingsCard(
                  context: context,
                  title: 'Share App',
                  icon: Icons.share_rounded,
                  onTap: () {
                    Share.share('Check out QuickPuzzle, the ultimate custom jigsaw puzzle game app! Download and start solving puzzles: https://play.google.com/store/apps/details?id=com.quick.puzzleapp');
                  },
                ),
                const Spacer(),
                Text(
                  'QuickPuzzle v1.0.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.3),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Icon(icon, color: Colors.cyanAccent, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white.withOpacity(0.3),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContentDialog(BuildContext context, String title, String text) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.1),
                  blurRadius: 30,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.cyanAccent,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.8),
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'CLOSE',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
