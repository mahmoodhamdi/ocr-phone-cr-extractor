import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:multi_image_picker_plus/multi_image_picker_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OCR Phone & CR Extractor',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const OCRScreen(),
    );
  }
}

class ResultItem {
  final String imagePath;
  final String phoneNumber;
  final String crNumber;
  final DateTime processedAt;

  ResultItem({
    required this.imagePath,
    required this.phoneNumber,
    required this.crNumber,
    required this.processedAt,
  });
}

class OCRScreen extends StatefulWidget {
  const OCRScreen({super.key});

  @override
  _OCRScreenState createState() => _OCRScreenState();
}

class _OCRScreenState extends State<OCRScreen> {
  List<ResultItem> results = [];
  bool isProcessing = false;

  final ImagePicker _picker = ImagePicker();
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final arabicTextRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  /// 📌 اختيار صورة واحدة من المعرض
  Future<void> _pickSingleImage() async {
    setState(() {
      isProcessing = true;
    });

    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile != null) {
      await _processImage(File(pickedFile.path));
    }

    setState(() {
      isProcessing = false;
    });
  }

  /// 📌 اختيار صور متعددة من المعرض
  Future<void> _pickMultipleImages() async {
    setState(() {
      isProcessing = true;
    });

    final List<XFile> pickedFiles = await _picker.pickMultiImage();

    if (pickedFiles.isNotEmpty) {
      for (var file in pickedFiles) {
        await _processImage(File(file.path));
      }
    }

    setState(() {
      isProcessing = false;
    });
  }

  bool isPickerActive = false; // Track if the picker is active

  /// 📌 اختيار صور متعددة من المعرض باستخدام multi_image_picker_plus مع التعامل مع الأذونات
  Future<void> _pickMultipleImagess() async {
    if (isPickerActive) {
      print("Image picker is already active, please wait...");
      return; // Prevent triggering the picker while it's already active
    }

    setState(() {
      isProcessing = true;
      isPickerActive = true; // Mark picker as active
    });

    // First, request storage permission
    var storagePermission = await Permission.storage.request();

    // If storage permission is granted, proceed to camera permission (if needed)
    if (storagePermission.isGranted) {
      var cameraPermission = await Permission.camera.request();

      if (cameraPermission.isGranted) {
        try {
          // Pick multiple images from the gallery
          final List<Asset> pickedAssets = await MultiImagePicker.pickImages(

            selectedAssets: [], // Optional: specify pre-selected assets
            androidOptions: AndroidOptions(
              maxImages: 500,
              actionBarTitle:
                  "Select Images", // Optional: change the action bar title
              allViewTitle:
                  "All Photos", // Optional: change the all photos view title
            ),
          );

          if (pickedAssets.isNotEmpty) {
            for (var asset in pickedAssets) {
              // Convert the asset to a File
              final file = await _getFileFromAsset(asset);
              await _processImage(file);
            }
          }
        } catch (e) {
          print("Error picking images: $e");
        }
      } else {
        print(
          "Camera permission is denied. Please grant permission to continue.",
        );
      }
    } else {
      print(
        "Storage permission is denied. Please grant permission to continue.",
      );
    }

    setState(() {
      isProcessing = false;
      isPickerActive = false; // Mark picker as inactive once it's finished
    });
  }

  /// Function to convert Asset to File
  Future<File> _getFileFromAsset(Asset asset) async {
    final byteData = await asset.getByteData();
    final buffer = byteData.buffer.asUint8List();
    final filePath = '${(await getTemporaryDirectory()).path}/${asset.name}';
    final file = File(filePath)..writeAsBytesSync(buffer);
    return file;
  }

  /// 📌 معالجة صورة واستخراج البيانات منها
  Future<void> _processImage(File imageFile) async {
    try {
      String phone = await _extractPhoneNumber(imageFile);
      String cr = await _extractCRNumber(imageFile);

      setState(() {
        results.add(
          ResultItem(
            imagePath: imageFile.path,
            phoneNumber: phone,
            crNumber: cr,
            processedAt: DateTime.now(),
          ),
        );
      });
    } catch (e) {
      log("⚠️ خطأ أثناء معالجة الصورة: $e");
    }
  }

  /// 📌 استخراج رقم الهاتف من الصورة
  Future<String> _extractPhoneNumber(File imageFile) async {
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);

      /// ✅ تشغيل OCR على الصورة الأصلية
      final RecognizedText recognizedText = await textRecognizer.processImage(
        inputImage,
      );
      final RecognizedText recognizedArabicText = await arabicTextRecognizer
          .processImage(inputImage);

      /// 🔍 استخراج النصوص وتحليلها
      String fullText = "${recognizedText.text} ${recognizedArabicText.text}";
      fullText = fullText.replaceAll(RegExp(r'[^0-9]'), '');

      /// 🏷️ البحث عن رقم الهاتف بصيغة (966XXXXXXXXX)
      RegExp phoneRegExp = RegExp(r'966\d{9}');
      RegExpMatch? phoneMatch = phoneRegExp.firstMatch(fullText);

      return phoneMatch?.group(0) ?? "غير موجود";
    } catch (e) {
      log("⚠️ خطأ أثناء استخراج رقم الهاتف: $e");
      return "خطأ في المعالجة";
    }
  }

  /// 📌 قص جزء معين من الصورة
  Future<File> _cropImage(File imageFile) async {
    final Uint8List imageBytes = await imageFile.readAsBytes();
    img.Image? originalImage = img.decodeImage(imageBytes);

    if (originalImage == null) return imageFile;

    int w = originalImage.width;
    int h = originalImage.height;

    /// ✅ تحديد منطقة القص (يمين الصورة - الجزء العلوي)
    img.Image croppedImage = img.copyCrop(
      originalImage,
      x: w - 300,
      y: 0,
      width: 300,
      height: 100,
    );

    /// 🔽 حفظ الصورة بعد القص
    final File croppedFile = File('${imageFile.path}_cropped.png');
    await croppedFile.writeAsBytes(img.encodePng(croppedImage));

    return croppedFile;
  }

  /// 📌 استخراج رقم السجل التجاري بعد قص الصورة
  Future<String> _extractCRNumber(File imageFile) async {
    try {
      final File croppedFile = await _cropImage(imageFile);
      final inputImage = InputImage.fromFilePath(croppedFile.path);

      /// ✅ تشغيل OCR على الجزء المقصوص فقط
      final RecognizedText recognizedText = await textRecognizer.processImage(
        inputImage,
      );
      final RecognizedText recognizedArabicText = await arabicTextRecognizer
          .processImage(inputImage);

      /// 🔍 استخراج النصوص وتحليلها
      String fullText = "${recognizedText.text} ${recognizedArabicText.text}";
      fullText = fullText.replaceAll(RegExp(r'[^0-9]'), '');

      /// 🏷️ البحث عن رقم السجل التجاري بصيغة (45XXXXXXXXXX)
      RegExp crRegExp = RegExp(r'4[2-8]\d{10}');

      RegExpMatch? crMatch = crRegExp.firstMatch(fullText);

      return crMatch?.group(0) ?? "غير موجود";
    } catch (e) {
      log("⚠️ خطأ أثناء استخراج رقم السجل التجاري: $e");
      return "خطأ في المعالجة";
    }
  }

  /// 📌 تصدير النتائج إلى ملف CSV

  /// 📌 تصدير النتائج إلى ملف Excel
  Future<void> _exportToExcel() async {
    if (results.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("لا توجد نتائج للتصدير")));
      return;
    }

    try {
      // إنشاء ملف Excel
      final xls.Workbook workbook = xls.Workbook();
      final xls.Worksheet sheet = workbook.worksheets[0];

      // إضافة عناوين الأعمدة
      sheet.getRangeByName('A1').setText('الرقم');
      sheet.getRangeByName('B1').setText('اسم الملف');
      sheet.getRangeByName('C1').setText('رقم الهاتف');
      sheet.getRangeByName('D1').setText('رقم السجل التجاري');
      sheet.getRangeByName('E1').setText('تاريخ المعالجة');

      // إضافة البيانات
      for (int i = 0; i < results.length; i++) {
        final item = results[i];
        String fileName = item.imagePath.split('/').last;
        sheet.getRangeByIndex(i + 2, 1).setNumber(i + 1);
        sheet.getRangeByIndex(i + 2, 2).setText(fileName);
        sheet.getRangeByIndex(i + 2, 3).setText(item.phoneNumber);
        sheet.getRangeByIndex(i + 2, 4).setText(item.crNumber);
        sheet
            .getRangeByIndex(i + 2, 5)
            .setText(
              '${item.processedAt.day}/${item.processedAt.month}/${item.processedAt.year} ${item.processedAt.hour}:${item.processedAt.minute}',
            );
      }

      // حفظ الملف
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/ocr_results_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final File file = File(path);
      await file.writeAsBytes(bytes, flush: true);

      // مشاركة الملف
      await Share.shareXFiles([
        XFile(path),
      ], text: 'نتائج استخراج البيانات من الصور');

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("تم تصدير البيانات بنجاح")));
    } catch (e) {
      log("⚠️ خطأ أثناء تصدير البيانات: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("حدث خطأ أثناء تصدير البيانات")),
      );
    }
  }

  /// 📌 حذف جميع النتائج
  void _clearResults() {
    setState(() {
      results.clear();
    });
  }

  @override
  void dispose() {
    textRecognizer.close();
    arabicTextRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text("رقم الهاتف والسجل التجاري"),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: results.isEmpty ? null : _clearResults,
              tooltip: "مسح النتائج",
            ),
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: results.isEmpty ? null : _exportToExcel,
              tooltip: "تصدير إلى CSV",
            ),
          ],
        ),
        body: Column(
          children: [
            // أزرار الإجراءات
            ElevatedButton.icon(
              onPressed: isProcessing ? null : _pickSingleImage,
              icon: const Icon(Icons.image),
              label: const Text("اختيار صورة واحدة"),
            ),

            ElevatedButton.icon(
              onPressed: isProcessing ? null : _pickMultipleImagess,
              icon: const Icon(Icons.photo_library),
              label: const Text("اختيار عدد كبير من الصور"),
            ),
            ElevatedButton.icon(
              onPressed: isProcessing ? null : _pickMultipleImages,
              icon: const Icon(Icons.photo_library),
              label: const Text("اختيار عدة صور بحد أقصى 100 صوره"),
            ),
            // مؤشر التحميل
            if (isProcessing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text("جاري معالجة الصور..."),
                  ],
                ),
              ),

            // عرض النتائج
            Expanded(
              child:
                  results.isEmpty
                      ? const Center(
                        child: Text(
                          "لم يتم معالجة أي صور بعد",
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                      : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final item = results[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  // صورة مصغرة
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8.0),
                                    child: Image.file(
                                      File(item.imagePath),
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // بيانات الاستخراج
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "صورة ${index + 1}",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          "📞 رقم الهاتف: ${item.phoneNumber}",
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "🏢 رقم السجل التجاري: ${item.crNumber}",
                                        ),
                                      ],
                                    ),
                                  ),
                                  // زر حذف النتيجة
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        results.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
