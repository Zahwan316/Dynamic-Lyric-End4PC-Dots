# LyricsWidget — Documentation

A synchronized lyrics widget for the Quickshell bar, with a compact notch-style pill, an expanded karaoke view, and a floating-island placement mode.

![Lyrics screenshot](screenshots/1.png)

---

## Features

- **Real-time sync** with MPRIS players (position/duration polled from `playerctl`).
- **Word-level karaoke** when the source provides enhanced LRC/YRC timings; line-level LRC otherwise.
- **Compact pill** with:
  - album art, current lyric, romanized line, translated line, and equalizer bars;
  - tiered sizing based on how many lines are shown;
  - smooth 260 ms `Easing.InOutCubic` slide/crossfade when the lyric changes (compact mode only).
- **Expanded view** with a stable, non-shaking list:
  - popup anchor and morph size are frozen when expansion starts;
  - list scrolls only when the active line leaves the comfortable reading area;
  - fixed row font sizes and opacity-only emphasis — no blur/scale popping.
- **Multiple lyric sources with automatic fallback**.
- **Translation fallback chain** plus local romanization when all network providers fail.
- **Two placements**:
  - `notch` — Mac-style notch with concave shoulders, attached to the bar/top edge;
  - `floating` / `floating-island` — fully rounded pill, placed 8 px from the screen edge.
- Usable from **left, middle, or right** bar layouts in both classic and dashboard settings.

---

## Placement modes

### `notch`

The compact pill is drawn as a custom shape:

- the top edge spans the full widget width and blends into the bar;
- the top-left/top-right corners curve inward as concave “shoulders”;
- the body is narrower, with rounded bottom corners;
- when `useAlbumColor` is enabled, a dark gradient tinted from the album accent color fills the shape;
- on a bottom bar the shape is mirrored vertically.

### `floating` / `floating-island`

The widget renders in a separate `LyricsIsland` panel window:

- fully rounded rectangle, using the original pill gradient;
- anchored 8 px from the top (or bottom) of the screen;
- hidden from the bar itself;
- only active while the lyrics widget is present in a bar layout.

---

## Enabling and moving the widget

The source of truth for visibility is the **bar layout**, not the `enable` flag. Adding `lyricsWidget` to `leftLayout`, `middleLayout`, or `rightLayout` makes it visible; removing it hides it. The `enable` option is kept only as a synced mirror.

- **Dashboard settings:** `Settings → Dashboard → Bar → Lyrics widget`, then drag **Lyrics** in the bar layout editor.
- **Classic/minimal settings:** `Settings → Bar → Bar widgets / Layout`.

Legacy config entries using the ID `"LyricsWidget"` are normalized to `"lyricsWidget"` automatically when the layout is saved.

---

## Configuration

All options live under `bar.lyricsWidget` in:

```text
~/.config/illogical-impulse/config.json
```

### Options

| Key | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Mirror of layout presence; normally managed by settings. |
| `mode` | string | `"notch"` | `"notch"`, `"floating"`, or `"floating-island"`. |
| `size` | string | `"default"` | Compact/expanded widget scale for notch and floating island: `"extra-small"`, `"small"`, `"default"`, `"medium"`, `"large"`, `"very-large"`. |
| `useAlbumColor` | bool | `true` | Tint the compact background from the current album art. |
| `albumColorStyle` | string | `"gradient"` | Only when `useAlbumColor` is on: `"gradient"` (black with album tint at the bottom) or `"full"` (solid album cover color as the background). |
| `enableKaraoke` | bool | `true` | Animate the current line word-by-word. When off, the whole active line is simply highlighted. |
| `sourceOrder` | string[] | see below | Lyric provider order. Failed providers are skipped. |
| `translation.targetLanguage` | string | `"id"` | Translation target, selectable in Settings → Bar → Lyrics widget. |
| `translation.customEndpoint` | string | `""` | Optional third translation provider. |
| `credentials.*` | strings | `""` | Server URLs/tokens for the providers that need them. |

### Default source order

```text
lrclib → netease → kugou → musixmatch → subsonic → jellyfin → applemusic → youtubemusic
```

Behavior:

- each request has a timeout and a stale-track guard;
- HTTP errors, timeouts, empty/invalid payloads, or lower-priority results fall through to the next provider;
- word-timed results (enhanced LRC/YRC) outrank plain line-timed LRC.

### Provider requirements

| ID | Requirement |
|---|---|
| `lrclib` | None — public API. |
| `netease` | None — public API. |
| `kugou` | None — public lyrics API. |
| `musixmatch` | Uses a public web token by default; can be overridden. |
| `subsonic` | Requires `subsonicUrl`, `subsonicUser`, `subsonicPassword`. |
| `jellyfin` | Requires `jellyfinUrl`, `jellyfinToken`. |
| `applemusic` | Requires `appleMusicToken` (Apple developer token) via iTunes lookup. |
| `youtubemusic` | Requires `youTubeMusicApi` (Invidious/Piped base URL) for search + captions. |

