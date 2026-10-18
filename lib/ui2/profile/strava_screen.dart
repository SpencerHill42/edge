// Mehr › Strava: paste the API app's client ID and secret once, log in once,
// and finished runs, walks, football and padel go up on their own.
//
// The keys stay in the keychain (StravaVault), never in the build: the IPA is
// built on a public repo. See lib/strava/strava.dart.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../strava/strava.dart';
import '../../strava/strava_sync.dart';
import '../screens/journal_compose.dart' show OsTextField;
import '../ui2.dart';

class StravaScreen extends StatefulWidget {
  const StravaScreen({super.key});

  @override
  State<StravaScreen> createState() => _StravaScreenState();
}

class _StravaScreenState extends State<StravaScreen> {
  final _sync = StravaSync.instance;
  final _id = TextEditingController();
  final _secret = TextEditingController();
  StravaTokens? _tokens;
  bool _haveKeys = false, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final creds = await _sync.vault.credentials();
    final t = await _sync.vault.tokens();
    if (!mounted) return;
    setState(() {
      _haveKeys = creds != null;
      _tokens = t;
      if (creds != null) _id.text = creds.id;
    });
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_secret.text.trim().isNotEmpty || !_haveKeys) {
        await _sync.vault.saveCredentials(_id.text, _secret.text);
      }
      await _sync.connect();
    } catch (e) {
      _error = e is StravaException ? e.message : '$e';
    }
    if (!mounted) return;
    _secret.clear();
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    await _sync.disconnect();
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final t = _tokens;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x16),
          children: [
            NavBar(l?.stravaTitle ?? 'Strava'),
            const SizedBox(height: S.x3),
            Text(
                l?.stravaIntro ??
                    'Runs, walks, football and padel go to Strava with heart '
                        'rate after every workout.',
                style: F.body.copyWith(color: p.ink2)),
            const SizedBox(height: S.x5),
            if (t != null) ...[
              Surface(
                child: Row(children: [
                  Icon(LucideIcons.circleCheck, size: 20, color: p.on(C.green)),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(
                        (t.athlete ?? '').isEmpty
                            ? (l?.stravaConnected ?? 'Connected')
                            : (l?.stravaConnectedAs(t.athlete!) ??
                                'Connected as ${t.athlete}'),
                        style: F.body.copyWith(color: p.ink)),
                  ),
                ]),
              ),
              const SizedBox(height: S.x4),
              BigButton(l?.stravaDisconnect ?? 'Disconnect',
                  color: C.red, soft: true, busy: _busy, onTap: _disconnect),
            ] else ...[
              OsTextField(
                  controller: _id,
                  label: l?.stravaClientId ?? 'Client ID',
                  keyboard: TextInputType.number),
              const SizedBox(height: S.x4),
              OsTextField(
                  controller: _secret,
                  label: l?.stravaClientSecret ?? 'Client secret',
                  hint: _haveKeys ? '••••••••' : ''),
              const SizedBox(height: S.x2),
              Text(
                  l?.stravaKeysHint ??
                      'From strava.com/settings/api. Kept in this iPhone\'s '
                          'keychain only.',
                  style: F.cap.copyWith(color: p.ink3)),
              const SizedBox(height: S.x5),
              BigButton(l?.stravaConnect ?? 'Connect to Strava',
                  icon: LucideIcons.link,
                  color: C.orange,
                  busy: _busy,
                  onTap: _busy ? null : _connect),
            ],
            if (_error != null) ...[
              const SizedBox(height: S.x3),
              Text(
                  l?.stravaConnectFailed(_error!) ??
                      'Could not connect: $_error',
                  style: F.cap.copyWith(color: p.on(C.red))),
            ],
          ],
        ),
      ),
    );
  }
}

/// The upload state of one session, for the activity summary: "Auf Strava ✓"
/// with a link, the progress, or the reason with a retry. Nothing for a sport
/// that is not synced or while Strava is not connected.
class StravaStatusRow extends StatelessWidget {
  final String sessionId;
  final String? type;
  const StravaStatusRow(this.sessionId, this.type, {super.key});

  @override
  Widget build(BuildContext c) {
    if (stravaSportFor(type) == null) return const SizedBox.shrink();
    final sync = StravaSync.instance;
    return ValueListenableBuilder<int>(
      valueListenable: sync.revision,
      builder: (c, _, _) => FutureBuilder<StravaUpload?>(
        future: sync.stateOf(sessionId),
        builder: (c, snap) {
          final u = snap.data;
          if (u == null) return const SizedBox.shrink();
          final p = P.of(c);
          final l = AppLocalizations.of(c);
          final (icon, color, text) = switch (u.state) {
            StravaState.done => (
                LucideIcons.circleCheck,
                C.green,
                l?.stravaStatusDone ?? 'On Strava'
              ),
            StravaState.uploading => (
                LucideIcons.upload,
                C.orange,
                l?.stravaStatusUploading ?? 'Uploading to Strava …'
              ),
            StravaState.queued => (
                LucideIcons.clock,
                C.orange,
                l?.stravaStatusQueued ?? 'Waiting to upload to Strava'
              ),
            StravaState.waiting => (
                LucideIcons.clock,
                C.orange,
                l?.stravaStatusWaiting ??
                    'Waiting for the band\'s heart rate, then to Strava'
              ),
            StravaState.failed => (
                LucideIcons.circleAlert,
                C.red,
                l?.stravaStatusFailed(u.error ?? '') ?? 'Strava: ${u.error}'
              ),
          };
          return Surface(
            onTap: switch (u.state) {
              StravaState.done when u.activityId != null => () => launchUrl(
                  Uri.parse('https://www.strava.com/activities/${u.activityId}'),
                  mode: LaunchMode.externalApplication),
              StravaState.failed => () => sync.retry(sessionId),
              _ => null,
            },
            child: Row(children: [
              Icon(icon, size: 18, color: p.on(color)),
              const SizedBox(width: S.x3),
              Expanded(
                  child: Text(text, style: F.body.copyWith(color: p.ink))),
              if (u.state == StravaState.failed)
                Text(l?.stravaRetry ?? 'Retry',
                    style: F.cap.copyWith(
                        color: p.on(C.blue), fontWeight: FontWeight.w600)),
            ]),
          );
        },
      ),
    );
  }
}
