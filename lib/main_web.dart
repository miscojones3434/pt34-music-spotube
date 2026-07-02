import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Pt34MusicWebApp());
}

class WebTrack {
  const WebTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.audioUrl,
    required this.favorite,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final String audioUrl;
  final bool favorite;

  WebTrack copyWith({bool? favorite}) {
    return WebTrack(
      id: id,
      title: title,
      artist: artist,
      album: album,
      coverUrl: coverUrl,
      audioUrl: audioUrl,
      favorite: favorite ?? this.favorite,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'coverUrl': coverUrl,
      'audioUrl': audioUrl,
      'favorite': favorite,
    };
  }

  factory WebTrack.fromJson(Map<String, dynamic> json) {
    return WebTrack(
      id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title'].toString().trim()
          : 'Tema sin título',
      artist: json['artist']?.toString().trim() ?? '',
      album: json['album']?.toString().trim() ?? '',
      coverUrl: json['coverUrl']?.toString().trim() ?? '',
      audioUrl: json['audioUrl']?.toString().trim() ?? '',
      favorite: json['favorite'] == true,
    );
  }
}

class Pt34MusicWebApp extends StatefulWidget {
  const Pt34MusicWebApp({super.key});

  @override
  State<Pt34MusicWebApp> createState() => _Pt34MusicWebAppState();
}

class _Pt34MusicWebAppState extends State<Pt34MusicWebApp> {
  static const _storageKey = 'pt34_music_web_library_v1';
  static const _currentKey = 'pt34_music_web_current_v1';

  final html.AudioElement _audio = html.AudioElement();
  final TextEditingController _searchController = TextEditingController();

  List<WebTrack> _tracks = [];
  String? _currentId;
  int _tabIndex = 0;
  bool _isPlaying = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _tracks = _readLibrary();
    _currentId = html.window.localStorage[_currentKey];

    _audio.onPlay.listen((_) {
      if (mounted) {
        setState(() => _isPlaying = true);
      }
    });

    _audio.onPause.listen((_) {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    });

    _audio.onEnded.listen((_) => _nextTrack());

    _audio.onTimeUpdate.listen((_) {
      final duration = _audio.duration;
      if (!duration.isFinite || duration <= 0 || !mounted) {
        return;
      }

      setState(() {
        _progress = (_audio.currentTime / duration).clamp(0, 1).toDouble();
      });
    });

    _audio.onError.listen((_) {
      _showMessage(
        'No se ha podido reproducir la fuente. Comprueba que sea una URL directa compatible.',
      );
    });

