import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// --- TYPES (port from types.ts) ---
enum CellType { WALL, PATH }

class Position {
  final int row;
  final int col;
  const Position(this.row, this.col);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Position && row == other.row && col == other.col;

  @override
  int get hashCode => row * 31 + col;
}

enum GameTurn { PLAYER, ENEMY }
enum TurnPhase { ROLLING, MOVING }
enum GameStatus { LORE, PLAYING, WIN, LOSE }

const int MAZE_WIDTH = 21;
const int MAZE_HEIGHT = 21;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]).then((_) {
    runApp(const MyApp());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ECO NEGRO',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.grey[900],
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'monospace'),
      ),
      home: const GamePage(),
    );
  }
}

class GameProvider extends ChangeNotifier {
  late List<List<CellType>> maze;
  Position playerPos = const Position(1, 1);
  Position enemyPos = const Position(MAZE_HEIGHT - 2, 1);
  Position exitPos = const Position(MAZE_HEIGHT - 2, MAZE_WIDTH - 2);

  GameTurn currentTurn = GameTurn.PLAYER;
  TurnPhase turnPhase = TurnPhase.ROLLING;
  GameStatus gameStatus = GameStatus.LORE;
  String? resultMessage;

  int diceResult = 0;
  Set<Position> possibleMoves = {};

  int echoCharges = 0;
  bool echoActive = false;

  final Random _rng = Random();

  GameProvider() {
    _initGame();
  }

  void _initGame() {
    maze = generateMaze(MAZE_WIDTH, MAZE_HEIGHT);
    // Add extra loops to increase possible routes to the exit
    addMazeLoops(maze, passes: 3, chance: 0.12);

    playerPos = const Position(1, 1);
    // Choose exit and enemy positions on PATH cells, trying to keep them far apart
    final pathCells = <Position>[];
    for (int r = 1; r < maze.length - 1; r++) {
      for (int c = 1; c < maze[0].length - 1; c++) {
        if (maze[r][c] == CellType.PATH) pathCells.add(Position(r, c));
      }
    }

    Position chooseFar(List<Position> candidates, Position from, int minDist) {
      final shuffled = List<Position>.from(candidates)..shuffle();
      for (final p in shuffled) {
        if (_manhattan(p, from) >= minDist) return p;
      }
      return candidates.isNotEmpty ? candidates.first : from;
    }

    exitPos = chooseFar(pathCells, playerPos, 10);
    // Ensure enemy is not spawned on the exit or too close to player
    enemyPos = chooseFar(pathCells.where((p) => p != exitPos).toList(), playerPos, 8);
    currentTurn = GameTurn.PLAYER;
    turnPhase = TurnPhase.ROLLING;
    diceResult = 0;
    possibleMoves = {};
    echoCharges = 0;
    echoActive = false;
    gameStatus = GameStatus.LORE;
  }

  void startGame() {
    gameStatus = GameStatus.PLAYING;
    notifyListeners();
  }

  void restartGame() {
    _initGame();
    // Immediately start playing after restart
    gameStatus = GameStatus.PLAYING;
    notifyListeners();
  }

  void rollDice() {
    if (currentTurn != GameTurn.PLAYER || turnPhase != TurnPhase.ROLLING) return;
    diceResult = _rng.nextInt(4) + 1;
    possibleMoves = calculatePossibleMoves(playerPos, diceResult, maze);
    turnPhase = TurnPhase.MOVING;
    notifyListeners();
  }

  void passTurn() {
    if (currentTurn != GameTurn.PLAYER) return;
    // End player turn without moving
    _endPlayerTurn();
  }

  void activateEcho() {
    if (echoCharges < 6 || currentTurn != GameTurn.PLAYER) return;
    echoActive = true;
    notifyListeners();
  }

  void movePlayer(Position to) {
    if (currentTurn != GameTurn.PLAYER || turnPhase != TurnPhase.MOVING) return;
    if (!possibleMoves.contains(to)) return;
    playerPos = to;
    // If echo active, it turns off and charges reset
    if (echoActive) {
      echoActive = false;
      echoCharges = 0;
    }
    // Check win
    if (playerPos == exitPos) {
      gameStatus = GameStatus.WIN;
      resultMessage = '!HAZ LOGRADO ESCAPAR DE LA CRIATURA¡';
      notifyListeners();
      return;
    }

    // If player moved onto enemy
    if (playerPos == enemyPos) {
      gameStatus = GameStatus.LOSE;
      resultMessage = '!TEAN ATRAPADO YA NO QUEDA ESPERANZA PARA TI¡';
      notifyListeners();
      return;
    }

    _endPlayerTurn();
  }

