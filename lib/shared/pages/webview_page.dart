import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/browser/browser_agent_session.dart';
import '../../features/home/services/tool_approval_service.dart';
import '../../features/settings/widgets/tool_schema_ui.dart';
import '../../l10n/app_localizations.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    this.url,
    this.contentBase64,
    this.agentSession = false,
  });
  final String? url;
  final String? contentBase64; // HTML string in Base64
  final bool agentSession;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  String? _title;
  String? _currentUrl;
  bool _isLoading = true;
  int _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _forceAgentClose = false;
  final List<_ConsoleMessage> _console = <_ConsoleMessage>[];

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('Console', onMessageReceived: _onConsoleMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            setState(() {
              _isLoading = p < 100;
              _progress = p;
            });
          },
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
            if (widget.agentSession) {
              BrowserAgentSession.instance.pageStarted(url);
            }
          },
          onPageFinished: (url) async {
            setState(() {
              _isLoading = false;
              _progress = 100;
              _currentUrl = url;
            });
            if (widget.agentSession) {
              BrowserAgentSession.instance.pageFinished(url);
            }
            await _refreshCanGoStates();
            await _updateTitle();
          },
          onWebResourceError: (err) {
            _pushConsole(
              level: 'error',
              message: 'Web error ${err.errorCode}: ${err.description}',
              source: _currentUrl,
            );
          },
        ),
      );
    if (widget.agentSession) {
      BrowserAgentSession.instance.register(
        _controller,
        onClose: _closeAgentSession,
      );
    }
    // Initial load
    scheduleMicrotask(_initialLoad);
  }

  @override
  void dispose() {
    if (widget.agentSession) {
      BrowserAgentSession.instance.unregister(_controller);
    }
    super.dispose();
  }

  Future<void> _initialLoad() async {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      // Keep parity with existing Linux limitation: no WebView support
      final l10n = AppLocalizations.of(context)!;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.htmlPreviewNotSupportedOnLinux)),
      );
      Navigator.of(context).maybePop();
      return;
    }
    final url = widget.url?.trim() ?? '';
    if (url.isNotEmpty) {
      await _controller.loadRequest(Uri.parse(url));
    } else {
      final data = widget.contentBase64 ?? '';
      final html = data.isEmpty
          ? '<!doctype html><html><body></body></html>'
          : utf8.decode(base64Decode(data));
      await _controller.loadHtmlString(html);
    }
  }

  void _onConsoleMessage(JavaScriptMessage msg) {
    try {
      final obj = jsonDecode(msg.message) as Map<String, dynamic>;
      _pushConsole(
        level: obj['level']?.toString() ?? 'log',
        message: obj['message']?.toString() ?? '',
        source: obj['source']?.toString(),
        line: (obj['line'] as num?)?.toInt(),
      );
    } catch (_) {
      _pushConsole(level: 'log', message: msg.message);
    }
  }

  void _pushConsole({
    required String level,
    required String message,
    String? source,
    int? line,
  }) {
    setState(() {
      _console.add(
        _ConsoleMessage(
          level: level.toUpperCase(),
          message: message,
          source: source,
          line: line,
        ),
      );
      if (_console.length > 128) {
        _console.removeRange(0, _console.length - 128);
      }
    });
  }

  Future<void> _updateTitle() async {
    try {
      final t = await _controller.runJavaScriptReturningResult(
        'document.title',
      );
      setState(() {
        _title = _stripJsString(t);
      });
    } catch (_) {}
  }

  String? _stripJsString(Object? v) {
    if (v == null) return null;
    var s = '$v';
    if (s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    return s;
  }

  Future<void> _refreshCanGoStates() async {
    try {
      final back = await _controller.canGoBack();
      final fwd = await _controller.canGoForward();
      setState(() {
        _canGoBack = back;
        _canGoForward = fwd;
      });
    } catch (_) {}
  }

  Future<void> _closeAgentSession() async {
    if (!mounted) return;
    setState(() {
      _forceAgentClose = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Navigator.of(context).maybePop();
  }

  Future<void> _openAddressEditor() async {
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final editor = TextEditingController(text: _currentUrl ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ru ? 'Открыть адрес' : 'Open address'),
        content: TextField(
          controller: editor,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(hintText: 'https://example.com'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(editor.text),
            child: Text(ru ? 'Открыть' : 'Open'),
          ),
        ],
      ),
    );
    editor.dispose();
    if (!mounted || value == null || value.trim().isEmpty) return;
    var raw = value.trim();
    if (!raw.contains('://')) raw = 'https://$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }
    if (widget.agentSession) BrowserAgentSession.instance.expectNavigation();
    await _controller.loadRequest(uri);
  }

  ToolApprovalRequest? _pendingBrowserApproval(ToolApprovalService? service) {
    if (service == null) return null;
    for (final request in service.pendingRequests) {
      if (request.toolName == 'browser_use') return request;
    }
    return null;
  }

  Widget _browserApprovalBar(
    BuildContext context,
    ToolApprovalRequest request,
  ) {
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final approval = context.read<ToolApprovalService>();
    final action = (request.arguments['action'] ?? '').toString();
    final elementId = request.arguments['element_id'];
    final detail = elementId == null ? action : '$action #$elementId';
    // eval_js runs whatever the model wrote; approving it without seeing it is
    // approving nothing in particular, so the code itself goes in the prompt.
    final code = action == 'eval_js'
        ? (request.arguments['code'] ?? '').toString().trim()
        : '';
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Material(
        color: cs.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ru
                    ? 'Moru хочет выполнить действие в браузере: $detail'
                    : 'Moru wants to perform a browser action: $detail',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (code.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    code,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => approval.deny(
                      request.toolCallId,
                      conversationId: request.conversationId,
                    ),
                    child: Text(ru ? 'Запретить' : 'Deny'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final confirmed = await confirmFullToolTrust(context);
                      if (!confirmed || !context.mounted) return;
                      approval.setAutoApproveAll(true);
                      await context
                          .read<SettingsProvider>()
                          .setToolAutoApproveAll(true);
                    },
                    child: Text(ru ? 'Всегда разрешать' : 'Always allow'),
                  ),
                  FilledButton(
                    onPressed: () => approval.approve(
                      request.toolCallId,
                      conversationId: request.conversationId,
                    ),
                    child: Text(ru ? 'Разрешить' : 'Allow'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool contentMode =
        (widget.contentBase64 != null && (widget.contentBase64!.isNotEmpty)) &&
        ((widget.url == null) || widget.url!.isEmpty);
    final approvalService = widget.agentSession
        ? context.watch<ToolApprovalService>()
        : null;
    final browserApproval = _pendingBrowserApproval(approvalService);
    return PopScope(
      canPop: _forceAgentClose || !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _forceAgentClose) return;
        if (_canGoBack) {
          _controller.goBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _title?.isNotEmpty == true ? _title! : (_currentUrl ?? ''),
          ),
          actions: [
            if (!contentMode && !widget.agentSession) ...[
              IconButton(
                tooltip: l10n.messageWebViewRefreshTooltip,
                onPressed: () => _controller.reload(),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: l10n.messageWebViewForwardTooltip,
                onPressed: _canGoForward ? () => _controller.goForward() : null,
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
            PopupMenuButton<String>(
              onSelected: (value) async {
                switch (value) {
                  case 'open':
                    if (!contentMode) {
                      final url = _currentUrl;
                      if (url != null && url.trim().isNotEmpty) {
                        final uri = Uri.tryParse(url);
                        if (uri != null) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      }
                    }
                    break;
                  case 'console':
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (ctx) => _ConsoleSheet(messages: _console),
                    );
                    break;
                }
              },
              itemBuilder: (ctx) => [
                if (!contentMode)
                  PopupMenuItem<String>(
                    value: 'open',
                    child: Text(l10n.messageWebViewOpenInBrowser),
                  ),
                PopupMenuItem<String>(
                  value: 'console',
                  child: Text(l10n.messageWebViewConsoleLogs),
                ),
              ],
            ),
          ],
          leading: IconButton(
            icon: Icon(
              widget.agentSession
                  ? Icons.close
                  : (_canGoBack ? Icons.arrow_back : Icons.close),
            ),
            onPressed: () async {
              if (widget.agentSession) {
                await _closeAgentSession();
              } else if (_canGoBack) {
                await _controller.goBack();
              } else {
                await Navigator.of(context).maybePop();
              }
            },
          ),
        ),
        body: Column(
          children: [
            if (_isLoading)
              LinearProgressIndicator(
                value: _progress > 0 ? _progress / 100 : null,
              ),
            Expanded(child: WebViewWidget(controller: _controller)),
            if (!contentMode)
              SafeArea(
                top: false,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        onPressed: _canGoBack
                            ? () => _controller.goBack()
                            : null,
                        icon: const Icon(Icons.arrow_back, size: 20),
                      ),
                      IconButton(
                        tooltip: l10n.messageWebViewForwardTooltip,
                        onPressed: _canGoForward
                            ? () => _controller.goForward()
                            : null,
                        icon: const Icon(Icons.arrow_forward, size: 20),
                      ),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _openAddressEditor,
                          child: Container(
                            height: 34,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _currentUrl ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.messageWebViewRefreshTooltip,
                        onPressed: () => _controller.reload(),
                        icon: const Icon(Icons.refresh, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            if (browserApproval != null)
              _browserApprovalBar(context, browserApproval),
          ],
        ),
      ),
    );
  }
}

class _ConsoleMessage {
  _ConsoleMessage({
    required this.level,
    required this.message,
    this.source,
    this.line,
  });
  final String level;
  final String message;
  final String? source;
  final int? line;
}

class _ConsoleSheet extends StatelessWidget {
  const _ConsoleSheet({required this.messages});
  final List<_ConsoleMessage> messages;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.messageWebViewConsoleLogs,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (messages.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  l10n.messageWebViewNoConsoleMessages,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: messages.length,
                itemBuilder: (ctx, i) {
                  final m = messages[i];
                  Color c;
                  switch (m.level) {
                    case 'ERROR':
                      c = cs.error;
                      break;
                    case 'WARN':
                    case 'WARNING':
                      c = cs.secondary;
                      break;
                    default:
                      c = cs.onSurface;
                      break;
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${m.level}: ${m.message}\n${l10n.moruConsoleSource('${m.source ?? ''}${m.line != null ? ':${m.line}' : ''}')}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: c,
                        fontFamily: 'monospace',
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
