# Changelog

## 2.2.7 - first public release

### Library
- Builds Movies, TV Shows and Music from your server's folder listings, from one or more
  sources.
- The library is saved on the Roku: it shows immediately at launch and survives updates.
  New, changed and removed files are picked up on start and every 30 minutes.
- Posters, plots, cast and track lists come from IMDb data (Cinemeta), TVmaze and Deezer.
  Your own `folder.jpg`, cover and poster art always comes first; matches can be fixed and
  items hidden.
- Song lengths are read from the files themselves, with album details as a fallback.

### Playing
- Resume, versions of the same movie, and Up Next for episodes.
- **Subtitles:**
  - SRT, WebVTT, ASS/SSA, PGS, VobSub, and text tracks inside MKV;
  - right-to-left and non-Latin scripts;
  - "Loading subtitles..." while a track loads;
  - **Choose a subtitle file...** picks one from anywhere on your server, remembered per
    movie.
- **Audio tracks:** the remembered language first, a compatibility track before one that
  needs converting, and commentary or description tracks only when chosen. The Audio menu
  shows what the helper does with each track (e.g. TrueHD 5.1 > AC3 5.1).
- **Play bar:** the video and audio formats playing (H.264, 1080p, HDR, AC3 5.1...), with a
  HELPER badge when the audio is being converted.
- **Unplayable files:** files this Roku can't play (HEVC, 4K or AV1 on Rokus without them)
  are flagged before playing, with another version offered when there is one.

### Music
- Album pages with gapless playback, seeking, and a player bar with the album art.
  Music keeps playing while you browse; a paused song's bar goes when you leave the page.
- FLAC above 48 kHz plays through the helper at the right speed.

### The helper (optional)
- Your own free Oracle Cloud server converts only the audio your Roku can't play. Video
  never passes through it.
  - DTS and TrueHD become Dolby Digital. Stereo stays stereo and 7.1 becomes 5.1, or
    everything becomes stereo with **Converted audio in stereo** on.
  - Hi-res FLAC becomes 48 kHz.
- One-step setup in Oracle Cloud Shell (`boxstream-setup.sh`). The server gets a random
  plain name, and `--remove NAME` deletes it.
- A Roku that passes DTS to a receiver plays it directly, without the helper.

### Settings
- Every row explains itself in the side panel, and long descriptions get a taller row.
- **This Roku can play** shows each video and audio format with a PLAYS, NO or YOUR HELPER
  badge, and whether the helper is connected.
- The helper's address is typed on a number pad; the dashes and `.sslip.io` are added for
  you.
- **\*** on the remote is caps lock in the keyboard.