    final current = _currentTrack;
    if (current != null) {
      _audio.src = current.audioUrl;
    }
  }

  @override
  void dispose() {
    _audio.pause();
    _audio.removeAttribute('src');
    _searchController.dispose();
    super.dispose();
  }

  WebTrack? get _currentTrack {
    for (final track in _tracks) {
      if (track.id == _currentId) {
        return track;
      }
    }
    return null;
  }

  List<WebTrack> _readLibrary() {
    try {
      final raw = html.window.localStorage[_storageKey];
      if (raw == null || raw.isEmpty) {
        return [];
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map((item) => WebTrack.fromJson(Map<String, dynamic>.from(item)))
          .where((track) => track.audioUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _saveLibrary() {
    html.window.localStorage[_storageKey] = jsonEncode(
      _tracks.map((track) => track.toJson()).toList(),
    );
  }

  void _showMessage(String text) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _playTrack(WebTrack track) async {
    final changedTrack = _currentId != track.id;

    setState(() {
      _currentId = track.id;
      _progress = 0;
    });

    html.window.localStorage[_currentKey] = track.id;

    if (changedTrack) {
      _audio.src = track.audioUrl;
      _audio.load();
    }

    try {
      await _audio.play();
    } catch (_) {
      _showMessage(
        'El navegador ha bloqueado o no admite ese audio. Prueba una URL directa HTTPS.',
      );
    }
  }

  Future<void> _togglePlayback() async {
    final current = _currentTrack;
    if (current == null) {
      _showMessage('Añade una fuente desde Biblioteca.');
      return;
    }

    if (_audio.paused) {
      await _playTrack(current);
      return;
    }

    _audio.pause();
  }

  void _nextTrack() {
    if (_tracks.isEmpty) {
      return;
    }

    var index = _tracks.indexWhere((track) => track.id == _currentId);
    if (index < 0) {
      index = 0;
    } else {
      index = (index + 1) % _tracks.length;
    }

    _playTrack(_tracks[index]);
  }

  void _previousTrack() {
    if (_tracks.isEmpty) {
      return;
    }

    var index = _tracks.indexWhere((track) => track.id == _currentId);
    if (index <= 0) {
      index = _tracks.length - 1;
    } else {
      index -= 1;
    }

    _playTrack(_tracks[index]);
  }

  void _toggleFavorite(WebTrack track) {
    setState(() {
      _tracks = _tracks
          .map(
            (item) => item.id == track.id
                ? item.copyWith(favorite: !item.favorite)
                : item,
          )
          .toList();
    });

    _saveLibrary();
  }

  void _deleteTrack(WebTrack track) {
    setState(() {
      _tracks.removeWhere((item) => item.id == track.id);
    });

    if (_currentId == track.id) {
      _audio.pause();
      _audio.removeAttribute('src');
      _audio.load();
      _currentId = null;
      _isPlaying = false;
      html.window.localStorage.remove(_currentKey);
    }

    _saveLibrary();
    _showMessage('Fuente eliminada.');
  }

  Future<void> _openAddTrackDialog() async {
    final title = TextEditingController();
    final artist = TextEditingController();
    final album = TextEditingController();
    final cover = TextEditingController();
    final audio = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Añadir fuente'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Título o emisora',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: artist,
                    decoration: const InputDecoration(
                      labelText: 'Artista o autor',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: album,
                    decoration: const InputDecoration(
                      labelText: 'Álbum o colección',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cover,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'URL de carátula HTTPS (opcional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: audio,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'URL directa de audio HTTPS',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final audioUrl = audio.text.trim();

                try {
                  final uri = Uri.parse(audioUrl);
                  if (!uri.hasScheme ||
                      (uri.scheme != 'https' && uri.scheme != 'http')) {
                    throw const FormatException();
                  }
                } catch (_) {
                  _showMessage('Introduce una URL válida que empiece por https://');
                  return;
                }

                final track = WebTrack(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  title: title.text.trim().isEmpty
                      ? Uri.parse(audioUrl).host
                      : title.text.trim(),
                  artist: artist.text.trim(),
                  album: album.text.trim(),
                  coverUrl: cover.text.trim(),
                  audioUrl: audioUrl,
                  favorite: false,
                );

                setState(() {
                  _tracks = [track, ..._tracks];
                });

                _saveLibrary();
                Navigator.pop(dialogContext);
                _playTrack(track);
                _showMessage('Fuente guardada en este navegador.');
              },
              child: const Text('GUARDAR Y REPRODUCIR'),
            ),
          ],
        );
      },
    );

    title.dispose();
    artist.dispose();
    album.dispose();
    cover.dispose();
    audio.dispose();
  }

  Widget _cover(WebTrack? track, {double size = 56}) {
    final hasCustomCover =
        track != null && track.coverUrl.trim().isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          hasCustomCover ? track!.coverUrl : 'pt34-music-logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Container(
              color: const Color(0xFF2B1E40),
              child: const Icon(
                Icons.music_note_rounded,
                color: Color(0xFFE2C9FF),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _trackTile(WebTrack track) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        leading: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _playTrack(track),
          child: _cover(track),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (track.artist.isNotEmpty) track.artist,
            if (track.album.isNotEmpty) track.album,
          ].join(' · ').isEmpty
              ? 'Fuente autorizada'
              : [
                  if (track.artist.isNotEmpty) track.artist,
                  if (track.album.isNotEmpty) track.album,
                ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _playTrack(track),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Favorito',
              onPressed: () => _toggleFavorite(track),
              icon: Icon(
                track.favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: track.favorite ? const Color(0xFFE0B8FF) : null,
              ),
            ),
            IconButton(
              tooltip: 'Eliminar',
              onPressed: () => _deleteTrack(track),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _homePage() {
    final favorites = _tracks.where((track) => track.favorite).length;
    final artists = _tracks
        .where((track) => track.artist.trim().isNotEmpty)
        .map((track) => track.artist.trim().toLowerCase())
        .toSet()
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
      children: [
        Row(
          children: [
            _cover(null, size: 54),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PT34-MUSIC',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Spotube Web · Biblioteca personal',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              colors: [Color(0xFF9B5CFF), Color(0xFF4F2D90)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tu música, tu biblioteca',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Añade fuentes de audio propias o autorizadas, con carátula, artista y álbum.',
                style: TextStyle(height: 1.35),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _openAddTrackDialog,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF512A98),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('AÑADIR FUENTE'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _statCard('Fuentes', _tracks.length.toString(), Icons.queue_music_rounded),
            _statCard('Favoritos', favorites.toString(), Icons.favorite_rounded),
            _statCard('Artistas', artists.toString(), Icons.person_rounded),
          ],
        ),
        const SizedBox(height: 26),
        const Text(
          'Añadido recientemente',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (_tracks.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text(
                'Aún no hay música en la biblioteca. Añade una fuente autorizada para comenzar.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          )
        else
          ..._tracks.take(5).map(_trackTile),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return SizedBox(
      width: 112,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFFD9BFFF)),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(label, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchPage() {
    final query = _searchController.text.trim().toLowerCase();

    final results = _tracks.where((track) {
      return track.title.toLowerCase().contains(query) ||
          track.artist.toLowerCase().contains(query) ||
          track.album.toLowerCase().contains(query);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'Buscar',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Temas, artistas o álbumes',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (_tracks.isEmpty)
          const Text(
            'Añade fuentes en Biblioteca para buscarlas aquí.',
            style: TextStyle(color: Colors.white70),
          )
        else if (results.isEmpty)
          const Text(
            'No hay coincidencias.',
            style: TextStyle(color: Colors.white70),
          )
        else
          ...results.map(_trackTile),
      ],
    );
  }

  Widget _libraryPage() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddTrackDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('FUENTE'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Biblioteca',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Las fuentes se guardan solo en este navegador.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          if (_tracks.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(26),
                child: Column(
                  children: [
                    Icon(Icons.library_music_outlined, size: 48),
                    SizedBox(height: 12),
                    Text(
                      'Tu biblioteca está vacía',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 7),
                    Text(
                      'Pulsa FUENTE para añadir música propia o autorizada.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ..._tracks.map(_trackTile),
        ],
      ),
    );
  }

  Widget _profilePage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'Perfil',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: _cover(null),
            title: const Text('PT34-MUSIC'),
            subtitle: const Text('Port web basado en Spotube'),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Modo web'),
            subtitle: const Text(
              'Audio mediante URLs directas compatibles con el navegador.',
            ),
            onTap: () {
              _showMessage(
                'Las fuentes nativas y el servidor local de Spotube no existen en GitHub Pages.',
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Borrar biblioteca local'),
            subtitle: const Text('Elimina las fuentes guardadas de este navegador.'),
            onTap: () async {
              final accepted = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Borrar biblioteca'),
                    content: const Text(
                      'Esta acción elimina las fuentes guardadas en este navegador.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Borrar'),
                      ),
                    ],
                  );
                },
              );

              if (accepted != true) {
                return;
              }

              _audio.pause();
              _audio.removeAttribute('src');
              _audio.load();

              setState(() {
                _tracks = [];
                _currentId = null;
                _isPlaying = false;
                _progress = 0;
              });

              html.window.localStorage.remove(_storageKey);
              html.window.localStorage.remove(_currentKey);
              _showMessage('Biblioteca eliminada.');
            },
          ),
        ),
      ],
    );
  }

  Widget _miniPlayer() {
    final track = _currentTrack;
    if (track == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: const Color(0xFF241D2B),
      child: InkWell(
        onTap: () => _tabIndex = 2,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 8),
          child: Column(
            children: [
              Row(
                children: [
                  _cover(track, size: 42),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          track.artist.isEmpty ? 'Reproductor web' : track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _previousTrack,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  IconButton(
                    onPressed: _togglePlayback,
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      size: 32,
                    ),
                  ),
                  IconButton(
                    onPressed: _nextTrack,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
              Slider(
                value: _progress,
                onChanged: (value) {
                  final duration = _audio.duration;
                  if (!duration.isFinite || duration <= 0) {
                    return;
                  }

                  _audio.currentTime = duration * value;
                  setState(() => _progress = value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _homePage(),
      _searchPage(),
      _libraryPage(),
      _profilePage(),
    ];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PT34-MUSIC',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B5CFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF100E14),
        cardTheme: CardThemeData(
          color: const Color(0xFF1C1822),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(19),
          ),
        ),
      ),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: SafeArea(child: pages[_tabIndex]),
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _miniPlayer(),
                NavigationBar(
                  selectedIndex: _tabIndex,
                  onDestinationSelected: (index) {
                    setState(() => _tabIndex = index);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: 'Inicio',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.search_rounded),
                      label: 'Buscar',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.library_music_outlined),
                      selectedIcon: Icon(Icons.library_music_rounded),
                      label: 'Biblioteca',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: 'Perfil',
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
