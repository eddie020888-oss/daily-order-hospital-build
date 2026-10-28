# Hospital feedback audio

These three WAV files are original deterministic synthesis authored for this project.
They contain no downloaded music, commercial recordings, third-party samples or model outputs.

- `clinic_soft_jazz_loop.wav`: 24 seconds, 80 BPM, eight bars of synthesized keyboard chords, bass and mallet notes.
- `ui_confirm.wav`: two ascending synthesized notes.
- `ui_reject.wav`: two descending synthesized notes.

Format: mono PCM16, 22,050 Hz. The runtime loops the music and controls music/SFX volume independently.
Source: `tools/Generate-HospitalFeedbackAudio.py` in the project root; pass `--output` with a fresh directory under `E:/CODEX` to reproduce without overwriting existing assets.

SHA-256:

| File | SHA-256 |
| --- | --- |
| clinic_soft_jazz_loop.wav | 3312F75C7C5D94F1B59EB5663D3B908FA272EDF50A5213741E0742F221B541B2 |
| ui_confirm.wav | 3AB07EA0AB2D78156B48DE9130481C8B8B9FC31F6985444C316AF5E0CC088B44 |
| ui_reject.wav | 37FE3873108E4FCD81EDF7CB7536BB694B335D1B09E9039AB78F0F03F230B7BD |

This establishes source provenance, not listening approval, Android device verification or acceptance against the approved visual design.
