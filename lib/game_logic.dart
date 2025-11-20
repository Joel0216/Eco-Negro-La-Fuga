import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'models.dart';

class GameProvider with ChangeNotifier {
  final int rows = 21;
  final int cols = 21;

  late List<List<CellType>> _grid;
  late Position _playerPos;
  late Position _enemyPos;
  late Position _exitPos;

  GameStatus _gameStatus = GameStatus.LORE;
  GameTurn _currentTurn = GameTurn.PLAYER;
  TurnPhase _turnPhase = TurnPhase.ROLLING;
  int _diceResult = 0;
  int _echoCharges = 0;
  bool _isEchoActive = false;
  List<Position> _possibleMoves = [];

  List<List<CellType>> get grid => _grid;
  Position get playerPos => _playerPos;
  Position get enemyPos => _enemyPos;
  Position get exitPos => _exitPos;
  GameStatus get gameStatus => _gameStatus;
  GameTurn get currentTurn => _currentTurn;
  TurnPhase get turnPhase => _turnPhase;
  int get diceResult => _diceResult;
  int get echoCharges => _echoCharges;
  bool get isEchoActive => _isEchoActive;
  List<Position> get possibleMoves => _possibleMoves;

  GameProvider() {
    _initializeGame();
  }

  void _initializeGame() {
    _generateMaze();
    _playerPos = Position(1, 1);
    _enemyPos = Position(19, 19);
    _exitPos = Position(1, 19);
    _currentTurn = GameTurn.PLAYER;
    _turnPhase = TurnPhase.ROLLING;
    _gameStatus = GameStatus.LORE;
    _diceResult = 0;
    _echoCharges = 0;
    _isEchoActive = false;
    _possibleMoves = [];
    notifyListeners();
  }

  void startGame() {
    _gameStatus = GameStatus.PLAYING;
    notifyListeners();
  }
  
  void restartGame() {
    _initializeGame();
    startGame();
  }

  void _generateMaze() {
    _grid = List.generate(rows, (_) => List.filled(cols, CellType.WALL));
    final stack = <Position>[];
    final start = Position(1, 1);
    
    _grid[start.row][start.col] = CellType.PATH;
    stack.add(start);

    while (stack.isNotEmpty) {
      final current = stack.last;
      final neighbors = _getUnvisitedNeighbors(current);

      if (neighbors.isNotEmpty) {
        final next = neighbors[Random().nextInt(neighbors.length)];
        _removeWall(current, next);
        _grid[next.row][next.col] = CellType.PATH;
        stack.add(next);
      } else {
        stack.removeLast();
      }
    }
  }

  List<Position> _getUnvisitedNeighbors(Position pos) {
    final neighbors = <Position>[];
    for (var dr = -2; dr <= 2; dr += 4) {
      if (pos.row + dr > 0 && pos.row + dr < rows -1) {
        neighbors.add(Position(pos.row + dr, pos.col));
      }
    }
    for (var dc = -2; dc <= 2; dc += 4) {
      if (pos.col + dc > 0 && pos.col + dc < cols - 1) {
        neighbors.add(Position(pos.row, pos.col + dc));
      }
    }
    return neighbors.where((p) => _grid[p.row][p.col] == CellType.WALL).toList();
  }

  void _removeWall(Position current, Position next) {
    final dr = (next.row - current.row) ~/ 2;
    final dc = (next.col - current.col) ~/ 2;
    _grid[current.row + dr][current.col + dc] = CellType.PATH;
  }

  void rollDice() {
    if (_turnPhase != TurnPhase.ROLLING) return;
    _diceResult = Random().nextInt(6) + 1;
    _turnPhase = TurnPhase.MOVING;
    _calculatePossibleMoves();
    notifyListeners();
  }

  void _calculatePossibleMoves() {
    final startPos = (_currentTurn == GameTurn.PLAYER) ? _playerPos : _enemyPos;
    _possibleMoves = _bfs(startPos, _diceResult);
  }

  List<Position> _bfs(Position start, int steps) {
    final queue = <(Position, int)>[(start, 0)];
    final visited = {start};
    final possible = <Position>[];

    while (queue.isNotEmpty) {
      final (current, dist) = queue.removeAt(0);

      if (dist == steps) {
        possible.add(current);
        continue;
      }

      for (var neighbor in _getValidNeighbors(current)) {
        if (!visited.contains(neighbor)) {
          visited.add(neighbor);
          queue.add((neighbor, dist + 1));
        }
      }
    }
    return possible;
  }
  
  Iterable<Position> _getValidNeighbors(Position pos) {
    final neighbors = <Position>[];
    for (var d in [-1, 1]) {
      final newRow = pos.row + d;
      if (newRow >= 0 && newRow < rows && _grid[newRow][pos.col] == CellType.PATH) {
        neighbors.add(Position(newRow, pos.col));
      }
      final newCol = pos.col + d;
      if (newCol >= 0 && newCol < cols && _grid[pos.row][newCol] == CellType.PATH) {
        neighbors.add(Position(pos.row, newCol));
      }
    }
    return neighbors;
  }

  void move(Position newPos) {
    if (_turnPhase != TurnPhase.MOVING || !_possibleMoves.contains(newPos)) return;

    if (_currentTurn == GameTurn.PLAYER) {
      _playerPos = newPos;
      if (_playerPos == _exitPos) {
        _gameStatus = GameStatus.WIN;
      } else if (_playerPos == _enemyPos) {
        _gameStatus = GameStatus.LOSE;
      }
    } else {
      _enemyPos = newPos;
      if (_enemyPos == _playerPos) {
        _gameStatus = GameStatus.LOSE;
      }
    }
    _endTurn();
    notifyListeners();
  }

  void _endTurn() {
    if (_currentTurn == GameTurn.PLAYER) {
      if (_echoCharges < 6) _echoCharges++;
      _currentTurn = GameTurn.ENEMY;
    } else {
      _currentTurn = GameTurn.PLAYER;
    }
    _turnPhase = TurnPhase.ROLLING;
    _possibleMoves = [];
    _isEchoActive = false;
  }

  void activateEcho() {
    if (_currentTurn == GameTurn.PLAYER && _echoCharges >= 6) {
      _echoCharges = 0;
      _isEchoActive = true;
      notifyListeners();

      Timer(const Duration(seconds: 3), () {
        _isEchoActive = false;
        notifyListeners();
      });
    }
  }
}
