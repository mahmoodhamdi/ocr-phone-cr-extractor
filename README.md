# OCR Phone & CR Extractor

A Flutter application that uses Optical Character Recognition (OCR) to automatically extract phone numbers and Commercial Registration (CR) numbers from images.

## Features

- **Image Selection**: Choose single or multiple images from the gallery
- **Automated Extraction**: Automatically extracts:
  - Phone numbers matching Saudi format (966XXXXXXXXX)
  - Commercial Registration numbers matching format (45XXXXXXXXXX)
- **Results Management**:
  - View extraction results with image thumbnails
  - Delete individual results
  - Clear all results
- **Export Functionality**: Export all extraction results to Excel file
- **Image Processing**: Uses smart cropping for more accurate CR number extraction

## Technology Stack

- **Flutter**: UI framework
- **Google ML Kit**: Text recognition and OCR capabilities
- **Image package**: Image processing and manipulation
- **Syncfusion Excel**: Excel file generation
- **Share Plus**: File sharing functionality

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Android Studio or VS Code with Flutter extensions
- Android device or emulator (Android 5.0+)
- iOS device or simulator (iOS 11.0+)

### Installation

1. Clone this repository:

```bash
git clone https://github.com/mahmoodhamdi/ocr-phone-cr-extractor.git
```

2. Navigate to the project directory:

```bash
cd ocr-phone-cr-extractor
```

3. Install dependencies:

```bash
flutter pub get
```

4. Run the app:

```bash
flutter run
```

### Configuration

For Android:

- Ensure the minimum SDK version in android/app/build.gradle is set to 21 or higher
- Add camera and storage permissions in AndroidManifest.xml

For iOS:

- Add camera and photo library usage descriptions in Info.plist
- Set minimum deployment target to iOS 11.0 in Xcode

## How It Works

1. The app uses the image_picker plugin to select images from the gallery
2. For each image, it runs Google ML Kit's text recognition in both Latin and Arabic scripts
3. It processes the recognized text using regular expressions to extract:
   - Phone numbers starting with "966" followed by 9 digits
   - CR numbers starting with "45" followed by 10 digits
4. For CR number extraction, it first crops the image to focus on the typical location of CR numbers
5. Results are displayed in a scrollable list with thumbnails and extracted information
6. Users can export results to an Excel file that includes file names, extracted data, and timestamps

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch `git checkout -b feature/amazing-feature`
3. Commit your changes `git commit -m 'Add some amazing feature'`
4. Push to the branch `git push origin feature/amazing-feature`
5. Open a Pull Request

## Acknowledgements

- [Google ML Kit](https://developers.google.com/ml-kit) for OCR capabilities
- [Flutter](https://flutter.dev) for the app framework