Providers without configuration are skipped silently.

### Full example

```json
{
  "bar": {
    "lyricsWidget": {
      "enable": true,
      "mode": "notch",
      "size": "default",
      "useAlbumColor": true,
      "albumColorStyle": "gradient",
      "enableKaraoke": true,
      "sourceOrder": [
        "lrclib",
        "netease",
        "kugou",
        "musixmatch",
        "subsonic",
        "jellyfin",
        "applemusic",
        "youtubemusic"
      ],
      "translation": {
        "targetLanguage": "id",
        "customEndpoint": ""
      },
      "credentials": {
        "musixmatchToken": "20052115310630bcb171d09f9e09f491",
        "subsonicUrl": "",
        "subsonicUser": "",
        "subsonicPassword": "",
        "jellyfinUrl": "",
        "jellyfinToken": "",
        "appleMusicToken": "",
        "youTubeMusicApi": ""
      }
    }
  }
}
```

---

## Translation pipeline

For each untranslated line the widget tries:

1. **Google Translate** (`translate.googleapis.com`) — also supplies romanization for non-Latin scripts.
2. **MyMemory** — with source-language detection for Japanese, Korean, Chinese, Russian, and English.
3. **Custom endpoint** — only when `translation.customEndpoint` is set. It is called as:

   ```text
   <endpoint>?q=<line>&target=<targetLanguage>
   ```

   and may return plain text or JSON containing `translatedText`, `translation`, or `text`.

If every provider fails, the locally generated romanization is still committed and the queue continues. A stale track id cancels pending work, so results from a previous song are never applied.

The target language is selectable in **Settings → Bar → Lyrics widget → Translation language**. When Google detects that the song is already in that language, translation is skipped and the **Translate** button turns itself off automatically; you can still switch it back on manually. Latin-script lines in the detected language are no longer sent to the translation providers, while non-Latin lines are still processed so romanization remains available.

---

## Visual tuning

The notch geometry is defined near the top of `modules/ii/bar/LyricsWidget.qml`:

```qml
readonly property int notchShoulderInset: Math.round(root.sp(22))
readonly property int notchShoulderDrop: Math.max(root.sp(10), Math.round(root.height * 0.28))
readonly property int notchBottomRadius: Math.max(root.sp(12), Math.round(root.height * 0.35))
```

The `size` option maps to `widgetScale` (0.8 / 0.9 / 1.0 / 1.1 / 1.25 / 1.4). The `sp()` helper scales pixel sizes for both placements and the expanded card.

The notch gradient strength is in the `LinearGradient` named `notchAlbumGradient` inside the `notchBackground` shape.

---

## Main files

| File | Role |
|---|---|
| `modules/ii/bar/LyricsWidget.qml` | Widget UI, lyric fetching, translation queue, animations. |
| `modules/ii/bar/LyricsIsland.qml` | Floating-island panel window and screen-edge geometry. |
| `modules/ii/bar/BarContent.qml` | Horizontal bar layout rendering/filtering. |
| `modules/ii/verticalBar/VerticalBarContent.qml` | Vertical bar layout rendering/filtering. |
| `modules/common/Config.qml` | Options, layout normalization, shared enable helpers. |
| `modules/ii/settings/pages/BarConfig.qml` | Classic settings and layout editor. |
| `modules/ii/settings/DashboardSettingsCatalog.qml` | Dashboard settings section. |
| `modules/ii/settings/DashboardBarWidgets.qml` | Dashboard bar widget catalog. |
| `modules/ii/settings/DashboardBarLayoutCard.qml` | Dashboard drag/drop layout writes. |
| `panelFamilies/IllogicalImpulseFamily.qml` | Floating-island panel activation. |

---

## Troubleshooting

- **No lyrics appear:** confirm the widget is actually in a bar layout, then check `sourceOrder` and credentials for the providers you enabled.
- **Spotify / live lyrics do not appear:** set `bar.media.preferredPlayer` to `spotify` (or the exact player identity) in Settings → Bar → Preferred player. The widget now follows that preference instead of picking the first playing MPRIS bus. Live lines from `sptlrx` are also allowed through even when a synced LRC exists, which fixes long instrumental intros.
- **Only plain line sync:** the matched source did not return enhanced LRC/YRC; try reordering providers.
- **Wrong translation language:** set `bar.lyricsWidget.translation.targetLanguage`.
- **Widget appears in the bar while floating mode is active:** remove it from the bar layout; floating mode follows layout presence.
- **Results from the previous song show up:** stale-track guards should prevent this; if it persists, restart Quickshell.
