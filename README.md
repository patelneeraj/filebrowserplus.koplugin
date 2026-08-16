# FilebrowserPlus Plugin for KOReader

>[!IMPORTANT]
>Contributors needed for testing. Please check [Discussion #16](https://github.com/patelneeraj/filebrowserplus.koplugin/discussions/16)

## What is this?

This is a plugin for [KOReader](https://github.com/koreader/koreader) that allows you to run [Filebrowser](https://github.com/filebrowser/filebrowser) directly from within KOReader on any supported device.  
It is **inspired by and derived from** the [filebrowser.koplugin](https://github.com/b-/filebrowser.koplugin), but has been **rewritten and extended** to provide more customization and convenience options.

## What is the use?

This plugin enables you to **manage files (ebooks, configurations, etc.) wirelessly**.  
You can start the FilebrowserPlus server on your eReader and access it from another device (laptop, phone, etc.) connected to the same Wi-Fi network.

From the Filebrowser web interface, you can:

- Upload, download, or delete files
- Edit text files directly
- Preview images

## How to install?

1. Download the ZIP file from the latest release on the [Releases Page](https://github.com/patelneeraj/filebrowserplus.koplugin/releases).
2. Extract the ZIP archive.
3. Move the `filebrowserplus.koplugin` directory into the `koreader/plugins/` directory on your device.

## Using a different Filebrowser binary (for other architectures)

The included binary (`filebrowser/filebrowser`) is built for **ARMv7**, which covers most eReaders (e.g., Kindle Paperwhite, Voyage, Oasis, etc.).  
If your device uses a different CPU architecture (e.g., **ARM64**, **x86**, or **MIPS**), you can replace it with the correct binary for your system.

Here’s how:

1. Download the appropriate precompiled Filebrowser binary for your device from the [Filebrowser releases page](https://github.com/filebrowser/filebrowser/releases).
2. Extract the archive on your computer.
3. Rename the downloaded binary to `filebrowser` (no extension).
4. Replace the existing file at: `koreader/plugins/filebrowserplus.koplugin/filebrowser/filebrowser` with your new binary.
5. Start KOReader and launch the plugin as usual.

That’s it — the plugin will automatically use the new binary.

## How to use?

1. Open KOReader’s top menu.
2. Make sure your device is connected to Wi-Fi.
3. Go to **Gearbox Menu → Network → FilebrowserPlus**.
4. Open **FilebrowserPlus settings** (long press on FilebrowserPlus entry) and adjust configuration as needed:
   - **Data path:** defaults to `/`.
     - Note: On **Kindle**, only directories within `/mnt/us` (including `/mnt/us` itself) are writable.
     - On **Kobo**, only directories within `/mnt/onboard` (including `/mnt/onboard` itself) are writable.
     - ⚠️ **Important:** Paths outside these locations are **read-only**, and attempting to use them will prevent directory creation and cause the server to fail to start.
   - **Port:** defaults to `80`. If you get a permission error, try another port such as `8080`.
   - **Auto-stop timeout (min):** defaults to `30`.
     - Set to `0` to disable auto-stop.
5. Start the server with a normal tap on **FilebrowserPlus**.
   - Default username: `admin`
   - Default password: `admin12345678` (shown on first setup)
6. When running, the menu label shows **IP:port** when available.  
   Visit that address (e.g., `http://192.168.x.x:8080`) from your phone or computer connected to the same Wi-Fi network.
7. You can change the password or create new users via the Filebrowser web interface.
8. If you ever forget your password, press **“Reset Admin User Password”** in the plugin settings — it resets to default.

## Menu behavior

- **Tap** on `FilebrowserPlus`: start/stop server quickly.
- **Long press** on `FilebrowserPlus`: open plugin settings.
- While running, menu text shows current connection endpoint (`IP:port` when available).

## Why not use the existing [filebrowser.koplugin](https://github.com/b-/filebrowser.koplugin)?

While the original plugin works, it has a few quirks.  
**FilebrowserPlus** is a modern rewrite that offers improved configurability and convenience while maintaining compatibility with KOReader.

## Extra features provided

Compared to the original plugin, FilebrowserPlus adds:

- Configurable port
- Configurable data path (the original exposed root `/` by default)
- Reset admin password directly from KOReader
- Configurable authentication (the original had auth disabled by default)
- Option to auto-start with KOReader
- Configurable auto-stop timeout (including disable option)

## Compatibility

Currently tested on:

- Kindle Paperwhite (12th Gen)
- Kindle Basic(11th Gen)
- Kindle Basic(10th Gen)
- Kobo Libra Color
- Pocketbook Inkpad Color 3
- Kobo Clara BW

It should work on other Kindle devices and Kobo devices.  
If you own any other device and would like to help test, please open an Issue on GitHub.

## Limitations

At the moment, only the **ARMv7 architecture** binary is provided (covers ~80% of eReaders).  
The only CPU architecture–dependent component is the `filebrowser` binary itself.  
If you use a different architecture, follow the section above to replace the binary.  
If you need assistance, please open an Issue.

## License

Licensed under the **GNU Affero General Public License v3 (AGPLv3)**.  
Portions of this plugin are derived from the original `filebrowser.koplugin` (AGPLv3).
