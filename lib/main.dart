import 'dart:io';
import 'dart:core';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:api_cache_manager/api_cache_manager.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import 'package:rfid_scanner_c6/dependency_injection.dart';
import 'failed_submissions.dart';
import 'database_helper.dart';

final APICacheManager cacheManager = APICacheManager();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDocumentDir = await getApplicationDocumentsDirectory();
  Hive.init(appDocumentDir.path);

  HttpOverrides.global = MyHttpOverrides();
  runApp(const MyApp());
  DependencyInjection.init();
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Apóvilta Tracker',
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: Color.fromRGBO(47, 255, 0, 1)),
      ),
      home: const GeolocationApp(),
    );
  }
}

class GeolocationApp extends StatefulWidget {
  const GeolocationApp({super.key});

  @override
  State<GeolocationApp> createState() => _GeolocationAppState();
}

class _GeolocationAppState extends State<GeolocationApp> {
  static const platform = MethodChannel("com.example.rfid_scanner/channel");
  String _rfidValue = '';
  final TextEditingController barcodeController = TextEditingController();

  Position? _currentLocation;
  late bool servicePermission = false;
  late LocationPermission permission;
  bool _isLoading = false;
  bool _scanButtonVisible = true;
  bool _retryScanVisible = false;
  bool _captureImageVisible = false;
  bool _submitDetailsVisible = false;
  bool _captureImageButtonEnabled = false;
  bool _submitDetailsButtonEnabled = false;
  bool _rfidScanCompleted = false;
  bool _imagePickerActive = false; // Add this flag

  String _currentAddress = "Windhoek, Namibia";
  int contractorName = 1;
  String skipBarcode = '';

  List<Map<String, dynamic>> requestData = [];

  DateTime timestamp = DateTime.now();

  File? _image1;
  File? _image2;
  File? _image3;
  File? _image4;
  File? _image5;
  File? _image6;

  int _currentImageIndex = 0;
  int _imageCount = 0;
  final skipBarcodeKey = GlobalKey<FormFieldState>();
  List<http.StreamedResponse> failedResponses = [];

  String _webhookUrl = 'http://ewaste.iis.com.na/api/entry';

