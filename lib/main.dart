import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
// Removed problematic multi_image_picker_plus - using alternative
import 'package:file_picker/file_picker.dart';
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
  int totalImages = 0;
  int processedImages = 0;

  final ImagePicker _picker = ImagePicker();
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final arabicTextRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  bool isPickerActive = false;

  /// 📌 اختيار صورة واحدة من المعرض
  Future<void> _pickSingleImage() async {
    if (isPickerActive) {
      _showProcessingMessage();
      return;
    }

    try {
      setState(() {
        isProcessing = true;
        isPickerActive = true;
        totalImages = 1;
        processedImages = 0;
      });

      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85, // Reduce quality to prevent memory issues
      );

      if (pickedFile != null && mounted) {
        await _processImage(File(pickedFile.path));
      }
    } catch (e) {
      _handleError("خطأ في اختيار الصورة", e);
    } finally {
      if (mounted) {
        setState(() {
          isProcessing = false;
          isPickerActive = false;
        });
      }
    }
  }

  /// 📌 اختيار صور متعددة من المعرض
  Future<void> _pickMultipleImages() async {
    if (isPickerActive) {
      _showProcessingMessage();
      return;
    }

    try {
      setState(() {
        isProcessing = true;
        isPickerActive = true;
      });

      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        imageQuality: 85,
        limit: 50, // Set reasonable limit
      );

      if (pickedFiles.isNotEmpty && mounted) {
        setState(() {
          totalImages = pickedFiles.length;
          processedImages = 0;
        });

        for (var file in pickedFiles) {
          if (!mounted) break;
          try {
            await _processImage(File(file.path));
          } catch (e) {
            log("Error processing file ${file.path}: $e");
            setState(() {
              processedImages++;
            });
          }
        }
      }
    } catch (e) {
      _handleError("خطأ في اختيار الصور المتعددة", e);
    } finally {
      if (mounted) {
        setState(() {
          isProcessing = false;
          isPickerActive = false;
        });
      }
    }
  }

  /// 📌 اختيار صور متعددة باستخدام File Picker (بديل آمن)
  Future<void> _pickUnlimitedImages({bool selectAll = false}) async {
    if (isPickerActive) {
      _showProcessingMessage();
      return;
    }

    // Request permissions first
    await _requestPermissions();

    try {
      setState(() {
        isProcessing = true;
        isPickerActive = true;
      });

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp', 'gif'],
      );

      if (result != null && result.files.isNotEmpty && mounted) {
        List<File> imageFiles =
            result.files
                .where((file) => file.path != null)
                .map((file) => File(file.path!))
                .toList();

        if (imageFiles.isNotEmpty) {
          setState(() {
            totalImages = imageFiles.length;
            processedImages = 0;
          });

          // Show batch processing dialog for large selections
          if (imageFiles.length > 50) {
            bool? processBatch = await _showBatchProcessingDialog(
              imageFiles.length,
            );
            if (processBatch == false || processBatch == null) {
              setState(() {
                isProcessing = false;
                isPickerActive = false;
              });
              return;
            }
          }

          // Process images with error handling
          for (var file in imageFiles) {
            if (!mounted) break;
            try {
              await _processImage(file);
            } catch (e) {
              log("Error processing file ${file.path}: $e");
              setState(() {
                processedImages++;
              });
            }
          }
        }
      }
    } catch (e) {
      _handleError("خطأ في اختيار الصور", e);
    } finally {
      if (mounted) {
        setState(() {
          isProcessing = false;
          isPickerActive = false;
        });
      }
    }
  }

  /// Request necessary permissions
  Future<void> _requestPermissions() async {
    try {
      if (Platform.isAndroid) {
        var storagePermission = await Permission.storage.request();
        var photosPermission = await Permission.photos.request();
        var mediaLibraryPermission = await Permission.mediaLibrary.request();

        if (!storagePermission.isGranted &&
            !photosPermission.isGranted &&
            !mediaLibraryPermission.isGranted) {
          _showErrorSnackBar("يرجى منح الإذن للوصول إلى الصور");
        }
      }
    } catch (e) {
      log("Permission request error: $e");
    }
  }

  /// Show processing message
  void _showProcessingMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("يرجى انتظار انتهاء العملية السابقة")),
    );
  }

  /// Handle errors consistently
  void _handleError(String message, dynamic error) {
    log("$message: $error");
    if (mounted) {
      _showErrorSnackBar("$message: ${error.toString()}");
    }
  }

  /// Show error snackbar
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show batch processing dialog for very large selections
  Future<bool?> _showBatchProcessingDialog(int imageCount) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("معالجة مجموعية"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("لقد اخترت $imageCount صورة."),
              const SizedBox(height: 12),
              const Text("تحذير: معالجة عدد كبير من الصور قد:"),
              const SizedBox(height: 8),
              const Text("• تستغرق وقتاً طويلاً"),
              const Text("• تستهلك ذاكرة كبيرة"),
              const Text("• قد تتسبب في توقف التطبيق"),
              const SizedBox(height: 12),
              const Text("يُنصح بمعالجة أقل من 50 صورة في المرة الواحدة."),
            ],
          ),
          actions: [
            TextButton(
              child: const Text("إلغاء"),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text("المتابعة"),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
  }

  /// 📌 معالجة صورة واستخراج البيانات منها
  Future<void> _processImage(File imageFile) async {
    try {
      // Verify file exists and is readable
      if (!await imageFile.exists()) {
        throw Exception("الملف غير موجود");
      }

      String phone = await _extractPhoneNumber(imageFile);
      String cr = await _extractCRNumber(imageFile);

      if (mounted) {
        setState(() {
          results.add(
            ResultItem(
              imagePath: imageFile.path,
              phoneNumber: phone,
              crNumber: cr,
              processedAt: DateTime.now(),
            ),
          );
          processedImages++;
        });
      }
    } catch (e) {
      log("⚠️ خطأ أثناء معالجة الصورة: $e");
      if (mounted) {
        setState(() {
          processedImages++;
        });
      }
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
    try {
      final Uint8List imageBytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) return imageFile;

      int w = originalImage.width;
      int h = originalImage.height;

      // Ensure crop dimensions are within image bounds
      int cropWidth = (w > 300) ? 300 : w;
      int cropHeight = (h > 100) ? 100 : h;
      int startX = (w > 300) ? w - 300 : 0;

      /// ✅ تحديد منطقة القص (يمين الصورة - الجزء العلوي)
      img.Image croppedImage = img.copyCrop(
        originalImage,
        x: startX,
        y: 0,
        width: cropWidth,
        height: cropHeight,
      );

      /// 🔽 حفظ الصورة بعد القص
      final tempDir = await getTemporaryDirectory();
      final fileName = imageFile.path.split('/').last;
      final File croppedFile = File('${tempDir.path}/${fileName}_cropped.png');
      await croppedFile.writeAsBytes(img.encodePng(croppedImage));

      return croppedFile;
    } catch (e) {
      log("Error cropping image: $e");
      return imageFile; // Return original if crop fails
    }
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

      /// 🏷️ البحث عن رقم السجل التجاري بصيغة (4[2-8]XXXXXXXXXX)
      RegExp crRegExp = RegExp(r'4[2-8]\d{10}');
      RegExpMatch? crMatch = crRegExp.firstMatch(fullText);

      return crMatch?.group(0) ?? "غير موجود";
    } catch (e) {
      log("⚠️ خطأ أثناء استخراج رقم السجل التجاري: $e");
      return "خطأ في المعالجة";
    }
  }

  /// 📌 تصدير النتائج إلى ملف Excel
  Future<void> _exportToExcel() async {
    if (results.isEmpty) {
      _showErrorSnackBar("لا توجد نتائج للتصدير");
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("تم تصدير البيانات بنجاح"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _handleError("خطأ أثناء تصدير البيانات", e);
    }
  }

  /// 📌 حذف جميع النتائج
  void _clearResults() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("تأكيد الحذف"),
          content: const Text("هل أنت متأكد من حذف جميع النتائج؟"),
          actions: [
            TextButton(
              child: const Text("إلغاء"),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text("حذف", style: TextStyle(color: Colors.red)),
              onPressed: () {
                setState(() {
                  results.clear();
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
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
              tooltip: "تصدير إلى Excel",
            ),
          ],
        ),
        body: Column(
          children: [
            // أزرار الإجراءات
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isProcessing ? null : _pickSingleImage,
                          icon: const Icon(Icons.image),
                          label: const Text("صورة واحدة"),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isProcessing ? null : _pickMultipleImages,
                          icon: const Icon(Icons.photo_library),
                          label: const Text("عدة صور"),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          isProcessing
                              ? null
                              : () => _pickUnlimitedImages(selectAll: false),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text("عدد كبير من الصور (آمن)"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // مؤشر التحميل مع التفاصيل
            if (isProcessing)
              Container(
                padding: const EdgeInsets.all(16.0),
                margin: const EdgeInsets.symmetric(horizontal: 16.0),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      "جاري معالجة الصور...",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (totalImages > 0)
                      Column(
                        children: [
                          Text(
                            "$processedImages من $totalImages صورة",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value:
                                totalImages > 0
                                    ? processedImages / totalImages
                                    : 0,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.blue.shade600,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

            // إحصائيات سريعة
            if (results.isNotEmpty && !isProcessing)
              Container(
                margin: const EdgeInsets.all(16.0),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          "${results.length}",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                        Text(
                          "إجمالي الصور",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          "${results.where((r) => r.phoneNumber != "غير موجود" && r.phoneNumber != "خطأ في المعالجة").length}",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                        Text(
                          "أرقام هاتف",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          "${results.where((r) => r.crNumber != "غير موجود" && r.crNumber != "خطأ في المعالجة").length}",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                        Text(
                          "سجلات تجارية",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            // عرض النتائج
            Expanded(
              child:
                  results.isEmpty
                      ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.photo_library_outlined,
                              size: 80,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              "لم يتم معالجة أي صور بعد",
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              "اختر الصور من الأزرار أعلاه للبدء",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final item = results[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 4.0,
                            ),
                            elevation: 2,
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
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) {
                                        return Container(
                                          width: 80,
                                          height: 80,
                                          color: Colors.grey.shade300,
                                          child: const Icon(
                                            Icons.error_outline,
                                            color: Colors.red,
                                          ),
                                        );
                                      },
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
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.phone,
                                              size: 16,
                                              color:
                                                  item.phoneNumber ==
                                                          "غير موجود"
                                                      ? Colors.red
                                                      : Colors.green,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                "رقم الهاتف: ${item.phoneNumber}",
                                                style: TextStyle(
                                                  color:
                                                      item.phoneNumber ==
                                                              "غير موجود"
                                                          ? Colors.red
                                                          : Colors.black87,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.business,
                                              size: 16,
                                              color:
                                                  item.crNumber == "غير موجود"
                                                      ? Colors.red
                                                      : Colors.green,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                "السجل التجاري: ${item.crNumber}",
                                                style: TextStyle(
                                                  color:
                                                      item.crNumber ==
                                                              "غير موجود"
                                                          ? Colors.red
                                                          : Colors.black87,
                                                ),
                                              ),
                                            ),
                                          ],
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
