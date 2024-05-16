import 'dart:typed_data';

class FailedSubmission {
  int id;
  int contractorID;
  double latitude;
  double longitude;
  String town;
  String skipBarcode;
  DateTime timestamp;
  Uint8List? imageBytes1;
  Uint8List? imageBytes2;
  Uint8List? imageBytes3;
  Uint8List? imageBytes4;
  Uint8List? imageBytes5;
  Uint8List? imageBytes6;

  FailedSubmission({
    required this.id,
    required this.contractorID,
    required this.latitude,
    required this.longitude,
    required this.town,
    required this.skipBarcode,
    required this.timestamp,
    // this.imageBytes1,
    // this.imageBytes2,
    // this.imageBytes3,
    // this.imageBytes4,
    // this.imageBytes5,
    // this.imageBytes6,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contractorID': contractorID,
      'latitude': latitude,
      'longitude': longitude,
      'town': town,
      'skipBarcode': skipBarcode,
      'timestamp': timestamp.toIso8601String(),
      // 'imageBytes1': imageBytes1,
      // 'imageBytes2': imageBytes2,
      // 'imageBytes3': imageBytes3,
      // 'imageBytes4': imageBytes4,
      // 'imageBytes5': imageBytes5,
      // 'imageBytes6': imageBytes6,
    };
  }
}
