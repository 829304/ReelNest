import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/playback/presentation/player_realtime_stats_panel.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/player/video_playback_stats.dart';

void main() {
  Widget subject(
    VideoPlaybackStats stats, {
    bool loading = false,
    bool buffering = false,
    bool playing = true,
    bool available = true,
  }) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 600,
        child: PlayerRealtimeStatsPanel(
          stats: stats,
          loading: loading,
          buffering: buffering,
          playing: playing,
          available: available,
          palette: const PlayerPalette(lightContent: true),
        ),
      ),
    ),
  );

  testWidgets('shows valid zeroes and keeps decoder and VO drops separate', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        const VideoPlaybackStats(
          estimatedFps: 0,
          decoderDroppedFrames: 0,
          outputDroppedFrames: 7,
          hardwareDecoder: 'd3d11va',
          renderPasses: [
            VideoRenderPass(
              name: 'upload',
              lastMilliseconds: 0,
              averageMilliseconds: 1.25,
            ),
          ],
          forwardCacheBytes: 0,
          forwardCacheSeconds: 0,
          avSyncSeconds: -0.0123,
        ),
      ),
    );

    expect(find.text('0.00 FPS（估算）'), findsOneWidget);
    expect(find.text('解码器丢帧'), findsOneWidget);
    expect(find.text('视频输出丢帧'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('d3d11va'), findsOneWidget);
    expect(find.text('字节 0 B · 时长 约 0.0 s'), findsOneWidget);
    expect(find.text('-12.3 ms'), findsOneWidget);
    expect(find.text('upload'), findsOneWidget);
    expect(find.text('最近 0.000 ms · 平均 1.250 ms · 峰值 --'), findsOneWidget);
    expect(find.text('播放中'), findsOneWidget);
  });

  testWidgets('uses explicit unavailable values and playback state', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(const VideoPlaybackStats(), buffering: true),
    );

    expect(find.text('正在缓冲'), findsOneWidget);
    expect(find.text('--'), findsNWidgets(5));
    expect(find.text('字节 -- · 时长 --'), findsOneWidget);
    expect(find.text('-- · 当前 VO 未提供统计'), findsOneWidget);

    await tester.pumpWidget(
      subject(const VideoPlaybackStats(), loading: true, available: false),
    );
    expect(find.text('正在载入'), findsOneWidget);
  });

  testWidgets('labels software decode and never exposes path-like pass names', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        const VideoPlaybackStats(
          hardwareDecoder: 'no',
          renderPasses: [
            VideoRenderPass(name: r'C:\private\movie.mkv', peakMilliseconds: 2),
          ],
          avSyncSeconds: 0,
        ),
        playing: false,
      ),
    );

    expect(find.text('软件解码'), findsOneWidget);
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.text('0.0 ms'), findsOneWidget);
    expect(find.text('未命名 pass'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
  });
}
