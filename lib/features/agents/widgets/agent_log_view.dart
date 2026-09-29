import 'package:flutter/material.dart';

import '../../../shared/widgets/section_card.dart';

/// The install output, following the tail while it grows unless the user
/// scrolled up to read.
class AgentLogView extends StatefulWidget {
  const AgentLogView({super.key, required this.text});

  final String text;

  @override
  State<AgentLogView> createState() => _AgentLogViewState();
}

class _AgentLogViewState extends State<AgentLogView> {
  final _scrollController = ScrollController();
  bool _followTail = true;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_trackPosition);
    _scrollToTail();
  }

  @override
  void didUpdateWidget(covariant AgentLogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) _scrollToTail();
  }

  void _trackPosition() {
    _followTail = _scrollController.position.extentAfter <= 24;
  }

  void _scrollToTail() {
    if (!_followTail || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_followTail || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SectionCard(
      child: SizedBox(
        key: const ValueKey('agent-log'),
        height: 240,
        width: double.infinity,
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            primary: false,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.text,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