  void _endPlayerTurn() {
    // If echo was active it already reset charges in move; if not active, gain 1 charge
    if (!echoActive) {
      echoCharges = (echoCharges + 1).clamp(0, 6);
    } else {
      // echoActive is true => effect ends and charges become 0
      echoActive = false;
      echoCharges = 0;
    }
    diceResult = 0;
    possibleMoves = {};
    turnPhase = TurnPhase.ROLLING;
    currentTurn = GameTurn.ENEMY;
    notifyListeners();

    // Perform enemy action after short delay
    Future.delayed(const Duration(milliseconds: 600), () {
      _enemyTurn();
    });
  }

  void _enemyTurn() {
    if (gameStatus != GameStatus.PLAYING) return;
    // Simple enemy AI: move one step toward player using BFS path
    final path = _bfsPath(enemyPos, playerPos, maze);
    if (path.length >= 2) {
      enemyPos = path[1]; // move 1 step along path
    }
    // Check if enemy caught player (same cell)
    if (enemyPos == playerPos) {
      gameStatus = GameStatus.LOSE;
      resultMessage = '!TEAN ATRAPADO YA NO QUEDA ESPERANZA PARA TI¡';
      notifyListeners();
      return;
    }

    // If enemy is adjacent (one block) to player -> immediate lose and dialog
    if (_manhattan(enemyPos, playerPos) == 1) {
      gameStatus = GameStatus.LOSE;
      resultMessage = '!TEAN ATRAPADO YA NO QUEDA ESPERANZA PARA TI¡';
      notifyListeners();
      return;
    }

    // End enemy turn
    currentTurn = GameTurn.PLAYER;
    turnPhase = TurnPhase.ROLLING;
    notifyListeners();
  }

  // Helper BFS path (shortest path) returning list of positions from start to goal inclusive
  List<Position> _bfsPath(Position start, Position goal, List<List<CellType>> grid) {
    final h = grid.length;
    final w = grid[0].length;
    final q = <Position>[];
    final cameFrom = <Position, Position?>{};
    q.add(start);
    cameFrom[start] = null;
    final dirs = [
      const Position(-1, 0),
      const Position(1, 0),
      const Position(0, -1),
      const Position(0, 1),
    ];

    while (q.isNotEmpty) {
      final cur = q.removeAt(0);
      if (cur == goal) break;
      for (final d in dirs) {
        final nr = cur.row + d.row;
        final nc = cur.col + d.col;
        if (nr > 0 && nr < h - 1 && nc > 0 && nc < w - 1 && grid[nr][nc] == CellType.PATH) {
          final np = Position(nr, nc);
          if (!cameFrom.containsKey(np)) {
            cameFrom[np] = cur;
            q.add(np);
          }
        }
      }
    }

    if (!cameFrom.containsKey(goal)) return [start];
    final path = <Position>[];
    Position? cur = goal;
    while (cur != null) {
      path.insert(0, cur);
      cur = cameFrom[cur];
    }
    return path;
  }
}

int _manhattan(Position a, Position b) => (a.row - b.row).abs() + (a.col - b.col).abs();

// --- Maze generation (DFS) ported from TS ---
List<List<CellType>> generateMaze(int width, int height) {
  final w = width % 2 == 0 ? width + 1 : width;
  final h = height % 2 == 0 ? height + 1 : height;
  final maze = List.generate(h, (_) => List.generate(w, (_) => CellType.WALL));
  final stack = <Position>[];
  final startPos = const Position(1, 1);
  maze[startPos.row][startPos.col] = CellType.PATH;
  stack.add(startPos);
  final rnd = Random();

  while (stack.isNotEmpty) {
    final current = stack.last;
    final neighbors = <Map<String, dynamic>>[];
    final directions = <Map<String,int>>[
      {'r': -2, 'c': 0, 'wr': -1, 'wc': 0},
      {'r': 2, 'c': 0, 'wr': 1, 'wc': 0},
      {'r': 0, 'c': -2, 'wr': 0, 'wc': -1},
      {'r': 0, 'c': 2, 'wr': 0, 'wc': 1},
    ];

    for (final dir in directions) {
      final nRow = current.row + (dir['r']!);
      final nCol = current.col + (dir['c']!);
      if (nRow > 0 && nRow < h - 1 && nCol > 0 && nCol < w - 1 && maze[nRow][nCol] == CellType.WALL) {
        neighbors.add({'row': nRow, 'col': nCol, 'wall': Position(current.row + (dir['wr']!), current.col + (dir['wc']!))});
      }
    }

    if (neighbors.isNotEmpty) {
      final pick = neighbors[rnd.nextInt(neighbors.length)];
      final row = pick['row'] as int;
      final col = pick['col'] as int;
      final wall = pick['wall'] as Position;
      maze[wall.row][wall.col] = CellType.PATH;
      maze[row][col] = CellType.PATH;
      stack.add(Position(row, col));
    } else {
      stack.removeLast();
    }
  }
  return maze;
}

