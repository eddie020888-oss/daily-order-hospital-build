# 日常秩序医院 · iOS

This public repository contains the actual Godot hospital game and its art under `hospital/game`, published with the project owner's explicit authorization, plus its iOS build tooling.

Release builds use the standard `macos-26` GitHub-hosted runner and run only when manually dispatched by the repository owner on `main`. Signing material stays in encrypted repository secrets. No signed packages, raw logs, Actions artifacts or caches are published or retained by the workflow. TestFlight mode uploads directly to Apple in the same job; it does not submit an App Store release.

The small `macos-check.yml` environment check contains no credentials or application upload.
