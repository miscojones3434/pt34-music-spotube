import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/audio_player/playback_state.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/platform.dart';

class MobileAudioService extends BaseAudioHandler {
  static const _queueFolderId = 'pt34:auto:queue';
  static const _nowPlayingFolderId = 'pt34:auto:now-playing';
  static const _trackPrefix = 'pt34:auto:track:';

  AudioSession? session;
  final AudioPlayerNotifier audioPlayerNotifier;

  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  AudioPlayerState get playlist => audioPlayerNotifier.state;

  MobileAudioService(this.audioPlayerNotifier) {
    AudioSession.instance.then((s) {
      session = s;
      session?.configure(const AudioSessionConfiguration.music());

      bool wasPausedByBeginEvent = false;

      s.interruptionEventStream.listen((event) async {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              await audioPlayer.setVolume(0.5);
              break;

            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              wasPausedByBeginEvent = audioPlayer.isPlaying;
              await audioPlayer.pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              await audioPlayer.setVolume(1.0);
              break;

            case AudioInterruptionType.pause when wasPausedByBeginEvent:
            case AudioInterruptionType.unknown when wasPausedByBeginEvent:
              await audioPlayer.resume();
              wasPausedByBeginEvent = false;
              break;

            default:
              break;
          }
        }
      });

      s.becomingNoisyEventStream.listen((_) {
        audioPlayer.pause();
      });
    });

    audioPlayer.playerStateStream.listen((state) async {
      if (state == AudioPlaybackState.playing) {
        await session?.setActive(true);
      }

      playbackState.add(await _transformEvent());
    });

    audioPlayer.positionStream.listen((_) async {
      playbackState.add(await _transformEvent());
    });

    audioPlayer.bufferedPositionStream.listen((_) async {
      playbackState.add(await _transformEvent());
    });

    audioPlayer.playlistStream.listen((_) {
      unawaited(_refreshAndroidAuto());
    });

    queue.add(_queueItems());
  }

  void addItem(MediaItem item) {
    session?.setActive(true);
    mediaItem.add(item);
    unawaited(_refreshAndroidAuto());
  }

  MediaItem _trackToMediaItem(SpotubeTrackObject track) {
    return MediaItem(
      id: '$_trackPrefix${Uri.encodeComponent(track.id)}',
      title: track.name,
      album: track.album.name,
      artist: track.artists.asString(),
      duration: Duration(milliseconds: track.durationMs),
      artUri: track.album.images.asUri(
        placeholder: ImagePlaceholder.albumArt,
      ),
      playable: true,
    );
  }

  List<MediaItem> _queueItems() {
    return playlist.tracks
        .map(_trackToMediaItem)
        .toList(growable: false);
  }

  SpotubeTrackObject? _findTrack(String mediaId) {
    if (!mediaId.startsWith(_trackPrefix)) return null;

    final trackId = Uri.decodeComponent(
      mediaId.substring(_trackPrefix.length),
    );

    for (final track in playlist.tracks) {
      if (track.id == trackId) return track;
    }

    return null;
  }

  Future<void> _refreshAndroidAuto() async {
    queue.add(_queueItems());

    await AudioService.notifyChildrenChanged(
      AudioService.browsableRootId,
    );

    await AudioService.notifyChildrenChanged(
      _queueFolderId,
    );

    await AudioService.notifyChildrenChanged(
      _nowPlayingFolderId,
    );
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map? options,
  ]) async {
    switch (parentMediaId) {
      case AudioService.browsableRootId:
        return [
          MediaItem(
            id: _nowPlayingFolderId,
            title: 'En reproducción',
            displaySubtitle: playlist.activeTrack == null
                ? 'No hay música sonando'
                : playlist.activeTrack!.name,
            playable: false,
          ),
          MediaItem(
            id: _queueFolderId,
            title: 'Cola actual',
            displaySubtitle: playlist.tracks.isEmpty
                ? 'No hay canciones en cola'
                : '${playlist.tracks.length} canciones',
            playable: false,
          ),
        ];

      case _nowPlayingFolderId:
        final track = playlist.activeTrack;

        if (track == null) {
          return [
            const MediaItem(
              id: 'pt34:auto:empty:now-playing',
              title: 'No hay música reproduciéndose',
              playable: false,
            ),
          ];
        }

        return [_trackToMediaItem(track)];

      case _queueFolderId:
        final items = _queueItems();

        if (items.isEmpty) {
          return [
            const MediaItem(
              id: 'pt34:auto:empty:queue',
              title: 'Reproduce una canción en el móvil',
              displaySubtitle: 'La cola aparecerá aquí',
              playable: false,
            ),
          ];
        }

        return items;

      default:
        return [];
    }
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final track = _findTrack(mediaId);

    if (track == null) return null;

    return _trackToMediaItem(track);
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map? extras,
  ]) async {
    final track = _findTrack(mediaId);

    if (track == null) return;

    await audioPlayerNotifier.jumpToTrack(track);
    await audioPlayer.resume();
  }

  @override
  Future<void> playMediaItem(MediaItem item) {
    return playFromMediaId(item.id);
  }

  @override
  Future<void> play() => audioPlayer.resume();

  @override
  Future<void> pause() => audioPlayer.pause();

  @override
  Future<void> seek(Duration position) => audioPlayer.seek(position);

  @override
  Future<void> setShuffleMode(
    AudioServiceShuffleMode shuffleMode,
  ) async {
    await super.setShuffleMode(shuffleMode);

    await audioPlayer.setShuffle(
      shuffleMode == AudioServiceShuffleMode.all,
    );
  }

  @override
  Future<void> setRepeatMode(
    AudioServiceRepeatMode repeatMode,
  ) async {
    await super.setRepeatMode(repeatMode);

    await audioPlayer.setLoopMode(
      switch (repeatMode) {
        AudioServiceRepeatMode.all ||
        AudioServiceRepeatMode.group =>
          PlaylistMode.loop,
        AudioServiceRepeatMode.one => PlaylistMode.single,
        _ => PlaylistMode.none,
      },
    );
  }

  @override
  Future<void> stop() async {
    await audioPlayerNotifier.stop();
    await _refreshAndroidAuto();
  }

  @override
  Future<void> skipToNext() async {
    await audioPlayer.skipToNext();
    await super.skipToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await audioPlayer.skipToPrevious();
    await super.skipToPrevious();
  }

  @override
  Future<void> onTaskRemoved() async {
    await audioPlayer.pause();

    if (kIsAndroid) exit(0);
  }

  Future<PlaybackState> _transformEvent() async {
    try {
      final hasQueueIndex =
          playlist.currentIndex >= 0 &&
          playlist.currentIndex < playlist.tracks.length;

      return PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          audioPlayer.isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: {
          MediaAction.seek,
        },
        androidCompactActionIndices: const [0, 1, 2],
        playing: audioPlayer.isPlaying,
        updatePosition: audioPlayer.position,
        bufferedPosition: audioPlayer.bufferedPosition,
        queueIndex: hasQueueIndex ? playlist.currentIndex : null,
        shuffleMode: audioPlayer.isShuffled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (audioPlayer.loopMode) {
          PlaylistMode.loop => AudioServiceRepeatMode.all,
          PlaylistMode.single => AudioServiceRepeatMode.one,
          _ => AudioServiceRepeatMode.none,
        },
        processingState: audioPlayer.isBuffering
            ? AudioProcessingState.loading
            : AudioProcessingState.ready,
      );
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      rethrow;
    }
  }
}
