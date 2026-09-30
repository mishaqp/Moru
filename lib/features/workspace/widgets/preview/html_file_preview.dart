import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/segmented_tabs.dart';

import 'code_file_preview.dart';
import 'preview_states.dart';
import 'preview_file_server.dart';

class HtmlFilePreview extends StatefulWidget {
  const HtmlFilePreview({
    super.key,
    required this.file,
    this.sourceFile,
    this.accessRoot,
    this.autoLoad = true,
  });

  final File file;
  final File? sourceFile;
  final String? accessRoot;
  final bool autoLoad;

  @override
  HtmlFilePreviewState createState() => HtmlFilePreviewState();
}

class HtmlFilePreviewState extends State<HtmlFilePreview> {
  WebViewController? _controller;
  PreviewFileServer? _server;
  final Set<Future<void>> _initializations = {};
  int _generation = 0;
  Future<void> _serverClosed = Future.value();

  @visibleForTesting
  Future<void> get serverClosed => _serverClosed;
  @visibleForTesting
  Uri? get renderedUri => _server?.uri;
  Object? _error;
  bool _showSource = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      unawaited(load());
    } else {
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(HtmlFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.sourceFile?.path != widget.sourceFile?.path ||
        oldWidget.accessRoot != widget.accessRoot ||
        oldWidget.autoLoad != widget.autoLoad) {
      if (widget.autoLoad) {
        unawaited(load());
      } else {
        _generation++;
        unawaited(_server?.close());
        _server = null;
      }
    }
  }

  Future<void> load() {
    if (!mounted) return Future.value();
    final task = _init(++_generation);
    _initializations.add(task);
    unawaited(task.whenComplete(() => _initializations.remove(task)));
    return task;
  }

  bool _current(int generation) => mounted && generation == _generation;

  Future<void> _init(int generation) async {
    final previous = _server;
    _server = null;
    setState(() {
      _loading = true;
      _controller = null;
      _error = null;
    });
    PreviewFileServer? owned;
    try {
      await previous?.close();
      if (!_current(generation)) return;
      final original = widget.sourceFile ?? widget.file;
      owned = await PreviewFileServer.start(
        sourceFile: original,
        accessRoot: widget.accessRoot ?? original.parent.path,
      );
      if (!_current(generation)) return;
      _server = owned;
      final controller = WebViewController();
      final platform = controller.platform;
      if (platform is AndroidWebViewController) {
        await platform.setAllowFileAccess(false);
        await platform.setAllowContentAccess(false);
      }
      if (!_current(generation)) return;
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return uri != null &&
                    (uri.scheme == 'http' || uri.scheme == 'https')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (!_current(generation)) return;
      await controller.loadRequest(owned.uri);
      if (!_current(generation)) return;
      setState(() {
        _controller = controller;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (_current(generation)) {
        // Capability URLs must never become error text or logs.
        setState(() {
          _error = true;
          _loading = false;
        });
        if (identical(_server, owned)) _server = null;
        await owned?.close();
      }
    } finally {
      if (!_current(generation)) {
        if (identical(_server, owned)) _server = null;
        await owned?.close();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    final server = _server;
    _server = null;
    final pending = _initializations.toList();
    _serverClosed = () async {
      await server?.close();
      // A bind that completes after disposal still belongs to this preview;
      // its obsolete initialization closes it before this Future completes.
      await Future.wait(pending);
    }();
    unawaited(_serverClosed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SegmentedTabs(
            tabs: [
              SegmentedTab(
                label: l10n.workspacePreviewRendered,
                icon: Lucide.Eye,
              ),
              SegmentedTab(
                label: l10n.workspacePreviewSource,
                icon: Lucide.FileCode,
              ),
            ],
            index: _showSource ? 1 : 0,
            onChanged: (next) => setState(() => _showSource = next == 1),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_showSource) {
      return CodeFilePreview(
        file: widget.file,
        autoLoad: widget.autoLoad,
        language: 'xml',
      );
    }
    if (_error != null) {
      return PreviewError(onRetry: () => unawaited(load()));
    }
    if (_loading || _controller == null) {
      return const PreviewLoading();
    }
    return WebViewWidget(controller: _controller!);
  }
}
