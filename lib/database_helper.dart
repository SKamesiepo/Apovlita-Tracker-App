import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'failed_submissions.dart';

class DatabaseHelper {
  static const _databaseName = 'failed_submissions.db';
  static const _databaseVersion = 1;
  static const _tableName = 'failed_submissions';
  static const idColumn = 'id';

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);
    return await openDatabase(path,
        version: _databaseVersion, onCreate: _onCreate);
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE $_tableName (
      id INTEGER PRIMARY KEY NOT NULL,
      contractorID INTEGER NOT NULL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      town TEXT NOT NULL,
      skipBarcode TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      imageBytes1 BLOB,
      imageBytes2 BLOB,
      imageBytes3 BLOB,
      imageBytes4 BLOB,
      imageBytes5 BLOB,
      imageBytes6 BLOB
    )''');
  }

  Future<int> insertSubmission(FailedSubmission submission) async {
    final db = await database;
    int id = await db.insert(_tableName, submission.toMap());
    return id;
  }

  Future<List<FailedSubmission>> getSubmissions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_tableName);
    return List.generate(maps.length, (i) {
      return FailedSubmission(
          id: maps[i]['id'],
          contractorID: maps[i]['contractorID'],
          latitude: maps[i]['latitude'],
          longitude: maps[i]['longitude'],
          town: maps[i]['town'],
          skipBarcode: maps[i]['skipBarcode'],
          timestamp: DateTime.parse(maps[i]['timestamp']));
      // imageBytes1: maps[i]['imageBytes1'],
      // imageBytes2: maps[i]['imageBytes2'],
      // imageBytes3: maps[i]['imageBytes3'],
      // imageBytes4: maps[i]['imageBytes4'],
      // imageBytes5: maps[i]['imageBytes5'],
      // imageBytes6: maps[i]['imageBytes6']);
    });
  }

  Future<int> deleteSubmission(int id) async {
    final db = await database;
    return await db.delete(
      _tableName, // Name of your table
      where: '$idColumn = ?', // Assuming 'id' is your primary key column
      whereArgs: [id],
    );
  }
}
