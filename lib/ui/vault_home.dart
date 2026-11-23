import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/models.dart';
import '../core/vault_controller.dart';

const _ink = Color(0xFF153E3A);
const _teal = Color(0xFF206A64);
const _mint = Color(0xFFE4F4EE);

class VaultHome extends StatefulWidget {
  final VaultController controller;
  const VaultHome({required this.controller, super.key});

  @override
  State<VaultHome> createState() => _VaultHomeState();
}

class _VaultHomeState extends State<VaultHome> {
  int _tab = 0;
  final Set<String> _cleanupSelected = {};

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Row(children: [
            Icon(Icons.cloud_done_rounded, color: _teal, size: 28),
            SizedBox(width: 10),
            Text('Cloud Photo Vault'),
          ]),
          actions: [
            IconButton(
              onPressed: c.busy || c.backingUp ? null : c.scanPhotos,
              tooltip: 'Scan phone photos',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(children: [
            if (c.notice.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _mint, borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, size: 20, color: _teal),
                  const SizedBox(width: 10),
                  Expanded(child: Text(c.notice, style: const TextStyle(fontSize: 12, color: _ink))),
                ]),
              ),
            if (c.busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: IndexedStack(index: _tab, children: [
              _dashboard(c),
              _gallery(c),
              _cleanup(c),
              _settings(c),
            ])),
          ]),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) {
            setState(() => _tab = index);
            if (index == 2 && c.connected) c.refreshCounts();
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.photo_library_outlined), selectedIcon: Icon(Icons.photo_library), label: 'Photos'),
            NavigationDestination(icon: Icon(Icons.delete_outline_rounded), selectedIcon: Icon(Icons.delete_rounded), label: 'Clean up'),
            NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }

  Widget _dashboard(VaultController c) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
    children: [
      _welcomeBanner(),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: _metric(Icons.photo_library_rounded, '${c.totalPhotos}', 'Phone photos & videos')),
        const SizedBox(width: 12),
        Expanded(child: _metric(Icons.verified_rounded, '${c.backedUp}', 'Verified on Drive')),
      ]),
      const SizedBox(height: 12),
      _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.cloud_rounded, color: _teal),
          const SizedBox(width: 9),
          const Expanded(child: Text('Google Drive', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _ink))),
          _statusChip(c.connected ? 'Connected' : 'Not connected', c.connected),
        ]),
        const SizedBox(height: 12),
        Text(c.email ?? 'Connect your own Google account. No developer storage or server.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        if (!c.connected) ...[
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: c.busy ? null : c.connect,
            icon: const Icon(Icons.link), label: const Text('Connect Google Drive')),
        ],
      ])),
      const SizedBox(height: 12),
      _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Make room for more memories',
          style: TextStyle(fontWeight: FontWeight.w800, color: _ink, fontSize: 19)),
        const SizedBox(height: 8),
        const Text('Only verified cloud copies can be moved to Android Bin. You approve every clean-up.',
          style: TextStyle(color: Color(0xFF5F7773), height: 1.35)),
        const SizedBox(height: 14),
        if (c.backingUp) ...[
          LinearProgressIndicator(value: c.progress?.fraction),
          const SizedBox(height: 9),
          Text('${c.progress?.done ?? 0} / ${c.progress?.total ?? 0} · ${c.progress?.currentFile ?? "Preparing"}',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          TextButton.icon(onPressed: c.cancelBackup,
            icon: const Icon(Icons.stop_circle_outlined), label: const Text('Stop after current file')),
        ] else ...[
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: c.connected && !c.busy ? () => c.startBackup() : null,
            icon: const Icon(Icons.backup_rounded),
            label: const Text('Back up all new photos'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
          )),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: c.busy ? null : () async { await c.scanPhotos(); setState(() => _tab = 1); },
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose photos manually'),
          )),
        ],
      ])),
      const SizedBox(height: 12),
      _panel(child: Row(children: [
        const Icon(Icons.delete_sweep_outlined, color: _teal, size: 29),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${c.readyForCleanup.length} ready for review',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
          const Text('Cloud copy checked before any move to Bin', style: TextStyle(fontSize: 12)),
        ])),
        IconButton(onPressed: () => setState(() => _tab = 2), icon: const Icon(Icons.arrow_forward_ios_rounded)),
      ])),
      const SizedBox(height: 10),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text(
        'Tip: Files in Android Bin may still use storage until the Bin is emptied. Do not empty it before checking your backup.',
        style: TextStyle(color: Colors.black54, fontSize: 12),
      )),
    ],
  );

  Widget _welcomeBanner() => Container(
    padding: const EdgeInsets.all(23),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [_teal, Color(0xFF104842)]),
      borderRadius: BorderRadius.circular(24),
    ),
    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.auto_awesome_rounded, color: Color(0xFFB8F9D8), size: 30),
      SizedBox(height: 12),
      Text('Keep the memories.\nLose the clutter.',
        style: TextStyle(fontSize: 27, color: Colors.white, fontWeight: FontWeight.w900, height: 1.16)),
      SizedBox(height: 9),
      Text('Your photos → Your Google Drive → Your choice to clean up',
        style: TextStyle(color: Color(0xFFE6F8EF), fontSize: 12)),
    ]),
  );

  Widget _metric(IconData icon, String count, String label) => _panel(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: _teal, size: 24),
      const SizedBox(height: 10),
      Text(count, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 27, color: _ink)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ],
  ));

  Widget _gallery(VaultController c) => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 8), child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your gallery', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: _ink)),
        Text('${c.assets.length} loaded of ${c.totalPhotos} · ${c.selected.length} selected',
          style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ])),
      TextButton(onPressed: c.assets.isEmpty ? null : c.selectVisible, child: const Text('Select loaded')),
      IconButton(onPressed: c.selected.isEmpty ? null : c.clearSelected,
        tooltip: 'Clear selection', icon: const Icon(Icons.deselect)),
    ])),
    if (c.assets.isEmpty)
      Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.photo_library_outlined, size: 58, color: _teal),
        const SizedBox(height: 10),
        const Text('Scan to see your photos'),
        const SizedBox(height: 12),
        FilledButton(onPressed: c.busy ? null : c.scanPhotos, child: const Text('Scan photos')),
      ])))
    else
      Expanded(child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 450 && c.canLoadMore && !c.busy) {
            c.loadMore();
          }
          return false;
        },
        child: GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisSpacing: 5, crossAxisSpacing: 5,
          ),
          itemCount: c.assets.length,
          itemBuilder: (context, index) {
            final asset = c.assets[index];
            final chosen = c.selected.contains(asset.id);
            return InkWell(
              onTap: () => c.toggleSelect(asset.id),
              child: Stack(fit: StackFit.expand, children: [
                ClipRRect(borderRadius: BorderRadius.circular(8), child: _thumb(asset)),
                if (chosen) Container(decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _teal, width: 3))),
                Positioned(top: 5, right: 5, child: Icon(
                  chosen ? Icons.check_circle : Icons.circle_outlined,
                  color: chosen ? const Color(0xFFB8F9D8) : Colors.white,
                  shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
                )),
                if (asset.type == AssetType.video)
                  const Positioned(bottom: 5, right: 5, child: Icon(Icons.play_circle_fill_rounded, color: Colors.white)),
              ]),
            );
          },
        ),
      )),
    if (c.canLoadMore && c.assets.isNotEmpty)
      TextButton(onPressed: c.loadMore, child: const Text('Load more')),
    Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 15), child: SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: c.selected.isNotEmpty && c.connected && !c.backingUp ? () => c.startBackup(selectedOnly: true) : null,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: Text(c.backingUp ? 'Backing up…' : 'Back up ${c.selected.length} selected'),
      ),
    )),
  ]);

  Widget _thumb(AssetEntity asset) => FutureBuilder<Uint8List?>(
    future: asset.thumbnailDataWithSize(const ThumbnailSize(220, 220), quality: 75),
    builder: (context, snapshot) => snapshot.data == null
        ? const ColoredBox(color: Color(0xFFE2E9E5), child: Icon(Icons.image_outlined, color: Colors.blueGrey))
        : Image.memory(snapshot.data!, fit: BoxFit.cover),
  );

  Widget _cleanup(VaultController c) {
    final records = c.readyForCleanup;
    final selectedRecords = records.where((r) => _cleanupSelected.contains(r.assetId)).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 8), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Safe clean-up', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 7),
          const Text('Every item will be checked against Google Drive AGAIN before Android asks your permission.',
            style: TextStyle(color: Colors.black54, fontSize: 13)),
          Row(children: [
            Text('${records.length} verified records available', style: const TextStyle(fontSize: 12)),
            const Spacer(),
            TextButton(onPressed: records.isEmpty ? null : () {
              setState(() => _cleanupSelected.addAll(records.map((e) => e.assetId)));
            }, child: const Text('Select all')),
            TextButton(onPressed: () => setState(_cleanupSelected.clear), child: const Text('Clear')),
          ]),
        ],
      )),
      Expanded(child: records.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.verified_user_outlined, size: 60, color: _teal),
              const SizedBox(height: 12),
              const Text('Nothing to clean up yet'),
              TextButton(onPressed: c.connected ? c.refreshCounts : null, child: const Text('Refresh')),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: records.length,
              itemBuilder: (context, i) {
                final record = records[i];
                return Card(child: CheckboxListTile(
                  value: _cleanupSelected.contains(record.assetId),
                  onChanged: (value) => setState(() {
                    if (value == true) { _cleanupSelected.add(record.assetId); }
                    else { _cleanupSelected.remove(record.assetId); }
                  }),
                  title: Text(record.originalName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text('${_humanBytes(record.bytes)} · Cloud checksum verified',
                    style: const TextStyle(fontSize: 11)),
                  secondary: const Icon(Icons.cloud_done, color: _teal),
                ));
              },
            )),
      Padding(padding: const EdgeInsets.fromLTRB(16, 9, 16, 16), child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: selectedRecords.isEmpty || c.busy || c.backingUp
              ? null : () => _confirmTrash(c, selectedRecords),
          icon: const Icon(Icons.delete_outline),
          label: Text('Review & move ${selectedRecords.length} to Bin'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF9D4A40)),
        ),
      )),
    ]);
  }

  Future<void> _confirmTrash(VaultController c, List<BackupRecord> selectedRecords) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move originals to Android Bin?'),
        content: Text(
          '${selectedRecords.length} items selected.\n\n'
          'The app will re-read every phone original and compare its MD5 and size with its live Google Drive copy. '
          'Only matching items will be offered to Android for trashing.\n\n'
          'Android may ask for system approval. Bin items may still use storage until the Bin is emptied. '
          'Check your Google Drive files before emptying it.\n\n'
          'This action does NOT remove the Google Drive copy.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep originals')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Verify & move to Bin')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await c.trashRecords(selectedRecords);
    if (mounted) setState(_cleanupSelected.clear);
  }

  Widget _settings(VaultController c) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const Text('Backup preferences', style: TextStyle(fontWeight: FontWeight.w900, color: _ink, fontSize: 23)),
      const SizedBox(height: 16),
      _panel(child: Column(children: [
        SwitchListTile.adaptive(
          title: const Text('Automatic backup', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Best-effort background check roughly every 6 hours. Never auto-deletes.'),
          value: c.autoEnabled,
          onChanged: c.connected ? c.changeAuto : null,
        ),
        const Divider(height: 1),
        SwitchListTile.adaptive(
          title: const Text('Wi-Fi only', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Avoid mobile data uploads'),
          value: c.wifiOnly,
          onChanged: c.changeWifi,
        ),
      ])),
      const SizedBox(height: 12),
      _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Cloud account', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _ink)),
        const SizedBox(height: 8),
        Text(c.email ?? 'Not connected', style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 12),
        if (c.connected)
          OutlinedButton.icon(onPressed: c.busy ? null : c.disconnect,
            icon: const Icon(Icons.logout), label: const Text('Disconnect Google'))
        else
          FilledButton.icon(onPressed: c.connect, icon: const Icon(Icons.login), label: const Text('Connect Google Drive')),
      ])),
      const SizedBox(height: 12),
      _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        Text('Built for safety', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _ink)),
        SizedBox(height: 10),
        _Instruction('1', 'Original photos and videos upload without compression'),
        _Instruction('2', 'Google Drive file size and MD5 are checked'),
        _Instruction('3', 'App checks the Google Drive copy again before clean-up'),
        _Instruction('4', 'You approve Android’s system Move to Bin request'),
        SizedBox(height: 10),
        Text('Files are stored in Drive / Cloud Photo Vault / Year / Month. This app uses the Drive file permission scope and does not send photos to a third-party server.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
      ])),
      const SizedBox(height: 12),
      FutureBuilder<String>(future: c.settings.lastRun, builder: (_, snapshot) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text('Last auto status: ${snapshot.data ?? "Loading…"}',
          style: const TextStyle(fontSize: 12, color: Colors.black54)),
      )),
    ],
  );

  Widget _panel({required Widget child}) => Card(child: Padding(
    padding: const EdgeInsets.all(16), child: child,
  ));

  Widget _statusChip(String text, bool connected) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: connected ? _mint : const Color(0xFFFBE6E2),
      borderRadius: BorderRadius.circular(50),
    ),
    child: Text(text, style: TextStyle(
      color: connected ? _teal : const Color(0xFF953F38),
      fontWeight: FontWeight.w800, fontSize: 10,
    )),
  );
}

class _Instruction extends StatelessWidget {
  final String number;
  final String description;
  const _Instruction(this.number, this.description);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      CircleAvatar(radius: 11, backgroundColor: _mint,
        child: Text(number, style: const TextStyle(fontSize: 11, color: _teal, fontWeight: FontWeight.w900))),
      const SizedBox(width: 10),
      Expanded(child: Text(description, style: const TextStyle(fontSize: 12))),
    ]),
  );
}

String _humanBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).toStringAsFixed(1)} KB';
}
