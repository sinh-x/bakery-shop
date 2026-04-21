import 'package:flutter/material.dart';

import '../../../data/models/knowledge_entry.dart';

/// Horizontal PageView photo gallery with dots indicator and tap-to-fullscreen.
class KnowledgePhotoGallery extends StatefulWidget {
  const KnowledgePhotoGallery({
    super.key,
    required this.photos,
    required this.baseUrl,
  });

  final List<KnowledgePhoto> photos;
  final String baseUrl;

  @override
  State<KnowledgePhotoGallery> createState() => _KnowledgePhotoGalleryState();
}

class _KnowledgePhotoGalleryState extends State<KnowledgePhotoGallery> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = 0;
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openFullScreen(int index) {
    showDialog(
      context: context,
      builder: (ctx) => _FullScreenViewer(
        photos: widget.photos,
        initialIndex: index,
        baseUrl: widget.baseUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.photos.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (ctx, index) {
              final photo = widget.photos[index];
              final url = '$baseUrl${photo.url}';
              return GestureDetector(
                onTap: () => _openFullScreen(index),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, e, s) => Container(
                    color: Colors.grey.shade200,
                    child: const Center(
                      child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Dots indicator
        if (widget.photos.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.photos.length,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index == _currentIndex
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade400,
                ),
              ),
            ),
          ),
        // Caption
        if (widget.photos.isNotEmpty && widget.photos[_currentIndex].caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            widget.photos[_currentIndex].caption,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }

  String get baseUrl => widget.baseUrl;
}

/// Full-screen swipeable viewer with zoom/pan.
class _FullScreenViewer extends StatefulWidget {
  const _FullScreenViewer({
    required this.photos,
    required this.initialIndex,
    required this.baseUrl,
  });

  final List<KnowledgePhoto> photos;
  final int initialIndex;
  final String baseUrl;

  @override
  State<_FullScreenViewer> createState() => _FullScreenViewerState();
}

class _FullScreenViewerState extends State<_FullScreenViewer> {
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
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (ctx, index) {
          final photo = widget.photos[index];
          final url = '${widget.baseUrl}${photo.url}';
          return Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, e, s) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                  ),
                ),
              ),
              if (photo.caption.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Text(
                      photo.caption,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