  Future<void> _scanRfidTag() async {
    setState(() {
      _isLoading = true;
      _scanButtonVisible = true;
      _retryScanVisible = false;
    });
    try {
      final String result = await platform.invokeMethod("scanTag");
      setState(() {
        _rfidValue = result;
        barcodeController.text =
            result; // Update the text field with the scanned RFID tag
        skipBarcode = result;
        _captureImageVisible = true;
        _submitDetailsVisible = false;
        _captureImageButtonEnabled = true;
        _submitDetailsButtonEnabled = true;
        _scanButtonVisible = false;
        _retryScanVisible = false;
        _rfidScanCompleted = true;
      });
    } catch (e) {
      // Handle the error appropriately
      print('Error retrieving RFID tag: ${e.toString()}');
      setState(() {
        barcodeController.text = 'Try Scanning Again';
        _retryScanVisible = true;
        _scanButtonVisible = false;
        _rfidScanCompleted = false;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    if (_imagePickerActive) return; // Prevent multiple image picker instances

    setState(() {
      _imagePickerActive = true;
    });

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024, // Set maximum width of the image
      maxHeight: 1024, // Set maximum height of the image
      imageQuality: 40, // Set the quality of the image (1-100)
    );

    setState(() {
      _imagePickerActive = false;
    });

    if (pickedFile != null) {
      setState(() {
        if (_currentImageIndex == 0) {
          _image1 = File(pickedFile.path);
          _imageCount++;
        } else if (_currentImageIndex == 1) {
          _image2 = File(pickedFile.path);
          _imageCount++;
        } else if (_currentImageIndex == 2) {
          _image3 = File(pickedFile.path);
          _imageCount++;
        } else if (_currentImageIndex == 3) {
          _image4 = File(pickedFile.path);
          _imageCount++;
        } else if (_currentImageIndex == 4) {
          _image5 = File(pickedFile.path);
          _imageCount++;
        } else if (_currentImageIndex == 5) {
          _image6 = File(pickedFile.path);
          _imageCount++;
        }

        // Update the index (with wrapping if we reach the end)
        _currentImageIndex = (_currentImageIndex + 1) % 6;
        _submitDetailsVisible = true; // Show the Submit Details button
        _submitDetailsButtonEnabled = true;
        if (_imageCount >= 6) {
          _captureImageButtonEnabled =
              false; // Disable capture image button after 3 images
        }
      });
    }
  }

  void _clearImages() {
    setState(() {
      _image1 = null;
      _image2 = null;
      _image3 = null;
      _image4 = null;
      _image5 = null;
      _image6 = null;
      _imageCount = 0;
      _currentImageIndex =
          0; // Reset _currentImageIndex to start from the first image slot
    });
  }

  void _clearBarcodeScanValue() {
    setState(() {
      barcodeController.text =
          'Please Scan Tag'; // Directly update the controller's text
      skipBarcode =
          'Please Scan Tag'; // Ensure your state variable is also updated if used elsewhere
    });
  }

  Future<bool> isConnected() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> _sendLocationData() async {
    var response;
    var request;

    _currentLocation = await _getCurrentLocation();

    timestamp = DateTime.now();

    request = http.MultipartRequest('POST', Uri.parse(_webhookUrl));
    request.headers["Content-type"] = "multipart/form-data";

    request.fields['contractorID'] = contractorName.toString();
    request.fields['latitude'] = _currentLocation?.latitude.toString() ?? '';
    request.fields['longitude'] = _currentLocation?.longitude.toString() ?? '';
    request.fields['town'] = _currentAddress;
    request.fields['skipBarcode'] = skipBarcode;
    request.fields['timestamp'] = timestamp.toIso8601String();

    if (_image1 != null) {
      var imageFile = await http.MultipartFile.fromPath('image1', _image1!.path,
          contentType: MediaType('image', 'jpeg'));
      request.files.add(imageFile);
    }
    if (_image2 != null) {
      var imageFile = await http.MultipartFile.fromPath('image2', _image2!.path,
          contentType: MediaType('image', 'jpeg'));
      request.files.add(imageFile);
    }
    if (_image3 != null) {
      var imageFile = await http.MultipartFile.fromPath('image3', _image3!.path,
          contentType: MediaType('image', 'jpeg'));
      request.files.add(imageFile);
    }
    if (_image4 != null) {
      var imageFile = await http.MultipartFile.fromPath('image4', _image4!.path,
          contentType: MediaType('image', 'jpeg'));
      request.files.add(imageFile);
    }
    if (_image5 != null) {
      var imageFile = await http.MultipartFile.fromPath('image5', _image5!.path,
          contentType: MediaType('image', 'jpeg'));
      request.files.add(imageFile);
    }
    if (_image6 != null) {
      var imageFile = await http.MultipartFile.fromPath('image6', _image6!.path,
          contentType: MediaType('image', 'jpeg'));
      request.files.add(imageFile);
    }

    try {
      response = await request.send();
      _resetButtonFlow();

      print("Request URL: ${request.url}");
      print("Request Headers: ${request.headers}");
      print("Request Fields: ${request.fields}");
      print("Request Files: ${request.files}");

      if (response.statusCode == 200) {
        Get.rawSnackbar(
            messageText: const Text('Your Data Has Been Submitted',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            isDismissible: true,
            duration: const Duration(seconds: 5),
            backgroundColor: const Color.fromARGB(255, 6, 136, 12),
            icon: const Icon(
              Icons.cloud_upload,
              color: Colors.white,
              size: 30,
            ),
            margin: EdgeInsets.zero,
            snackStyle: SnackStyle.GROUNDED);
        // Call reset here
      }
    } catch (e) {
      print('Error sending data: $e');

      // Save data locally
      final dbHelper = DatabaseHelper();
      final failedSubmission = FailedSubmission(
          id: generateSubmissionId(),
          contractorID: contractorName,
          latitude: _currentLocation!.latitude,
          longitude: _currentLocation!.longitude,
          town: _currentAddress,
          skipBarcode: skipBarcode,
          timestamp: timestamp);

      await dbHelper.insertSubmission(failedSubmission);
      var submissionId = failedSubmission.id;

      print('This is the id of submission $submissionId');

      final submissionBox = await Hive.openBox(failedSubmission.id.toString());

      submissionBox.clear();

      if (_image1 != null) {
        await submissionBox.put('imageBytes1', await _image1!.readAsBytes());
      }
      if (_image2 != null) {
        await submissionBox.put('imageBytes2', await _image2!.readAsBytes());
      }
      if (_image3 != null) {
        await submissionBox.put('imageBytes3', await _image3!.readAsBytes());
      }
      if (_image4 != null) {
        await submissionBox.put('imageBytes4', await _image4!.readAsBytes());
      }
      if (_image5 != null) {
        await submissionBox.put('imageBytes5', await _image5!.readAsBytes());
      }
      if (_image6 != null) {
        await submissionBox.put('imageBytes6', await _image6!.readAsBytes());
      }

      await printSubmissionBoxContents(submissionId);
      _resetButtonFlow(); // Call reset here
    }
  }

  Future<void> printSubmissionBoxContents(int submissionId) async {
    final submissionBox = await Hive.openBox(submissionId.toString());
    if (submissionBox.isOpen) {
      print('Hive box for submission ID $submissionId opened successfully.');
      print('Contents of the box:');

      // Print the contents of the box
      for (var i = 1; i <= 6; i++) {
        final imageKey = 'imageBytes$i';
        final imageBytes = submissionBox.get(imageKey);
        print('$imageKey: $imageBytes');
      }
    } else {
      print('Failed to open Hive box for submission ID $submissionId.');
    }
  }

  Future<Position> _getCurrentLocation() async {
    //Checks to see if permission is there to access location services
    servicePermission = await Geolocator.isLocationServiceEnabled();
    if (!servicePermission) {
      print("Service Disabled");
    }

    //Request For Acceptance of GeoLocation
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return await Geolocator.getCurrentPosition();
  }

  _getAddressFromCoordinates() async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
          _currentLocation!.latitude, _currentLocation!.longitude);

      Placemark place = placemarks[0];

      setState(() {
        _currentAddress = "Windhoek, Namibia";
      });
    } catch (e) {
      print(e);
    }
  }

