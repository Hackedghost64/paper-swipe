# Neural narration progress

## Completed

- Added a Read Along sheet that extracts and displays the current PDF page.
- Replaced the system text-to-speech engine with KittenTTS Micro.
- Selected Luna as the default narrator voice at 0.94 speed.
- Added app-managed WAV playback and KittenTTS word-timing highlighting.
- Disabled KittenTTS analytics.
- Added Android network permission for the one-time model download.

## Reader behaviour

The first narration request downloads and caches the Micro model and its voice
files. Later requests run locally. Changing page or closing Read Along stops
narration, while the existing PDF reading-progress persistence is unchanged.

## Remaining handoff

- Build and install the updated APK on the connected Android device.
- Confirm the first-run model download and listen to Luna on a real page.
