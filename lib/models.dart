enum CellType { WALL, PATH }
enum GameTurn { PLAYER, ENEMY }
enum TurnPhase { ROLLING, MOVING }
enum GameStatus { LORE, PLAYING, WIN, LOSE }

class Position {
  final int row;
  final int col;

  Position(this.row, this.col);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Position &&
          runtimeType == other.runtimeType &&
          row == other.row &&
          col == other.col;

  @override
  int get hashCode => row.hashCode ^ col.hashCode;
}
