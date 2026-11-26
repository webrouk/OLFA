import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../data/support_repository.dart';
import 'help_screen.dart';
import 'support_files.dart';

/// New support request: category, subject, message and up to 3 images / PDFs.
class NewTicketScreen extends ConsumerStatefulWidget {
  const NewTicketScreen({super.key});
  @override
  ConsumerState<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends ConsumerState<NewTicketScreen> {
  String _cat = 'account';
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _files = <PickedFile>[];
  bool _sending = false;
  String? _subjectError, _bodyError;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _subjectError = _subject.text.trim().length < 3 ? l.errorSubjectShort : null;
      _bodyError = _body.text.trim().length < 10 ? l.errorMessageShort : null;
    });
    if (_subjectError != null || _bodyError != null) return;
    setState(() => _sending = true);
    try {
      final t = await ref.read(supportRepositoryProvider).create(category: _cat, subject: _subject.text.trim(), body: _body.text.trim(), files: List.of(_files));
      ref.invalidate(ticketsProvider);
      if (mounted) context.pushReplacement(Routes.ticket(t.id));
    } catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cats = ticketCategories(l);
    return FormPage(
      title: l.newRequest,
      action: PrimaryButton(label: l.send, loading: _sending, onPressed: _send),
      children: [
        Text(l.category, style: context.type.inputLabel),
        const SizedBox(height: 8),
        ChoiceWrap<String>(options: cats.keys.toList(), label: (k) => cats[k]!, isSelected: (k) => _cat == k, onTap: (k) => setState(() => _cat = k)),
        const SizedBox(height: 18),
        OlfaTextField(label: l.subject, controller: _subject, maxLength: 150, error: _subjectError, textInputAction: TextInputAction.next),
        OlfaTextField(label: l.message, controller: _body, maxLines: 6, maxLength: 4000, error: _bodyError),
        Row(children: [
          TextButton.icon(
            onPressed: () async {
              final f = await pickSupportFiles(context, room: kTicketFilesPerMessage - _files.length);
              if (mounted) setState(() => _files.addAll(f));
            },
            icon: const Icon(Icons.attach_file_rounded),
            label: Text(l.attachFile),
          ),
          const Spacer(),
          Text(l.attachHint, style: context.type.caption),
        ]),
        PickedFilesStrip(files: _files, onRemove: (i) => setState(() => _files.removeAt(i))),
        const SizedBox(height: 14),
        InfoBanner(text: l.supportPrivacy, icon: Icons.lock_outline_rounded),
      ],
    );
  }
}