// Add extra connections (loops) to the maze to increase escape possibilities.
void addMazeLoops(List<List<CellType>> maze, {int passes = 3, double chance = 0.10}) {
  final rnd = Random();
  final h = maze.length;
  final w = maze[0].length;
  for (int p = 0; p < passes; p++) {
    for (int r = 1; r < h - 1; r++) {
      for (int c = 1; c < w - 1; c++) {
        if (maze[r][c] == CellType.WALL) {
          // Count adjacent PATH neighbors
          int paths = 0;
          if (maze[r - 1][c] == CellType.PATH) paths++;
          if (maze[r + 1][c] == CellType.PATH) paths++;
          if (maze[r][c - 1] == CellType.PATH) paths++;
          if (maze[r][c + 1] == CellType.PATH) paths++;
          // If this wall separates two or more path cells, knocking it down creates a loop
          if (paths >= 2 && rnd.nextDouble() < chance) {
            maze[r][c] = CellType.PATH;
          }
        }
      }
    }
  }
}

// --- BFS for possible moves ---
Set<Position> calculatePossibleMoves(Position start, int steps, List<List<CellType>> grid) {
  final h = grid.length;
  final w = grid[0].length;
  final visited = <Position>{};
  final q = <Position>[];
  final dist = <Position, int>{};
  q.add(start);
  visited.add(start);
  dist[start] = 0;
  final dirs = [
    const Position(-1, 0),
    const Position(1, 0),
    const Position(0, -1),
    const Position(0, 1),
  ];

  while (q.isNotEmpty) {
    final cur = q.removeAt(0);
    final dcur = dist[cur]!;
    if (dcur >= steps) continue;
    for (final dir in dirs) {
      final nr = cur.row + dir.row;
      final nc = cur.col + dir.col;
      if (nr > 0 && nr < h - 1 && nc > 0 && nc < w - 1 && grid[nr][nc] == CellType.PATH) {
        final np = Position(nr, nc);
        if (!visited.contains(np)) {
          visited.add(np);
          dist[np] = dcur + 1;
          q.add(np);
        }
      }
    }
  }

  // Remove start position and any positions at distance 0
  visited.remove(start);
  // Filter to distance <= steps
  final out = visited.where((p) => dist[p]! <= steps).toSet();
  return out;
}

