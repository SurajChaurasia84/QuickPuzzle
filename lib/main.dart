import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  runApp(const TopPuzzleApp());
}

class TopPuzzleApp extends StatelessWidget {
  const TopPuzzleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Top Puzzle',
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
  int? currentGridRow;
  int? currentGridCol;

  JigsawPieceModel({
    required this.row,
    required this.col,
    required this.design,
    required this.currentPosition,
    this.isSnapped = false,
    this.currentGridRow,
    this.currentGridCol,
  });
}

class SparkleParticle {
  Offset position;
  Offset velocity;
  final Color color;
  final double size;
  double life;

  SparkleParticle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
    required this.life,
  });
}

class SparklePainter extends CustomPainter {
  final List<SparkleParticle> sparkles;

  SparklePainter(this.sparkles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in sparkles) {
      paint.color = p.color.withOpacity(p.life.clamp(0.0, 1.0));
      canvas.drawCircle(p.position, p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SparklePainter oldDelegate) => true;
}

class JigsawGameScreen extends StatefulWidget {
  final String imageUrl;
  final String? link;
  final int? timer;
  final String? reward;
  final int? initialRows;
  final int? initialCols;

  const JigsawGameScreen({
    super.key,
    required this.imageUrl,
    this.link,
    this.timer,
    this.reward,
    this.initialRows,
    this.initialCols,
  });

  @override
  State<JigsawGameScreen> createState() => _JigsawGameScreenState();
}

class _JigsawGameScreenState extends State<JigsawGameScreen> with TickerProviderStateMixin {
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

  Timer? _countdownTimer;
  int _secondsRemaining = 0;
  bool _isGameOver = false;

  // Sparkle Particles
  final List<SparkleParticle> _sparkles = [];
  AnimationController? _sparkleController;

  @override
  void initState() {
    super.initState();
    _rows = widget.initialRows ?? 3;
    _cols = widget.initialCols ?? 3;
    _startTimerIfNeeded();
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(() {
        _updateSparkles();
      });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _sparkleController?.dispose();
    super.dispose();
  }

  void _updateSparkles() {
    if (_sparkles.isEmpty) {
      _sparkleController?.stop();
      return;
    }
    setState(() {
      for (int i = _sparkles.length - 1; i >= 0; i--) {
        final p = _sparkles[i];
        p.position += p.velocity;
        p.life -= 0.05; // fade out
        if (p.life <= 0) {
          _sparkles.removeAt(i);
        }
      }
    });
  }

  void _triggerSparklesAt(double centerX, double centerY) {
    final random = math.Random();
    final List<SparkleParticle> newSparkles = [];
    
    for (int i = 0; i < 18; i++) {
      final angle = random.nextDouble() * 2 * math.pi;
      final speed = 1.0 + random.nextDouble() * 3.5;
      final velocity = Offset(math.cos(angle) * speed, math.sin(angle) * speed);
      
      final colors = [
        Colors.cyanAccent,
        Colors.amberAccent,
        Colors.white,
        Colors.yellowAccent,
      ];
      final color = colors[random.nextInt(colors.length)];
      
      newSparkles.add(SparkleParticle(
        position: Offset(centerX, centerY),
        velocity: velocity,
        color: color,
        size: 3.0 + random.nextDouble() * 4.0,
        life: 1.0,
      ));
    }

    setState(() {
      _sparkles.addAll(newSparkles);
    });

    _sparkleController?.repeat();
  }

