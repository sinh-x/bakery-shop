import 'package:flutter/material.dart';

import '../../../data/models/event_photo.dart';

/// Full-screen photo viewer for event photos.
///
/// Pages through [photos] with pinch-zoom via [InteractiveViewer]. Mirrors
/// the pattern of `OrderPhotoViewer` in
/// `features/orders/widgets/order_photo_section.dart` but is specific to
/// event photos (which carry no work-item tags).
///
/// The photo URL is constructed as `'$baseUrl/api/photos/{hash}.jpg'`,
/// matching the existing event photo serving convention.
class EventPhotoViewer extends StatefulWidget {
  const EventPhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.baseUrl,
  });

  final List<EventPhoto> photos;
  final int initialIndex;
  final String baseUrl;

  @override
  State<EventPhotoViewer> createState() => _EventPhotoViewerState();
}

class _EventPhotoViewerState extends State<EventPhotoViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${widget.photos.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photos.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (ctx, index) {
          final photo = widget.photos[index];
          final url = '${widget.baseUrl}/api/photos/${photo.photoHash}.jpg';
          return InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}