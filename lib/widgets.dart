import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'game_logic.dart';
import 'models.dart';

class BoardWidget extends StatelessWidget {
  const BoardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, game, child) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: game.cols,
          ),
          itemBuilder: (context, index) {
            final row = index ~/ game.cols;
            final col = index % game.cols;
            final pos = Position(row, col);
            return CellWidget(pos: pos);
          },
          itemCount: game.rows * game.cols,
        );
      },
    );
  }
}

class CellWidget extends StatefulWidget {
  final Position pos;
  const CellWidget({super.key, required this.pos});

  @override
  State<CellWidget> createState() => _CellWidgetState();
}

class _CellWidgetState extends State<CellWidget> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<Color?>? _animation;

  @override
  void initState() {
    super.initState();
    final game = context.read<GameProvider>();
    if (game.possibleMoves.contains(widget.pos)) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      )..repeat(reverse: true);
      _animation = ColorTween(
        begin: Colors.blue.withOpacity(0.5),
        end: Colors.blue.withOpacity(0.8),
      ).animate(_controller!);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final game = Provider.of<GameProvider>(context);
    final type = game.grid[widget.pos.row][widget.pos.col];

    bool isPlayer = game.playerPos == widget.pos;
    bool isEnemy = game.enemyPos == widget.pos;
    bool isExit = game.exitPos == widget.pos;
    bool isPossibleMove = game.possibleMoves.contains(widget.pos);

    bool showPlayer = isPlayer && (game.currentTurn == GameTurn.PLAYER || game.isEchoActive);
    bool showEnemy = isEnemy && (game.currentTurn == GameTurn.ENEMY || game.isEchoActive);
    bool showExit = isExit && game.isEchoActive;

    Color cellColor;
    if (type == CellType.WALL) {
      cellColor = Colors.grey[800]!;
    } else {
      cellColor = (widget.pos.row + widget.pos.col) % 2 == 0 ? Colors.grey[700]! : Colors.grey[600]!;
    }

    Widget? child;
    if (showPlayer) {
      child = const CircleAvatar(backgroundColor: Colors.teal, radius: 10);
    } else if (showEnemy) {
      child = const CircleAvatar(backgroundColor: Colors.red, radius: 10);
    } else if (showExit) {
      child = const Icon(Icons.exit_to_app, color: Colors.green);
    }
    
    return GestureDetector(
      onTap: () {
        if (isPossibleMove) {
          game.move(widget.pos);
        }
      },
      child: AnimatedBuilder(
        animation: _animation ?? const AlwaysStoppedAnimation(null),
        builder: (context, _) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              color: isPossibleMove ? _animation?.value : cellColor,
              border: Border.all(color: Colors.black26, width: 0.5),
            ),
            child: child != null ? Center(child: child) : null,
          );
        },
      ),
    );
  }
}