// --- UI ---
class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  late GameProvider game;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    game = GameProvider();
    game.addListener(_onGameUpdate);
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showLore());
  }

  void _onGameUpdate() {
    if (!mounted) return;
    final status = game.gameStatus;
    if (status == GameStatus.WIN || status == GameStatus.LOSE) {
      final message = game.resultMessage ?? (status == GameStatus.WIN ? '!HAZ LOGRADO ESCAPAR DE LA CRIATURA¡' : '!TEAN ATRAPADO YA NO QUEDA ESPERANZA PARA TI¡');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Text(status == GameStatus.WIN ? 'Victoria' : 'Derrota', style: TextStyle(color: status == GameStatus.WIN ? Colors.tealAccent : Colors.redAccent)),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  game.restartGame();
                  Navigator.of(context).pop();
                },
                child: const Text('REINICIAR'),
              )
            ],
          ),
        );
      });
    }
  }

  void _showLore() {
    if (game.gameStatus == GameStatus.LORE) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Justificación de la Simulación'),
          content: const SingleChildScrollView(
            child: Text(
              'Las instalaciones de Aethel no solo eran un laboratorio, sino un campo de entrenamiento.\n\n'
              'Este juego es una recreación de esas pruebas, una simulación diseñada para medir la adaptabilidad bajo condiciones de incertidumbre.\n\n'
              'Tu movimiento es incierto (dado). Tu habilidad de Ecolocalización puede revelar momentáneamente la presencia de la Resonancia y la salida, pero su uso es limitado y revela tanto peligro como posibilidad. Actúa con cautela, Sujeto 7.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  game.startGame();
                });
                Navigator.of(context).pop();
              },
              child: const Text('COMENZAR'),
            )
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    game.removeListener(_onGameUpdate);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ChangeNotifierProvider<GameProvider>.value(
          value: game,
          child: Column(
            children: [
              const SizedBox(height: 8),
              _buildHeader(),
              const SizedBox(height: 8),
              Expanded(child: _buildBoard()),
              _buildBottomPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Consumer<GameProvider>(builder: (context, g, _) {
      final isPlayerTurn = g.currentTurn == GameTurn.PLAYER;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ECO NEGRO', style: const TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isPlayerTurn ? Colors.tealAccent.shade700 : Colors.redAccent.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isPlayerTurn ? 'Sujeto 7' : 'La Resonancia',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold),
              ),
            )
          ],
        ),
      );
    });
  }

  Widget _buildBoard() {
    return Consumer<GameProvider>(builder: (context, g, _) {
      final gridSize = MAZE_WIDTH;
      final screenWidth = MediaQuery.of(context).size.width;
      final boardSize = min(screenWidth - 12, MediaQuery.of(context).size.height * 0.68);
      final cellSize = boardSize / gridSize;

      return Center(
        child: Container(
          color: Colors.transparent,
          width: boardSize,
          height: boardSize,
          child: InteractiveViewer(
            maxScale: 4.0,
            minScale: 0.5,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridSize,
                childAspectRatio: 1,
              ),
              itemCount: gridSize * gridSize,
              itemBuilder: (context, index) {
                final row = index ~/ gridSize;
                final col = index % gridSize;
                final cell = g.maze[row][col];
                final pos = Position(row, col);

                final isWall = cell == CellType.WALL;
                final isPlayer = pos == g.playerPos;
                final isEnemy = pos == g.enemyPos && (g.currentTurn == GameTurn.ENEMY || g.echoActive);
                final isExit = pos == g.exitPos && g.echoActive;
                final isPossible = g.possibleMoves.contains(pos) && g.currentTurn == GameTurn.PLAYER && g.turnPhase == TurnPhase.MOVING;

                Color bg = isWall ? Colors.grey[850]! : Colors.grey[800]!;
                Widget content = const SizedBox.shrink();

                if (isExit) {
                  content = Container(
                    width: cellSize * 0.6,
                    height: cellSize * 0.6,
                    decoration: BoxDecoration(color: Colors.tealAccent, borderRadius: BorderRadius.circular(4)),
                  );
                } else if (isPlayer) {
                  content = Container(
                    width: cellSize * 0.6,
                    height: cellSize * 0.6,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.tealAccent),
                  );
                } else if (isEnemy) {
                  content = Container(
                    width: cellSize * 0.6,
                    height: cellSize * 0.6,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent),
                  );
                }

                // For possible moves, render pulsing overlay
                return GestureDetector(
                  onTap: () {
                    if (isPossible) {
                      g.movePlayer(pos);
                      setState(() {});
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: bg,
                      border: Border.all(color: Colors.black87, width: 0.25),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (isPossible)
                          FadeTransition(
                            opacity: Tween<double>(begin: 0.4, end: 0.9).animate(_pulseController),
                            child: Container(color: Colors.lightBlue.withOpacity(0.28)),
                          ),
                        content,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }

  Widget _buildBottomPanel() {
    return Consumer<GameProvider>(builder: (context, g, _) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        color: Colors.grey[900],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dice
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(color: Colors.grey[850], borderRadius: BorderRadius.circular(8)),
                  child: Center(
                      child: Text(
                      g.diceResult == 0 ? '-' : g.diceResult.toString(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),

                // Buttons
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            textStyle: const TextStyle(fontSize: 14),
                          ),
                          onPressed: g.currentTurn == GameTurn.PLAYER && g.turnPhase == TurnPhase.ROLLING ? () { g.rollDice(); setState(() {}); } : null,
                          child: const Text('Lanzar Dado', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 6),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.tealAccent.shade700, 
                            foregroundColor: Colors.black, 
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          onPressed: g.currentTurn == GameTurn.PLAYER && g.echoCharges >= 6 ? () { g.activateEcho(); setState(() {}); } : null,
                          child: Text('Echo (${g.echoCharges}/6)', style: const TextStyle(fontFamily: 'monospace')),
                        ),
                      ],
                    ),
                  ),
                ),

                // Turn/pass info
                SizedBox(
                  width: 85,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        decoration: BoxDecoration(
                          color: g.currentTurn == GameTurn.PLAYER ? Colors.tealAccent.shade700 : Colors.redAccent.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          g.currentTurn == GameTurn.PLAYER ? 'Sujeto 7' : 'Resonancia', 
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (g.turnPhase == TurnPhase.MOVING && g.currentTurn == GameTurn.PLAYER)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[800],
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            textStyle: const TextStyle(fontSize: 10),
                          ),
                          onPressed: () { g.passTurn(); setState(() {}); },
                          child: const Text('Pasar', style: TextStyle(fontFamily: 'monospace')),
                        )
                      else
                        const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Status / hints
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Echo: ${g.echoActive ? 'ACTIVA' : 'INACTIVA'}', 
                    style: TextStyle(
                      fontFamily: 'monospace', 
                      fontSize: 10, 
                      color: g.echoActive ? Colors.tealAccent : Colors.white70
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Fichas: Enemigo & Salida', 
                    style: TextStyle(fontFamily: 'monospace', fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          ],
        ),
      );
    });
  }
}