  int generateSubmissionId() {
    final now = DateTime.now();

    // Format the date part (without separators)
    final dateString = DateFormat('ddmmy').format(now);

    final random = Random.secure();
    final randomValue = random.nextInt(1000);

    // Combine and parse as integer
    return int.parse('$dateString$randomValue');
  }

  void _resetButtonFlow() {
    setState(() {
      _scanButtonVisible = true;
      _retryScanVisible = false;
      _captureImageVisible = false;
      _submitDetailsVisible = false;
      _captureImageButtonEnabled = false;
      _submitDetailsButtonEnabled = false;
      _rfidScanCompleted = false;
      _imagePickerActive = false; // Reset the image picker flag
      _clearImages();
      _clearBarcodeScanValue();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize:
            const Size.fromHeight(90), // Adjust the height of the AppBar
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color.fromARGB(255, 108, 198, 126),
                  Color.fromARGB(255, 36, 170, 72)
                ], // Gradient colors
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
          ),
          toolbarHeight: 100,
          title: Row(
            mainAxisAlignment:
                MainAxisAlignment.center, // Center content vertically
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Image.asset(
                  'assets/apóvlita - logo.png',
                  height: 80, // Adjust the height of the image
                  width: 80, // Adjust the width of the image
                ),
              ),
              const Text(
                'Apóvlita Tracker',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 27.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      blurRadius: 10.0,
                      color: Colors.black54,
                      offset: Offset(2.0, 2.0),
                    ),
                  ],
                ),
              ),
            ],
          ),
          centerTitle: true,
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(8.0, 40.0, 8.0, 8.0), // Add top margin
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.center,
                child: TextFormField(
                  textAlign: TextAlign
                      .center, // Center the text within the TextFormField
                  decoration: const InputDecoration(
                    labelText: 'Epupa Cleaning Services',
                    labelStyle: TextStyle(
                      color: Colors.black, // Set the label text color to black
                      fontSize: 18.0, // Increase the font size
                    ),
                    border: OutlineInputBorder(), // Text before the input field
                    prefixIcon: Icon(Icons.person),
                  ),
                  enabled: false,
                ),
              ),
              const SizedBox(height: 16.0), // Add space between elements
              Image.asset(
                _rfidScanCompleted
                    ? 'assets/capture-images.png'
                    : 'assets/rfid-scan-image.png',
                height: 150, // Adjust the height of the image as needed
                width: 150, // Adjust the width of the image as needed
              ),
              const SizedBox(height: 16.0),
              Visibility(
                visible: _scanButtonVisible,
                child: ElevatedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : _scanRfidTag, // Start the scanning process
                  icon: _isLoading
                      ? const CircularProgressIndicator()
                      : const Icon(Icons.scanner, color: Colors.black),
                  label: _isLoading
                      ? const Text('')
                      : const Text(
                          'Scan',
                          style: TextStyle(
                            fontSize:
                                20.0, // Increase the font size of the button text
                            color: Colors.black, // Set the text color to black
                          ),
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors.green, // Set the background color to green
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 20), // Increase button size
                  ),
                ),
              ),
              Visibility(
                visible: _retryScanVisible,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _scanRfidTag, // Retry scanning
                  icon: _isLoading
                      ? const CircularProgressIndicator()
                      : const Icon(Icons.refresh),
                  label: Text(
                    _isLoading ? '' : 'Scan Failed: Retry Scan',
                    style: const TextStyle(
                      fontSize:
                          20.0, // Increase the font size of the button text
                      color: Colors.black, // Set the text color to black
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors.red, // Set the background color to red for retry
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 20), // Increase button size
                  ),
                ),
              ),
              const SizedBox(height: 8.0), // Add space between elements
              Offstage(
                offstage: true,
                child: TextFormField(
                  controller:
                      barcodeController, // Ensure this controller is initialized in your state class
                  decoration: const InputDecoration(
                    labelText: 'Skip Barcode',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      skipBarcode =
                          value; // Update skipBarcode with the value entered by the user
                    });
                  },
                  enabled: false,
                ),
              ),
              const SizedBox(height: 0.0),
              // Add space between elements
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.center, // Center the buttons horizontally
                children: [
                  if (_image1 != null)
                    Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Image.file(_image1!, height: 80, width: 80),
                    ),
                  if (_image2 != null)
                    Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Image.file(_image2!, height: 80, width: 80),
                    ),
                  if (_image3 != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.file(_image3!, height: 80, width: 80),
                    ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_image4 != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.file(_image4!, height: 80, width: 80),
                    ),
                  if (_image5 != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.file(_image5!, height: 80, width: 80),
                    ),
                  if (_image6 != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.file(_image6!, height: 80, width: 80),
                    ),
                ],
              ),

              const SizedBox(height: 8.0),

              Visibility(
                visible: _captureImageVisible,
                child: ElevatedButton.icon(
                  onPressed: _captureImageButtonEnabled
                      ? () {
                          _pickImage();
                          setState(() {
                            _submitDetailsVisible =
                                true; // Show the Submit Details button
                          });
                        }
                      : null,
                  icon: const Icon(Icons.camera, color: Colors.black),
                  label: const Text(
                    'Capture Images',
                    style: TextStyle(
                      fontSize:
                          20.0, // Increase the font size of the button text
                      color: Colors.black, // Set the text color to black
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors.green, // Set the background color to green
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 20), // Increase button size
                  ),
                ),
              ),
              const SizedBox(height: 8.0),
              // Add space between elements
              Visibility(
                visible: _submitDetailsVisible,
                child: ElevatedButton.icon(
                  onPressed: _submitDetailsButtonEnabled
                      ? () async {
                          setState(() {
                            _isLoading = true;
                          });

                          if (await isConnected()) {
                            await _initializeApp();
                            _currentLocation = await _getCurrentLocation();
                            await _getAddressFromCoordinates();
                            await _sendLocationData();

                            _clearImages();
                            _clearBarcodeScanValue();
                          }

                          setState(() {
                            _isLoading = false;
                          });
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _submitDetailsButtonEnabled
                        ? Colors.green
                        : Colors.grey,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 20), // Ensure same button size
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    "Submit Details",
                    style: TextStyle(
                      fontSize:
                          20.0, // Increase the font size of the button text
                      color: Colors.black, // Set the text color to black
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16.0),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initializeApp() async {
    // Check for location service and permission
    servicePermission = await Geolocator.isLocationServiceEnabled();
    if (!servicePermission) {
      print("Service Disabled");
      // Handle service disabled case
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      // Handle denied permission case
      if (permission == LocationPermission.denied) {
        return;
      }
    }
  }
}
