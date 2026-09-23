// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

void registerPdfViewFactory(String viewType, String url) {
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final iframe = html.IFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.overflow = 'auto'
      ..style.display = 'block'; // Ensure block display to fill container
    iframe.setAttribute('scrolling', 'yes');
    return iframe;
  });
}

void registerYoutubeViewFactory(String viewType, String url, {bool autoPlay = false}) {
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final iframe = html.IFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allowFullscreen = true
      ..allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture';
    return iframe;
  });
}

void registerVideoViewFactory(String viewType, String url) {
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final video = html.VideoElement()
      ..src = url
      ..autoplay = false
      ..loop = false
      ..controls = true
      ..style.objectFit = 'contain'
      ..style.width = '100%'
      ..style.height = '100%';
    video.setAttribute('playsinline', 'true');
    return video;
  });
}

void registerPdfObjectViewFactory(String viewType, String url) {
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final element = html.ObjectElement()
      ..data = url
      ..type = 'application/pdf'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
    return element;
  });
}

void registerPdfCanvasViewFactory(String viewType, String url) {
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final host = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.overflow = 'hidden'
      ..style.backgroundColor = '#202124';
    final canvas = html.CanvasElement()
      ..style.display = 'block'
      ..style.margin = 'auto'
      ..style.maxWidth = '100%'
      ..style.maxHeight = '100%';
    host.append(canvas);

    Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      try {
        if (host.clientWidth <= 0 || host.clientHeight <= 0) return;
        final pdfjs = globalContext['pdfjsLib'];
        if (pdfjs == null) return;
        timer.cancel();
        final loadingTask = (pdfjs as JSObject).callMethod<JSAny?>('getDocument'.toJS, url.toJS) as JSObject;
        final document = await (loadingTask['promise'] as JSPromise).toDart;
        final pagePromise = (document as JSObject).callMethod<JSAny?>('getPage'.toJS, 1.toJS) as JSPromise;
        final page = await pagePromise.toDart;
        final pageObject = page as JSObject;
        final baseViewport = pageObject.callMethod<JSAny?>('getViewport'.toJS, {'scale': 1}.jsify()) as JSObject;
        final pageWidth = (baseViewport['width'] as JSNumber).toDartDouble;
        final pageHeight = (baseViewport['height'] as JSNumber).toDartDouble;
        final availableWidth = host.clientWidth.toDouble() - 16;
        final availableHeight = host.clientHeight.toDouble() - 16;
        final scale = (availableWidth / pageWidth).clamp(0.05, availableHeight / pageHeight);
        final viewport = pageObject.callMethod<JSAny?>('getViewport'.toJS, {'scale': scale}.jsify()) as JSObject;
        canvas.width = ((viewport['width'] as JSNumber).toDartDouble).round();
        canvas.height = ((viewport['height'] as JSNumber).toDartDouble).round();
        canvas.style.width = '${canvas.width}px';
        canvas.style.height = '${canvas.height}px';
        final renderTask = pageObject.callMethod<JSAny?>('render'.toJS, {
          'canvasContext': canvas.context2D,
          'viewport': viewport,
        }.jsify()) as JSObject;
        await (renderTask['promise'] as JSPromise).toDart;
      } catch (_) {
        timer.cancel();
      }
    });
    return host;
  });
}
