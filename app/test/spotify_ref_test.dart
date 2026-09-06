import 'package:duet/sound_picker_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Duet identifies a Spotify track from a pasted link rather than by running
/// an OAuth flow, so this parser is the entire "picker". If it accepts
/// something it should not, the alarm stores a ref that can never play and the
/// only symptom is a morning that quietly falls back to the tone.
void main() {
  group('accepts what Spotify actually puts on the clipboard', () {
    test('a share link with tracking parameters', () {
      expect(
        spotifyRefFromInput(
            'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=abc123'),
        'spotify:track:4cOdK2wGLETKBW3PvgPWqT',
      );
    });

    test('the country-prefixed link Spotify sometimes produces', () {
      expect(
        spotifyRefFromInput(
            'https://open.spotify.com/intl-es/track/4cOdK2wGLETKBW3PvgPWqT'),
        'spotify:track:4cOdK2wGLETKBW3PvgPWqT',
      );
    });

    test('a bare URI', () {
      expect(spotifyRefFromInput('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'),
          'spotify:playlist:37i9dQZF1DXcBWIGoYBM5M');
    });

    test('surrounding whitespace, which a paste usually carries', () {
      expect(
        spotifyRefFromInput('  https://open.spotify.com/album/1DFixLWuPkv3KT3TnV35m3 \n'),
        'spotify:album:1DFixLWuPkv3KT3TnV35m3',
      );
    });
  });

  group('refuses what cannot play', () {
    test('empty input', () => expect(spotifyRefFromInput('   '), isNull));
    test('some other music service', () {
      expect(spotifyRefFromInput('https://music.apple.com/track/123'), isNull);
    });
    test('a Spotify URL that is not a playable thing', () {
      expect(spotifyRefFromInput('https://open.spotify.com/user/frelse'), isNull);
    });
    test('prose', () => expect(spotifyRefFromInput('play my song'), isNull));
  });

  test('names the ref for the editor', () {
    expect(spotifyRefTitle('spotify:track:abc'), 'Spotify track');
    expect(spotifyRefTitle('spotify:playlist:abc'), 'Spotify playlist');
    expect(spotifyRefTitle('spotify:show:abc'), 'Spotify podcast');
  });
}
