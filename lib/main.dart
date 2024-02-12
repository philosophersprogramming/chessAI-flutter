import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: TakePictureScreen(
        camera: firstCamera,
      ),
    ),
  );
}

class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({
    super.key,
    required this.camera,
  });

  final CameraDescription camera;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class DisplayPictureScreen extends StatelessWidget {
  final String imagePath;
  final String result;

  const DisplayPictureScreen({
    super.key,
    required this.imagePath,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display the Picture')),
      body: Column(
        children: [
          Expanded(
            child: Image.file(File(imagePath)),
          ),
          _ResultWidget(imagePath: imagePath, result: result),
          ElevatedButton(
            onPressed: () {
              // Navigate back to TakePictureScreen when the "Back" button is pressed
              Navigator.pop(context);
            },
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }
}

class TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  late String _serverAddress;
  late TextEditingController _textController;
  String _imagePath = '';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
    );
     _initializeControllerFuture = _controller.initialize().catchError((error) {
      if (kDebugMode) {
        print("Error initializing camera: $error");
      }
      // Handle initialization error here
    });
    
    // Initialize text controller with the saved or default value
    _textController = TextEditingController();

    _loadServerAddress(); // Load saved server address
  }

  void _loadServerAddress() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      // Retrieve the saved server address or set default value if not available
      _serverAddress =
          prefs.getString('serverAddress') ?? 'http://100.86.35.113:9081';
      _textController.text = _serverAddress; // Update text controller
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _takePicture() async {
    _controller.setFlashMode(FlashMode.off);
    try {
      await _initializeControllerFuture;
      final image = await _controller.takePicture();

      if (!mounted) return;

      setState(() {
        _imagePath = image.path; // Save the path of the taken picture
      });

      // Display the image using a dialog
      await showDialog(
        context: _scaffoldKey.currentContext!,
        builder: (context) => AlertDialog(
          content: Image.file(File(_imagePath)),
          actions: [
            ElevatedButton(
              onPressed: () {
                // Close the dialog
                Navigator.pop(context);
              },
              child: const Text('Dismiss'),
            ),
            ElevatedButton(
              onPressed: () {
                // Close the dialog and send the request
                Navigator.pop(context);
                _sendRequest();
              },
              child: const Text('Send Request'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  void _sendRequest() async {
    if (_imagePath.isNotEmpty) {
      String result = await uploadImage(_imagePath);

      // Navigate to DisplayPictureScreen and pass the result
      Navigator.push(
        _scaffoldKey.currentContext!,
        MaterialPageRoute(
          builder: (context) => DisplayPictureScreen(
            imagePath: _imagePath,
            result: result,
          ),
        ),
      );
    }
  }

  void _showSettingsPopup() {
  showDialog(
    context: _scaffoldKey.currentContext!,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Settings'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Server Address'),
              TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  hintText: 'Type here',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Access the entered text using _textController.text
              _serverAddress = _textController.text;
              if (kDebugMode) {
                print('Entered text: $_serverAddress');
              }
              SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.setString('serverAddress', _serverAddress); // Save server address
              // ignore: use_build_context_synchronously
              Navigator.pop(context); // Close the dialog
            },
            child: const Text('Save'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close the dialog
            },
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Take a picture'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              _showSettingsPopup();
              //  Add logic for settings button
            },
          ),
          Row(
            children: [
              // Button on the opposite side of the camera button
              IconButton(
                icon:
                    const Icon(Icons.refresh), // Replace with your desired icon
                onPressed: () {
                  _onRefreshPressed();
                },
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return CameraPreview(_controller);
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _takePicture,
        child: const Icon(Icons.camera_alt),
      ),
    );
  }

  Future<String> uploadImage(String imagePath) async {
    var request =
        http.MultipartRequest('POST', Uri.parse('$_serverAddress/upload'));

    // Convert the image to bytes and create a MultipartFile with a .jpg file extension
    List<int> imageBytes = await File(imagePath).readAsBytes();
    http.MultipartFile imageFile =
        http.MultipartFile.fromBytes('file', imageBytes, filename: 'image.jpg');

    // Add the MultipartFile to the request
    request.files.add(imageFile);

    try {
      // Send the request
      http.StreamedResponse response = await request.send();

      if (response.statusCode == 200) {
        String responseBody = await response.stream.bytesToString();
        if (kDebugMode) {
          print('Response: $responseBody');
        }
        return responseBody;
      } else {
        if (kDebugMode) {
          print('Error: ${response.reasonPhrase}');
        }
        return 'Error: ${response.reasonPhrase}';
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error: $e');
      }
      return 'Error: $e';
    }
  }

  void _onRefreshPressed() async {
    // Send a POST request here
    String result = await sendRefreshRequest();
    // Handle the result as needed
    if (kDebugMode) {
      print('Refresh request result: $result');
    }
  }

  Future<String> sendRefreshRequest() async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_serverAddress/gamestat'),
      );
      request.fields.addAll({
        'reset': 'true',
      });

      http.StreamedResponse response = await request.send();

      if (response.statusCode == 200) {
        return await response.stream.bytesToString();
      } else {
        return 'Error: ${response.reasonPhrase}';
      }
    } catch (e) {
      return 'Error: $e';
    }
  }
}

class _ResultWidget extends StatefulWidget {
  final String imagePath;
  final String result;
  const _ResultWidget({required this.imagePath, required this.result});

  @override
  _ResultWidgetState createState() => _ResultWidgetState();
}

class _ResultWidgetState extends State<_ResultWidget> {
  @override
  Widget build(BuildContext context) {
    return Text(widget.result); // Display the result in a Text widget
  }
}