/// The conversation with support, on one page: staff replies arrive here (live
/// while open, plus a notification), with images and PDFs both ways.
class SupportThreadScreen extends ConsumerStatefulWidget {
  const SupportThreadScreen({super.key, required this.ticketId});
  final String ticketId;
  @override
  ConsumerState<SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends ConsumerState<SupportThreadScreen> with WidgetsBindingObserver {
  SupportTicket? _t;
  Object? _error;
  final _c = TextEditingController();
  final _files = <PickedFile>[];
  final _pending = <TicketMessage>[];
  final _scroll = ScrollController();
  StreamSubscription<String>? _sub;
  Timer? _poll;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _sub = ref.read(supportRepositoryProvider).replies().listen((id) {
      if (id == widget.ticketId) _load();
    });
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load()); // fallback if the socket is down
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _poll?.cancel();
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await ref.read(supportRepositoryProvider).thread(widget.ticketId);
      if (!mounted) return;
      final grew = (t.messages.length) > (_t?.messages.length ?? 0);
      setState(() {
        _t = t;
        _error = null;
      });
      if (grew) _toEnd();
    } catch (e) {
      if (mounted && _t == null) setState(() => _error = e);
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> _send({TicketMessage? retry}) async {
    final body = retry?.body ?? _c.text.trim();
    final files = retry == null ? List.of(_files) : <PickedFile>[];
    if (body.isEmpty && files.isEmpty) return;
    final local = retry ??
        TicketMessage(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          fromStaff: false,
          body: body,
          createdAt: DateTime.now(),
          sending: true,
          files: [for (final f in files) TicketFile(id: f.name, fileName: f.name, mime: f.mime, bytes: f.bytes.length, localBytes: f.bytes)],
        );
    setState(() {
      _sending = true;
      _pending.removeWhere((m) => m.id == local.id);
      _pending.add(TicketMessage(id: local.id, fromStaff: false, body: local.body, createdAt: local.createdAt, files: local.files, sending: true));
      if (retry == null) {
        _c.clear();
        _files.clear();
      }
    });
    _toEnd();
    try {
      await ref.read(supportRepositoryProvider).reply(widget.ticketId, body: body, files: files);
      _pending.removeWhere((m) => m.id == local.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final i = _pending.indexWhere((m) => m.id == local.id);
        if (i >= 0) _pending[i] = TicketMessage(id: local.id, fromStaff: false, body: local.body, createdAt: local.createdAt, files: local.files, failed: true);
      });
      showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close() async {
    final l = AppLocalizations.of(context);
    final ok = await showConfirmation(context, title: l.closeRequestTitle, body: l.closeRequestBody, confirmLabel: l.closeRequest, icon: Icons.task_alt_rounded);
    if (!ok) return;
    try {
      await ref.read(supportRepositoryProvider).close(widget.ticketId);
      await _load();
    } catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = _t;
    final closed = t?.status == TicketStatus.closed;
    final msgs = [...?t?.messages, ..._pending];
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t?.subject ?? l.screenHelp, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (t != null) Text('${ticketCategories(l)[t.category] ?? t.category} · ${ticketStatusLabel(l, t.status)}', style: context.type.caption),
        ]),
        actions: [
          if (t != null && !closed) IconButton(tooltip: l.closeRequest, onPressed: _close, icon: const Icon(Icons.task_alt_rounded)),
        ],
      ),
      body: t == null
          ? (_error != null ? ErrorState(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : Column(children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount: msgs.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(padding: const EdgeInsets.only(bottom: 12), child: InfoBanner(text: l.supportThreadNote, icon: Icons.support_agent_rounded));
                    }
                    final m = msgs[i - 1];
                    return _Bubble(m: m, onRetry: m.failed ? () => _send(retry: m) : null);
                  },
                ),
              ),
              if (closed)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(l.requestClosedNote, style: context.type.caption, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      SecondaryButton(label: l.newRequest, onPressed: () => context.pushReplacement(Routes.newTicket)),
                    ]),
                  ),
                )
              else
                _Composer(
                  controller: _c,
                  files: _files,
                  sending: _sending,
                  onAttach: () async {
                    final f = await pickSupportFiles(context, room: kTicketFilesPerMessage - _files.length);
                    if (mounted) setState(() => _files.addAll(f));
                  },
                  onRemove: (i) => setState(() => _files.removeAt(i)),
                  onSend: _send,
                ),
            ]),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.files, required this.sending, required this.onAttach, required this.onRemove, required this.onSend});
  final TextEditingController controller;
  final List<PickedFile> files;
  final bool sending;
  final VoidCallback onAttach;
  final void Function(int) onRemove;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: OlfaColors.white,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Divider(height: 1),
          PickedFilesStrip(files: files, onRemove: onRemove),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(6, 8, 8, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(tooltip: l.attachFile, onPressed: onAttach, icon: const Icon(Icons.attach_file_rounded)),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 4000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: l.messageHint, counterText: '', isDense: true),
                ),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, v, __) {
                  final can = !sending && (v.text.trim().isNotEmpty || files.isNotEmpty);
                  return IconButton.filled(tooltip: l.send, onPressed: can ? onSend : null, icon: const Icon(Icons.send_rounded));
                },
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m, this.onRetry});
  final TicketMessage m;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mine = !m.fromStaff;
    final time = DateFormat.Hm(Localizations.localeOf(context).toLanguageTag()).format(m.createdAt);
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            if (!mine)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.support_agent_rounded, size: 14, color: OlfaColors.primary),
                  const SizedBox(width: 4),
                  Text(l.supportTeam, style: context.type.caption.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w600)),
                ]),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: mine ? OlfaColors.primary : OlfaColors.gray,
                borderRadius: OlfaRadius.all(18),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final f in m.files) Padding(padding: const EdgeInsets.only(bottom: 8), child: _FileView(f: f, onDark: mine)),
                if (m.body.isNotEmpty) SelectableText(m.body, style: context.type.bodyMedium.copyWith(color: mine ? OlfaColors.white : OlfaColors.black)),
              ]),
            ),
            const SizedBox(height: 3),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(m.sending ? l.sending : time, style: context.type.caption),
              if (m.failed) ...[
                const SizedBox(width: 6),
                InkWell(onTap: onRetry, child: Text(l.retry, style: context.type.caption.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w600))),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _FileView extends StatelessWidget {
  const _FileView({required this.f, required this.onDark});
  final TicketFile f;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? OlfaColors.white : OlfaColors.black;
    if (f.isImage) {
      final img = f.localBytes != null ? Image.memory(f.localBytes!, fit: BoxFit.cover) : OlfaImage(url: f.url);
      return GestureDetector(
        onTap: f.url == null && f.localBytes == null ? null : () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: f.localBytes != null ? Image.memory(f.localBytes!) : OlfaImage(url: f.url, fit: BoxFit.contain)))),
        child: ClipRRect(borderRadius: OlfaRadius.all(12), child: SizedBox(width: 220, height: 160, child: img)),
      );
    }
    return InkWell(
      onTap: f.url == null ? null : () => launchUrl(Uri.parse(f.url!), mode: LaunchMode.externalApplication),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.picture_as_pdf_outlined, color: fg),
        const SizedBox(width: 8),
        Flexible(child: Text(f.fileName, style: context.type.bodySmall.copyWith(color: fg, decoration: f.url != null ? TextDecoration.underline : null), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        Text(fileSize(f.bytes), style: context.type.caption.copyWith(color: fg.withValues(alpha: 0.8))),
      ]),
    );
  }
}
