import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:typed_data';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'package:rfid_scanner_c6/database_helper.dart';

class NetworkController extends GetxController {
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  var isSwitchedOn = false.obs; // Use RxBool for reactive updates
  var isConnected = false.obs;

  @override
  void onInit() {
    super.onInit();
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  @override
  void onClose() {
    _connectivitySubscription.cancel();
    super.onClose();
  }

  void _updateConnectionStatus(
      List<ConnectivityResult> connectivityResult) async {
    isSwitchedOn.value = connectivityResult.any((result) =>
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile);

    if (isSwitchedOn.value) {
      print("Connected");
    } else {
      print("Not connected");
    }

    if (isSwitchedOn.value) {
      try {
        final pingResult = await InternetAddress.lookup('www.example.com');
        isConnected.value =
            pingResult.isNotEmpty && pingResult[0].rawAddress.isNotEmpty;
        print("Could ping");
      } on SocketException catch (_) {
        isConnected.value = false;
        print("Could not ping");
      }
    } else {
      isConnected.value = false;
    }

    _manageSnackbar();
  }

  void _manageSnackbar() {
    if (!isSwitchedOn.value) {
      _showSnackbar('You Are Not Connected - Switch On Wifi/Cellular Data',
          Colors.red[400]!);
    } else if (!isConnected.value) {
      _showSnackbar('Your Network Is Unstable and Data Cannot Be Submitted',
          Color.fromARGB(255, 248, 174, 15)!);
    } else {
      Get.closeCurrentSnackbar();
      _retrySubmission();
    }
  }

  Future<void> deleteSubmissionBox(int submissionID) async {
    final boxName = submissionID.toString();
    await Hive.deleteBoxFromDisk(boxName);
  }

  Future<void> _retrySubmission() async {
    String _webhookUrl = 'http://ewaste.iis.com.na/api/entry';

    final dbHelper = DatabaseHelper();
    final submissions = await dbHelper.getSubmissions();

    if (isSwitchedOn.value) {
      for (final submission in submissions) {
        // Prepare the request based on submission data

        var currentSubmissionID = submission.id;

        var resubmissionRequest =
            http.MultipartRequest('POST', Uri.parse(_webhookUrl));
        resubmissionRequest.headers["Content-type"] = "multipart/form-data";

        resubmissionRequest.fields['contractorID'] =
            submission.contractorID.toString();
        resubmissionRequest.fields['latitude'] = submission.latitude.toString();
        resubmissionRequest.fields['longitude'] =
            submission.longitude.toString();
        resubmissionRequest.fields['town'] = submission.town;
        resubmissionRequest.fields['skipBarcode'] = submission.skipBarcode;
        resubmissionRequest.fields['timestamp'] =
            submission.timestamp.toIso8601String();

        final submissionBox =
            await Hive.openBox(currentSubmissionID.toString());

        if (submissionBox.isOpen) {
          // Variables to store the images
          List<File> imageFiles = [];

          for (var i = 1; i <= 6; i++) {
            final imageKey = 'imageBytes$i';
            final imageBytes = submissionBox.get(imageKey) as Uint8List?;
            if (imageBytes != null) {
              // Convert the image bytes back to File
              final directory = await getTemporaryDirectory();
              final imageFile =
                  File('${directory.path}/image_${submission.id}_$i.jpg');
              await imageFile.writeAsBytes(imageBytes);
              imageFiles.add(imageFile);
            }
          }

          for (var imageFile in imageFiles) {
            if (await imageFile.exists()) {
              var imageFileData = await http.MultipartFile.fromPath(
                'image${imageFiles.indexOf(imageFile) + 1}',
                imageFile.path,
                contentType: MediaType('image', 'jpeg'),
              );
              resubmissionRequest.files.add(imageFileData);
            }
          }

          try {
            var retryResponse = await resubmissionRequest.send();

            if (retryResponse.statusCode == 200) {
              // Success!
              _showQueueSnackbar('Your Queued Submissions Have Been Sent',
                  Color.fromARGB(255, 22, 111, 253)!);

              Get.closeCurrentSnackbar();

              print('Submission with ID: ${submission.id} resent successfully');

              await deleteSubmissionBox(submission.id);

              print('Hive box for submission ID: ${submission.id} deleted');

              // Delete all files within the directory
              for (var imageFile in imageFiles) {
                if (await imageFile.exists()) {
                  await imageFile.delete();
                }
              }

              print('Temporary image files deleted');

              // Optional: Delete the submission from the database if you no longer need it
              await dbHelper.deleteSubmission(submission.id);

              print('Failed submission cleared');
            } else {
              print(
                  'Submission with ID: ${submission.id} failed to resend. Status code: ${retryResponse.statusCode}');
            }
          } catch (e) {
            print('Error resending submission with ID: ${submission.id}: $e');
          }
        } else {
          print('Failed to open Hive box for submission ID: ${submission.id}');
          continue; // Skip to the next submission if box couldn't be opened
        }
      }
    }
  }

  void _showSnackbar(String message, Color backgroundColor) {
    Get.rawSnackbar(
      messageText: Text(
        message,
        style: TextStyle(color: Colors.white, fontSize: 14),
      ),
      isDismissible: false,
      duration: Duration(days: 1),
      backgroundColor: backgroundColor,
      icon: Icon(
        Icons.wifi_off,
        color: Colors.white,
        size: 30,
      ),
      margin: EdgeInsets.zero,
      snackStyle: SnackStyle.GROUNDED,
    );
  }

  void _showQueueSnackbar(String message, Color backgroundColor) {
    Get.rawSnackbar(
      messageText: Text(
        message,
        style: TextStyle(color: Colors.white, fontSize: 14),
      ),
      isDismissible: true,
      duration: Duration(seconds: 6),
      backgroundColor: backgroundColor,
      icon: Icon(
        Icons.upload_file,
        color: Colors.white,
        size: 30,
      ),
      margin: EdgeInsets.zero,
      snackStyle: SnackStyle.GROUNDED,
    );
  }
}