  void _startTimerIfNeeded() {
    if (widget.timer != null && widget.timer! > 0) {
      _countdownTimer?.cancel();
      _secondsRemaining = widget.timer!;
      _isGameOver = false;
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_hasWon) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_secondsRemaining > 0) {
            _secondsRemaining--;
          } else {
            timer.cancel();
            _isGameOver = true;
            _showGameOverDialog();
          }
        });
      });
    }
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_off_rounded, color: Colors.redAccent, size: 56),
                const SizedBox(height: 16),
                const Text(
                  "GAME OVER",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Time limit reached! Don't give up, try again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(); // pop dialog
                        Navigator.of(context).pop(); // return to home
                      },
                      child: const Text(
                        "EXIT",
                        style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(); // pop dialog
                        _resetPuzzle();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("TRY AGAIN"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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

    generated.shuffle(math.Random());
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

    // Find the closest unoccupied grid cell on the board
    int? targetR;
    int? targetC;
    double minDistance = double.infinity;

    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        final isOccupied = _pieces.any((p) =>
            p.isSnapped &&
            p != piece &&
            p.currentGridRow == r &&
            p.currentGridCol == c);

        if (isOccupied) continue;

        final cellLeft = _boardLeft + c * w - 0.20 * w;
        final cellTop = _boardTop + r * h - 0.20 * h;
        final distance = (piece.currentPosition - Offset(cellLeft, cellTop)).distance;

        if (distance < minDistance) {
          minDistance = distance;
          targetR = r;
          targetC = c;
        }
      }
    }

    setState(() {
      // Snap threshold: 35.0 pixels to closest cell
      if (targetR != null && targetC != null && minDistance < 35.0) {
        final cellLeft = _boardLeft + targetC * w - 0.20 * w;
        final cellTop = _boardTop + targetR * h - 0.20 * h;

        piece.currentPosition = Offset(cellLeft, cellTop);
        piece.isSnapped = true;
        piece.currentGridRow = targetR;
        piece.currentGridCol = targetC;
        HapticFeedback.mediumImpact();

        // Sparkle if it's the CORRECT box!
        if (targetR == piece.row && targetC == piece.col) {
          final centerX = cellLeft + (w * 1.4) / 2;
          final centerY = cellTop + (h * 1.4) / 2;
          _triggerSparklesAt(centerX, centerY);
        }

        // Check victory
        final allSnapped = _pieces.every((p) => p.isSnapped);
        final allCorrect = _pieces.every((p) =>
            p.isSnapped &&
            p.currentGridRow == p.row &&
            p.currentGridCol == p.col);

        if (allSnapped && allCorrect) {
          _hasWon = true;
        }
      } else {
        // Return to its tray slot position
        piece.isSnapped = false;
        piece.currentGridRow = null;
        piece.currentGridCol = null;
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
      _startTimerIfNeeded();
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

                  // 2. Reward label — centered above the board
                  if (widget.reward != null && widget.reward!.isNotEmpty)
                    Positioned(
                      top: _boardTop - 45,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.amberAccent.withOpacity(0.35), width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.emoji_events_rounded, color: Colors.amberAccent, size: 15),
                              const SizedBox(width: 6),
                              const Text(
                                'Reward: ',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                widget.reward!,
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 3. Main Game Board Target
                  Positioned(
                    left: _boardLeft,
                    top: _boardTop,
                    child: _buildGameBoard(),
                  ),

                  // 3.5 Link button — centered below the board
                  if (widget.link != null && widget.link!.isNotEmpty)
                    Positioned(
                      top: _boardTop + _boardSize + 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () async {
                            final uri = Uri.tryParse(widget.link!);
                            if (uri != null && await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white54.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              // border: Border.all(color: Colors.white54.withOpacity(0.30), width: 1),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.link_rounded, color: Colors.white54, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'Visit Link',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 2.5 Info Row: Grid Size (left) + Timer (right)
                  Positioned(
                    top: 68,
                    left: 16,
                    right: 16,
                    child: _buildInfoRow(),
                  ),

                  // 3. Bottom Tray visual card — hidden when hint is showing
                  if (!_showHint)
                    Positioned(
                      left: 0,
                      top: _trayTop - 8,
                      right: 0,
                      height: _trayHeight + 16,
                      child: _buildTrayBackground(),
                    ),

                  // 4. Render snapped pieces first (bottom of stack) — always visible
                  ..._buildPuzzlePieces(snappedOnly: true),

                  // 5. Render unsnapped pieces — hidden when hint is showing
                  if (!_showHint)
                    ..._buildPuzzlePieces(snappedOnly: false),

                  // 6. Floating Sparkles particles overlay
                  if (_sparkles.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: SparklePainter(_sparkles),
                        ),
                      ),
                    ),

                  // 7. Victory Overlay dialog
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
    final correctCount = _pieces.where((p) => p.isSnapped && p.currentGridRow == p.row && p.currentGridCol == p.col).length;
    final progressPercent = _pieces.isEmpty ? 0 : ((correctCount / _pieces.length) * 100).toInt();

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

        // Center spacer
        const Spacer(),

        // Action buttons
        Row(
          children: [
            // Percentage Progress Indicator in white54
            Text(
              '$progressPercent%',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white54,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
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

  // Info row: grid size on left, countdown timer on right
  Widget _buildInfoRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Grid size (left) — no background, no border
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_view_rounded, color: Colors.cyanAccent, size: 14),
            const SizedBox(width: 6),
            Text(
              '${_rows}x$_cols',
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),

        // Countdown timer (right) — only shown when timer is set, no background, no border
        if (widget.timer != null && widget.timer! > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_outlined, color: Colors.redAccent, size: 14),
              const SizedBox(width: 6),
              Text(
                _formatTime(_secondsRemaining),
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
      ],
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
              if (_isGameOver || _hasWon) return;
              _isScrollingTray = false;
              setState(() {
                _activeDraggingIndex = i;
                if (piece.isSnapped) {
                  piece.isSnapped = false;
                  piece.currentGridRow = null;
                  piece.currentGridCol = null;
                  _isDraggingPiece = true;
                } else {
                  _isDraggingPiece = false;
                }
              });
            },
            onPanUpdate: (details) {
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
                if (widget.reward != null && widget.reward!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.stars, color: Colors.amberAccent, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "Reward: ${widget.reward}",
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (widget.link != null && widget.link!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse(widget.link!);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('VISIT LINK'),
                  ),
                ],
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
  int _currentTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildHomeTab(context),
          _buildWinnersTab(),
          _buildOfferwallTab(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Colors.white.withOpacity(0.05),
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          onTap: (index) {
            setState(() {
              _currentTabIndex = index;
            });
          },
          backgroundColor: const Color(0xFF0F172A),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.cyanAccent,
          unselectedItemColor: Colors.white38,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.emoji_events_rounded),
              label: 'Winners',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.local_offer_rounded),
              label: 'Offerwall',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context) {
    return Container(
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
                              'assets/logo.jpeg',
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
                                "Top Puzzle",
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
                        final String? link = data['link'] as String?;
                        final int? timer = data['timer'] as int?;
                        final String? reward = data['reward'] as String?;
                        final int? rows = data['rows'] as int?;
                        final int? cols = data['cols'] as int?;
                        
                        // Format Upload Date
                        String uploadDateStr = 'Unknown Date';
                        if (data['uploadedAt'] != null && data['uploadedAt'] is Timestamp) {
                          final timestamp = data['uploadedAt'] as Timestamp;
                          final date = timestamp.toDate();
                          uploadDateStr = "${date.day}/${date.month}/${date.year}";
                        }

                        return _buildPuzzleCard(
                          imageUrl: imageUrl,
                          fileName: fileName,
                          uploadDateStr: uploadDateStr,
                          link: link,
                          timer: timer,
                          reward: reward,
                          rows: rows,
                          cols: cols,
                        );
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
    );
  }

  Widget _buildWinnersTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.cyanAccent.withOpacity(0.15), width: 1.5),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: Colors.cyanAccent,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Winners Leaderboard",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Coming soon! The top puzzle solvers and prize winners will be listed here.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOfferwallTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.cyanAccent.withOpacity(0.15), width: 1.5),
                  ),
                  child: const Icon(
                    Icons.local_offer_rounded,
                    color: Colors.cyanAccent,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Offerwall Tasks",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Coming soon! Complete custom offers and tasks to win special rewards.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPuzzleCard({
    required String imageUrl,
    required String fileName,
    required String uploadDateStr,
    String? link,
    int? timer,
    String? reward,
    int? rows,
    int? cols,
  }) {
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
          onTap: () => _navigateToGame(
            imageUrl: imageUrl,
            link: link,
            timer: timer,
            reward: reward,
            initialRows: rows,
            initialCols: cols,
          ),
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

  void _navigateToGame({
    required String imageUrl,
    String? link,
    int? timer,
    String? reward,
    int? initialRows,
    int? initialCols,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => JigsawGameScreen(
          imageUrl: imageUrl,
          link: link,
          timer: timer,
          reward: reward,
          initialRows: initialRows,
          initialCols: initialCols,
        ),
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
    final user = FirebaseAuth.instance.currentUser;
    final nextScreen = user != null ? const HomeScreen() : const LoginScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
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
                      'assets/logo.jpeg',
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser != null) {
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final UserCredential userCredential =
            await FirebaseAuth.instance.signInWithCredential(credential);
        final User? user = userCredential.user;

        if (user != null) {
          // Save or merge user details in Firestore
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'uid': user.uid,
            'name': user.displayName ?? '',
            'email': user.email ?? '',
            'photoUrl': user.photoURL ?? '',
            'lastLogin': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          if (mounted) {
            _navigateToHome();
          }
        }
      }
    } catch (e) {
      debugPrint('Google Sign-In failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign-in failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Background Glow effect
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.cyanAccent.withOpacity(0.04),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.cyanAccent.withOpacity(0.02),
              ),
            ),
          ),

          // Main Layout
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Premium Jigsaw Logo
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyanAccent.withOpacity(0.2),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                        border: Border.all(
                          color: Colors.cyanAccent.withOpacity(0.4),
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/logo.jpeg',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.extension_rounded,
                              size: 64,
                              color: Colors.cyanAccent,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // App Title
                    const Text(
                      'Top Puzzle',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Slogan
                    Text(
                      'Solve Custom Puzzles & Earn Rewards',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Action Buttons / Loading Indicator
                    if (_isLoading)
                      const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                        ),
                      )
                    else ...[
                      // Google Sign-In Button
                      GestureDetector(
                        onTap: _handleGoogleSignIn,
                        child: Container(
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.cyanAccent.withOpacity(0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.cyanAccent.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Simplified Premium Google G-Icon
                              Container(
                                width: 24,
                                height: 24,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'G',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Text(
                                'Sign In with Google',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Skip Button
                      TextButton(
                        onPressed: _navigateToHome,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Skip for now',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                // User Profile Card / Guest Card
                if (user != null)
                  _buildProfileCard(user)
                else
                  _buildGuestCard(context),

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
                        'subject': 'Top Puzzle Help & Support',
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
                    Share.share('Check out Top Puzzle, the ultimate custom jigsaw puzzle game app! Download and start solving puzzles: https://play.google.com/store/apps/details?id=com.quick.puzzleapp');
                  },
                ),

                // Log Out Option
                if (user != null) ...[
                  const SizedBox(height: 16),
                  _buildSettingsCard(
                    context: context,
                    title: 'Log Out',
                    icon: Icons.logout_rounded,
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                      await GoogleSignIn().signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    },
                  ),
                ],

                const Spacer(),
                Text(
                  'Top Puzzle v1.0.0',
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

  Widget _buildProfileCard(User user) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.05),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.cyanAccent, width: 2),
            ),
            child: ClipOval(
              child: user.photoURL != null && user.photoURL!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: user.photoURL!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                      ),
                      errorWidget: (context, url, error) => const Icon(Icons.person, color: Colors.cyanAccent, size: 28),
                    )
                  : const Icon(Icons.person, color: Colors.cyanAccent, size: 28),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName ?? 'Jigsaw Player',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amberAccent.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.amberAccent.withOpacity(0.1),
                ),
                child: const Icon(Icons.account_circle_outlined, color: Colors.amberAccent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Guest Player',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sign in to save rewards & sync progress',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              elevation: 0,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.login_rounded, size: 16),
                SizedBox(width: 8),
                Text(
                  'Sign In with Google',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
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
