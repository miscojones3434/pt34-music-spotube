import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Pt34MusicApp());
}

class Pt34MusicApp extends StatelessWidget {
  const Pt34MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PT34-MUSIC',
      debugShowCheckedModeBanner: false,
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
      home: const Pt34MusicHome(),
    );
  }
}

String textOf(dynamic value, {String fallback = ''}) {
  final valueText = value?.toString().trim() ?? '';
  return valueText.isEmpty ? fallback : valueText;
}

class LibraryTrack {
  const LibraryTrack({
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

  LibraryTrack copyWith({
    bool? favorite,
  }) {
    return LibraryTrack(
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

  factory LibraryTrack.fromJson(Map<String, dynamic> json) {
    return LibraryTrack(
      id: textOf(
        json['id'],
        fallback: DateTime.now().microsecondsSinceEpoch.toString(),
      ),
      title: textOf(json['title'], fallback: 'Tema sin título'),
      artist: textOf(json['artist']),
      album: textOf(json['album']),
      coverUrl: textOf(json['coverUrl']),
      audioUrl: textOf(json['audioUrl']),
      favorite: json['favorite'] == true,
    );
  }
}

class CatalogArtist {
  const CatalogArtist({
    required this.id,
    required this.name,
    required this.country,
    required this.type,
  });

  final String id;
  final String name;
  final String country;
  final String type;

  factory CatalogArtist.fromJson(Map<String, dynamic> json) {
    return CatalogArtist(
      id: textOf(json['id']),
      name: textOf(json['name'], fallback: 'Artista'),
      country: textOf(json['country']),
      type: textOf(json['type']),
    );
  }
}

class CatalogAlbum {
  const CatalogAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.type,
  });

  final String id;
  final String title;
  final String artist;
  final String year;
  final String type;

  String get coverUrl {
    return 'https://coverartarchive.org/release-group/$id/front-250';
  }

  factory CatalogAlbum.fromJson(Map<String, dynamic> json) {
    final names = <String>[];
    final credit = json['artist-credit'];

    if (credit is List) {
      for (final item in credit) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final name = textOf(map['name']);

          if (name.isNotEmpty) {
            names.add(name);
            continue;
          }

          final artist = map['artist'];

          if (artist is Map) {
            final artistName = textOf(
              Map<String, dynamic>.from(artist)['name'],
            );

            if (artistName.isNotEmpty) {
              names.add(artistName);
            }
          }
        }
      }
    }

    final date = textOf(json['first-release-date']);
    final year = date.length >= 4 ? date.substring(0, 4) : date;

    return CatalogAlbum(
      id: textOf(json['id']),
      title: textOf(json['title'], fallback: 'Álbum'),
      artist: names.join(', '),
      year: year,
      type: textOf(json['primary-type']),
    );
  }
}

class Pt34MusicHome extends StatefulWidget {
  const Pt34MusicHome({super.key});

  @override
  State<Pt34MusicHome> createState() => _Pt34MusicHomeState();
}

class _Pt34MusicHomeState extends State<Pt34MusicHome> {
  static const String libraryKey = 'pt34_music_library_v3';
  static const String currentKey = 'pt34_music_current_v3';

  final html.AudioElement audio = html.AudioElement();
  final TextEditingController catalogSearchController =
      TextEditingController();

  List<LibraryTrack> library = [];
  List<CatalogArtist> artists = [];
  List<CatalogAlbum> albums = [];
  List<CatalogAlbum> artistAlbums = [];

  CatalogArtist? openedArtist;

  int tab = 0;
  String? currentId;

  bool catalogLoading = false;
  bool artistLoading = false;
  bool playing = false;
  double progress = 0;

  String? catalogError;

  DateTime lastMusicBrainzRequest =
      DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();

    library = loadLibrary();
    currentId = html.window.localStorage[currentKey];

    final current = currentTrack;

    if (current != null) {
      audio.src = current.audioUrl;
    }

    audio.onPlay.listen((_) {
      if (mounted) {
        setState(() => playing = true);
      }
    });

    audio.onPause.listen((_) {
      if (mounted) {
        setState(() => playing = false);
      }
    });

    audio.onEnded.listen((_) => nextTrack());

