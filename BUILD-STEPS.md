# 📱 How to get FreeTune onto your iPhone

Two paths. **Path A needs no Mac** (GitHub builds it for you), Path B uses Xcode.

---

## Step 0 — Get your free Jamendo key (2 minutes, required)

1. Go to **https://dev.jamendo.com** → create a free account.
2. Click **"Register a new application"** (any name, e.g. `FreeTune`).
3. Copy your **client_id**.
4. Either paste it into the app's **Settings tab** after install,
   or hardcode it: open `FreeTune/Services/JamendoAPI.swift` and set
   `bundledClientID = "YOUR_KEY_HERE"`. (Recommended — then the app works
   for anyone you share the IPA with.)

---

## Path A — No Mac needed (GitHub Actions + Sideloadly on Windows)

1. **Put the project on GitHub**
   - Create a new GitHub repo → upload this `freetune` folder
     (easiest: GitHub Desktop → Add existing folder, or drag-and-drop on github.com).
2. **GitHub builds the IPA**
   - Open the repo → **Actions** tab → workflow "Build FreeTune IPA" → **Run workflow**.
   - It compiles the app on Apple's macOS CI and produces an artifact
     **`FreeTune-unsigned-ipa`** → download & unzip → `FreeTune-unsigned.ipa`.
3. **Sign + install on Windows with Sideloadly**
   - Install **Sideloadly** (sideloadly.io) and the **Apple Devices** app from
     the Microsoft Store (it provides the iPhone USB drivers).
   - Connect your iPhone by USB (trust the computer).
   - Drag the IPA into Sideloadly, enter your **Apple ID**, click **Start**.
   - On the iPhone: Settings → General → VPN & Device Management → trust your Apple ID profile.
4. **Done.** Free Apple IDs re-sign every 7 days (just re-run Sideloadly).
   A paid Apple Developer account ($99/yr) makes it last 1 year and enables App Store publishing.

---

## Path B — With a Mac (Xcode)

1. Copy the `freetune` folder to any Mac (AirDrop / USB / cloud).
2. Install **Xcode 16 or newer** (free on the App Store).
3. Double-click **`FreeTune.xcodeproj`**.
4. Select the **FreeTune** target → **Signing & Capabilities** → choose your
   **Team** (your Apple ID works; Xcode creates a Personal Team).
5. Plug in your iPhone → select it at the top → **Run ▶**. (First time:
   iPhone Settings → VPN & Device Management → trust developer.)
6. To export a real **IPA**: Product → **Archive** → Window → Organizer →
   **Distribute App** → *Custom* → *Debug/Development* → export.
   Then install via Path A step 3, or directly from Xcode.

---

## Simulator quick check (Path B)

In Xcode pick any iPhone Simulator → **Run ▶** — the whole UI runs instantly
(without an API key you'll just see the onboarding card).

---

## FAQ

- **Why is a key needed?** Jamendo's public API identifies every app with a
  free client ID. It costs nothing and has generous limits.
- **Why does the app say "download songs to enable FX"?** The EQ / Immersive
  DSP chain processes local files in real time — for streamed tracks it's
  applied automatically once they're downloaded.
- **Is downloading legal?** Yes — Jamendo music is Creative Commons and the
  app only shows the download button where the artist allowed it
  (`audiodownload_allowed`).
- **Dolby Atmos?** Atmos requires licensed studio content, which public CC
  catalogs don't provide. FreeTune gives you the closest legal equivalent:
  lossless FLAC + real-time EQ/bass/immersive processing.
