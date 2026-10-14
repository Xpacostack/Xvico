# Xvico architecture

This Swift package has no dependencies on sibling projects or another installed application.

- `Sources/XvicoApp/App`: lifecycle, preferences and orchestration.
- `Models`: scenes, bindings and presets.
- `Input`: HID/touch adapters, gesture processing and mouse sequencing.
- `Mapping`: mapping editors and keyboard vocabulary.
- `Voice`: recognition, input-method routing and process clients.
- `Views`: settings, application selection and system Shortcuts.
- `Design`: theme, localization and 3D rendering.
- `Sources/XvicoBluetooth`: in-tree BLE transport, discovery and packet parsing.
- `ThirdParty`: separately licensed packet tools and CoreAudio backend.
- `Tests`: software regressions; no user speech capture or desktop event posting.

Production input resolves the active app scene and press overrides directly. The unused second mapping-engine/coordinator path is removed. The app does not automatically read another application's preferences.

Scene presets now store only explicit overrides. Unspecified keys inherit the global bindings at execution time and in the editor; volume and mute defaults emit system media keys. The Scenes page can restore initial mappings, pause existing scenes without erasing them, and undo the last restore after a relaunch. The reset only touches remote mapping behavior, preserving appearance, login, sensitivity, permission and voice preferences. Delayed taps and held output are cleared before changing mappings.

Voice input offers two authorization lifecycles. A temporary session retains the original per-session administrator flow. Explicit persistent approval installs the root-owned `VoiceService` payload and the `work.xvico.voice-service` launch daemon once; subsequent manual starts use authenticated XPC. Both peers enforce the builder's certificate and their exact code identifiers using macOS 13 code-signing requirements. The endpoint accepts only a canonical UUID, derives UID/PID from its authenticated connection, and exposes start/stop operations with connection-specific session ownership. There is no arbitrary shell, path, UID or PID supplied over XPC. The installer verifies copied payloads in root-owned staging, validates Apple runtime signatures, hardens file ownership, serializes installs and rolls back failed replacements.

Installing, refreshing approval or relaunching the app never starts capture. The idle daemon only listens for XPC. Captures retain the one-hour bound, stop/quit/disconnection cleanup, microphone gating and restoration of diagnostics. Persistent approval survives the capture deadline. Changing the installed helper payload requires an explicit update; uninstalling the audio backend also removes the persistent service. Production distribution must use the maintainer's stable signing identity for the app and helpers.

The original internal bundle ID, preference keys, installed backend paths and microphone UID are retained as compatibility contracts. Renaming those without migration would discard settings, duplicate audio devices or invalidate privacy permissions. Public names use Xvico; earlier preset formats and shortcut callback schemes remain accepted.

The Apple runtime, build products, local evidence, captures and signing material are not tracked in Git. The optional runtime is supplied separately and verified against Apple's signature. Opus is fetched from its official source with a pinned SHA256 and compiled locally.

Public packages omit the optional Apple runtime. `AppleVoiceRuntimeStore` imports only the signed PacketLogger executable and PacketDecoder framework into a per-user cache, validates the copied signatures and rejects escaping links before replacing the previous import. Failed validation preserves the prior runtime. The app bundle remains sealed. Privileged installation resolves the fixed cache path from the selected local UID, stages the components with root-only permissions and verifies Apple signatures again before making them executable by the backend. Temporary capture also freezes only the expected components into root-owned staging. The main app and GPL helpers share only the MIT-licensed path/layout contract.
