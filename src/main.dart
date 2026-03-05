import 'nlib.dart';

void main() {
  print("--- Basic Types ---");
  print("add(10, 20) = ${add(10, 20)}");
  print("greet('Antigravity') = ${greet('Antigravity')}");

  print("\n--- Sequences ---");
  print("getRange(5) = ${getRange(5)}");
  print("sum([1, 2, 3]) = ${sum([1, 2, 3])}");

  print("\n--- Nested Objects ---");
  final emp = createEmployer(101, 30);
  print("Employer's Secretary ID: ${emp.secretary.id}");
  print("Employer's Secretary Age: ${emp.secretary.age}");

  print("\n--- List of Objects ---");
  final players = getTopPlayers();
  for (var p in players) {
    print("Player ID: ${p.id}, Score: ${p.score}");
  }
}