    audio.onTimeUpdate.listen((_) {
      final duration = audio.duration;

      if (!mounted || !duration.isFinite || duration <= 0) {
        return;
      }

      setState(() {
        progress = (audio.currentTime / duration).clamp(0, 1).toDouble();
      });
    });

    audio.onError.listen((_) {
      message(
        'No se puede reproducir esa fuente. Comprueba la URL de audio.',
      );
    });
  }

  @override
  void dispose() {
    audio.pause();
    audio.removeAttribute('src');
    catalogSearchController.dispose();
    super.dispose();
  }

  LibraryTrack? get currentTrack {
    for (final track in library) {
      if (track.id == currentId) {
        return track;
      }
    }

    return null;
  }

  List<LibraryTrack> loadLibrary() {
    try {
      final raw = html.window.localStorage[libraryKey];

      if (raw == null || raw.isEmpty) {
        return [];
      }

      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) => LibraryTrack.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((track) => track.audioUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void saveLibrary() {
    html.window.localStorage[libraryKey] = jsonEncode(
      library.map((track) => track.toJson()).toList(),
    );
  }

  void message(String text) {
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

  Future<Map<String, dynamic>> musicBrainzRequest(
    String endpoint,
    Map<String, String> parameters,
  ) async {
    final elapsed = DateTime.now().difference(lastMusicBrainzRequest);
    const minimumWait = Duration(milliseconds: 1100);

    if (elapsed < minimumWait) {
      await Future<void>.delayed(minimumWait - elapsed);
    }

    lastMusicBrainzRequest = DateTime.now();

    final uri = Uri.https(
      'musicbrainz.org',
      '/ws/2/$endpoint',
      {
        ...parameters,
        'fmt': 'json',
      },
    );

    final response = await html.HttpRequest.getString(uri.toString());
    final decoded = jsonDecode(response);

    if (decoded is! Map) {
      throw const FormatException('Respuesta inválida');
    }

    return Map<String, dynamic>.from(decoded);
  }

  Future<void> searchCatalog() async {
    final query = catalogSearchController.text.trim();

    if (query.length < 2) {
      message('Escribe al menos dos letras para buscar.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      catalogLoading = true;
      catalogError = null;
      openedArtist = null;
      artistAlbums = [];
      artists = [];
      albums = [];
    });

    try {
      final artistResult = await musicBrainzRequest(
        'artist',
        {
          'query': query,
          'limit': '8',
        },
      );

      final albumResult = await musicBrainzRequest(
        'release-group',
        {
          'query': query,
          'limit': '18',
          'type': 'album|ep|single',
        },
      );

      final searchedArtists = <CatalogArtist>[];
      final searchedAlbums = <CatalogAlbum>[];

      final rawArtists = artistResult['artists'];

      if (rawArtists is List) {
        for (final item in rawArtists) {
          if (item is Map) {
            final artist = CatalogArtist.fromJson(
              Map<String, dynamic>.from(item),
            );

            if (artist.id.isNotEmpty) {
              searchedArtists.add(artist);
            }
          }
        }
      }

      final rawAlbums = albumResult['release-groups'];

      if (rawAlbums is List) {
        for (final item in rawAlbums) {
          if (item is Map) {
            final album = CatalogAlbum.fromJson(
              Map<String, dynamic>.from(item),
            );

            if (album.id.isNotEmpty) {
              searchedAlbums.add(album);
            }
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        artists = searchedArtists;
        albums = searchedAlbums;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        catalogError =
            'No se ha podido consultar el catálogo. Espera unos segundos y prueba otra vez.';
      });
    } finally {
      if (mounted) {
        setState(() => catalogLoading = false);
      }
    }
  }

  Future<void> openArtist(CatalogArtist artist) async {
    setState(() {
      openedArtist = artist;
      artistAlbums = [];
      artistLoading = true;
      catalogError = null;
    });

    try {
      final result = await musicBrainzRequest(
        'release-group',
        {
          'artist': artist.id,
          'type': 'album|ep',
          'limit': '24',
        },
      );

      final fetchedAlbums = <CatalogAlbum>[];
      final rawAlbums = result['release-groups'];

      if (rawAlbums is List) {
        for (final item in rawAlbums) {
          if (item is Map) {
            final album = CatalogAlbum.fromJson(
              Map<String, dynamic>.from(item),
            );

            if (album.id.isNotEmpty) {
              fetchedAlbums.add(album);
            }
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() => artistAlbums = fetchedAlbums);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        catalogError =
            'No se han podido cargar los álbumes de este artista.';
      });
    } finally {
      if (mounted) {
        setState(() => artistLoading = false);
      }
    }
  }

  Future<void> playTrack(LibraryTrack track) async {
    final isNewTrack = currentId != track.id;

    setState(() {
      currentId = track.id;
      progress = 0;
    });

    html.window.localStorage[currentKey] = track.id;

    if (isNewTrack) {
      audio.src = track.audioUrl;
      audio.load();
    }

    try {
      await audio.play();
    } catch (_) {
      message(
        'El navegador ha bloqueado o no admite esa fuente de audio.',
      );
    }
  }

  Future<void> togglePlayback() async {
    final track = currentTrack;

    if (track == null) {
      message('Añade una fuente de audio a tu biblioteca.');
      return;
    }

    if (audio.paused) {
      await playTrack(track);
    } else {
      audio.pause();
    }
  }

  void nextTrack() {
    if (library.isEmpty) {
      return;
    }

    var index = library.indexWhere((track) => track.id == currentId);

    if (index < 0) {
      index = 0;
    }

    index = (index + 1) % library.length;
    playTrack(library[index]);
  }

  void previousTrack() {
    if (library.isEmpty) {
      return;
    }

    var index = library.indexWhere((track) => track.id == currentId);

    if (index <= 0) {
      index = library.length - 1;
    } else {
      index -= 1;
    }

    playTrack(library[index]);
  }

  void favoriteTrack(LibraryTrack track) {
    setState(() {
      library = library
          .map(
            (item) => item.id == track.id
                ? item.copyWith(favorite: !item.favorite)
                : item,
          )
          .toList();
    });

    saveLibrary();
  }

  void deleteTrack(LibraryTrack track) {
    setState(() {
      library.removeWhere((item) => item.id == track.id);
    });

    if (currentId == track.id) {
      audio.pause();
      audio.removeAttribute('src');
      audio.load();

      currentId = null;
      playing = false;

      html.window.localStorage.remove(currentKey);
    }

    saveLibrary();
    message('Fuente eliminada.');
  }

  Future<void> addTrackDialog({
    String title = '',
    String artist = '',
    String album = '',
    String coverUrl = '',
  }) async {
    final titleController = TextEditingController(text: title);
    final artistController = TextEditingController(text: artist);
    final albumController = TextEditingController(text: album);
    final coverController = TextEditingController(text: coverUrl);
    final audioController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Añadir a mi biblioteca'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Tema',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: artistController,
                    decoration: const InputDecoration(
                      labelText: 'Artista',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: albumController,
                    decoration: const InputDecoration(
                      labelText: 'Álbum',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: coverController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Carátula (opcional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: audioController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'URL de audio autorizada',
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
                final audioUrl = audioController.text.trim();
                final uri = Uri.tryParse(audioUrl);

                if (uri == null ||
                    !uri.hasScheme ||
                    (uri.scheme != 'https' && uri.scheme != 'http')) {
                  message(
                    'Introduce una URL válida que empiece por https://',
                  );
                  return;
                }

                final track = LibraryTrack(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  title: titleController.text.trim().isEmpty
                      ? uri.host
                      : titleController.text.trim(),
                  artist: artistController.text.trim(),
                  album: albumController.text.trim(),
                  coverUrl: coverController.text.trim(),
                  audioUrl: audioUrl,
                  favorite: false,
                );

                setState(() => library = [track, ...library]);
                saveLibrary();

                Navigator.pop(dialogContext);
                playTrack(track);

                message('Añadido a tu biblioteca.');
              },
              child: const Text('GUARDAR Y REPRODUCIR'),
            ),
          ],
        );
      },
    );

    titleController.dispose();
    artistController.dispose();
    albumController.dispose();
    coverController.dispose();
    audioController.dispose();
  }

  Widget artwork(
    String url, {
    double size = 56,
  }) {
    final imageUrl = url.isEmpty ? 'pt34-music-logo.png' : url;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Container(
              color: const Color(0xFF2D2042),
              child: const Icon(
                Icons.music_note_rounded,
                color: Color(0xFFE7C8FF),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget libraryTile(LibraryTrack track) {
    final subTitle = [
      if (track.artist.isNotEmpty) track.artist,
      if (track.album.isNotEmpty) track.album,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        leading: InkWell(
          onTap: () => playTrack(track),
          borderRadius: BorderRadius.circular(13),
          child: artwork(track.coverUrl, size: 56),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subTitle.isEmpty ? 'Fuente guardada' : subTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => playTrack(track),
        trailing: Wrap(
          children: [
            IconButton(
              onPressed: () => favoriteTrack(track),
              icon: Icon(
                track.favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: track.favorite
                    ? const Color(0xFFE7C8FF)
                    : null,
              ),
            ),
            IconButton(
              onPressed: () => deleteTrack(track),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget artistTile(CatalogArtist artist) {
    final subtitle = [
      if (artist.type.isNotEmpty) artist.type,
      if (artist.country.isNotEmpty) artist.country,
    ].join(' · ');

    final letter = artist.name.isEmpty
        ? '?'
        : artist.name.substring(0, 1).toUpperCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF2D2042),
          child: Text(
            letter,
            style: const TextStyle(
              color: Color(0xFFE7C8FF),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        title: Text(artist.name),
        subtitle: Text(
          subtitle.isEmpty ? 'Artista del catálogo' : subtitle,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => openArtist(artist),
      ),
    );
  }

  Widget albumTile(CatalogAlbum album) {
    final subtitle = [
      if (album.artist.isNotEmpty) album.artist,
      if (album.year.isNotEmpty) album.year,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        leading: artwork(album.coverUrl, size: 56),
        title: Text(
          album.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.album_rounded),
        onTap: () => openAlbum(album),
      ),
    );
  }

  void openAlbum(CatalogAlbum album) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1B1721),
      builder: (sheetContext) {
        final subtitle = [
          if (album.artist.isNotEmpty) album.artist,
          if (album.year.isNotEmpty) album.year,
          if (album.type.isNotEmpty) album.type,
        ].join(' · ');

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                artwork(album.coverUrl, size: 180),
                const SizedBox(height: 16),
                Text(
                  album.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);

                    addTrackDialog(
                      title: album.title,
                      artist: album.artist,
                      album: album.title,
                      coverUrl: album.coverUrl,
                    );
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('AÑADIR AUDIO AUTORIZADO'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget statCard(
    String label,
    String value,
    IconData icon,
  ) {
    return SizedBox(
      width: 112,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFFE7C8FF)),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget homePage() {
    final favoriteCount =
        library.where((track) => track.favorite).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        Row(
          children: [
            artwork('pt34-music-logo.png', size: 54),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PT34-MUSIC',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Spotube Web · Catálogo y biblioteca',
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
              colors: [
                Color(0xFF9B5CFF),
                Color(0xFF513092),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Artistas y carátulas reales',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Busca artistas, álbumes y lanzamientos reales dentro del catálogo musical.',
                style: TextStyle(height: 1.35),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => setState(() => tab = 1),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF542A9C),
                ),
                icon: const Icon(Icons.search_rounded),
                label: const Text('ABRIR CATÁLOGO'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            statCard(
              'Biblioteca',
              library.length.toString(),
              Icons.library_music_rounded,
            ),
            statCard(
              'Favoritos',
              favoriteCount.toString(),
              Icons.favorite_rounded,
            ),
            statCard(
              'Catálogo',
              'Real',
              Icons.album_rounded,
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Text(
          'Añadido recientemente',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        if (library.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Todavía no hay fuentes en Biblioteca. Entra en Catálogo para buscar artistas y discos.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          )
        else
          ...library.take(5).map(libraryTile),
      ],
    );
  }

  Widget catalogPage() {
    if (openedArtist != null) {
      return artistPage();
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'Catálogo',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Artistas, álbumes y carátulas reales.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: catalogSearchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => searchCatalog(),
          decoration: InputDecoration(
            hintText: 'Busca artista, álbum o canción',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              onPressed: searchCatalog,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (catalogLoading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (catalogError != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(catalogError!),
            ),
          )
        else if (artists.isEmpty && albums.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Escribe un artista, álbum o canción para consultar el catálogo.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          )
        else ...[
          if (artists.isNotEmpty) ...[
            const Text(
              'Artistas',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            ...artists.map(artistTile),
            const SizedBox(height: 20),
          ],
          if (albums.isNotEmpty) ...[
            const Text(
              'Álbumes y lanzamientos',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            ...albums.map(albumTile),
          ],
        ],
      ],
    );
  }

  Widget artistPage() {
    final artist = openedArtist!;

    final letter = artist.name.isEmpty
        ? '?'
        : artist.name.substring(0, 1).toUpperCase();

    final details = [
      if (artist.type.isNotEmpty) artist.type,
      if (artist.country.isNotEmpty) artist.country,
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  openedArtist = null;
                  artistAlbums = [];
                  catalogError = null;
                });
              },
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 4),
            const Text(
              'Artista',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0xFF2D2042),
                  child: Text(
                    letter,
                    style: const TextStyle(
                      color: Color(0xFFE7C8FF),
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        details.isEmpty ? 'Catálogo musical' : details,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Álbumes',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        if (artistLoading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (catalogError != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(catalogError!),
            ),
          )
        else if (artistAlbums.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No hay álbumes disponibles para este artista.'),
            ),
          )
        else
          ...artistAlbums.map(albumTile),
      ],
    );
  }

  Widget libraryPage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Biblioteca',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: addTrackDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('FUENTE'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Fuentes personales guardadas en este navegador.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 18),
        if (library.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(26),
              child: Column(
                children: [
                  Icon(Icons.library_music_outlined, size: 48),
                  SizedBox(height: 12),
                  Text(
                    'Tu biblioteca está vacía',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Busca un artista o álbum en Catálogo y añade una fuente de audio autorizada.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ...library.map(libraryTile),
      ],
    );
  }

  Widget profilePage() {
    final favorites =
        library.where((track) => track.favorite).length;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'Perfil',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: artwork('pt34-music-logo.png', size: 50),
            title: const Text('PT34-MUSIC'),
            subtitle: Text(
              '${library.length} fuentes · $favorites favoritos',
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Card(
          child: ListTile(
            leading: Icon(Icons.public_rounded),
            title: Text('Catálogo real'),
            subtitle: Text(
              'Artistas, discos y carátulas reales.',
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Borrar biblioteca local'),
            subtitle: const Text(
              'Elimina las fuentes guardadas en este navegador.',
            ),
            onTap: () {
              if (library.isEmpty) {
                message('No hay datos que borrar.');
                return;
              }

              setState(() {
                library = [];
                currentId = null;
                playing = false;
                progress = 0;
              });

              audio.pause();
              audio.removeAttribute('src');
              audio.load();

              html.window.localStorage.remove(libraryKey);
              html.window.localStorage.remove(currentKey);

              message('Biblioteca eliminada.');
            },
          ),
        ),
      ],
    );
  }

  Widget miniPlayer() {
    final track = currentTrack;

    if (track == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: const Color(0xFF251E2C),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                artwork(track.coverUrl, size: 42),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        track.artist.isEmpty
                            ? 'Reproductor web'
                            : track.artist,
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
                  onPressed: previousTrack,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                IconButton(
                  onPressed: togglePlayback,
                  icon: Icon(
                    playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    size: 32,
                  ),
                ),
                IconButton(
                  onPressed: nextTrack,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
            Slider(
              value: progress,
              onChanged: (value) {
                final duration = audio.duration;

                if (!duration.isFinite || duration <= 0) {
                  return;
                }

                audio.currentTime = duration * value;

                setState(() => progress = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homePage(),
      catalogPage(),
      libraryPage(),
      profilePage(),
    ];

    return Scaffold(
      body: SafeArea(
        child: pages[tab],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          miniPlayer(),
          NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (index) {
              setState(() {
                tab = index;

                if (index != 1) {
                  openedArtist = null;
                  artistAlbums = [];
                  catalogError = null;
                }
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_rounded),
                label: 'Catálogo',
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
  }
}
