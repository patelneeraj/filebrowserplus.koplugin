# FilebrowserPlus Plugin for KOReader

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
4. Adjust the configuration as needed:
   - **Data path:** defaults to `/` — change it to your books directory (e.g., `/mnt/us/Books` on Kindle).  
   - **Port:** defaults to `80`. If you get a permission error, try another port like `8080`.  
5. Start the server.  
   - Default username: `admin`  
   - Default password: `admin12345678`  
6. When the server starts, you’ll see the **IP address and port**.  
   Visit that address (e.g., `http://192.168.x.x:8080`) from your phone or computer connected to the same Wi-Fi network.  
7. You can change the password or create new users via the Filebrowser web interface.  
8. If you ever forget your password, press **“Reset Admin Password”** in the plugin menu — it will reset it to the default.

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

## Compatibility
Currently tested on:
- Kindle Paperwhite (12th Gen)
- Kindle Basic(11th Gen)
- Kindle Basic(10th Gen)

It should work on other Kindle devices and may also work on Kobo devices (untested).  
If you own a Kobo and would like to help test, please open an Issue on GitHub.

## Limitations
At the moment, only the **ARMv7 architecture** binary is provided (covers ~80% of eReaders).  
The only CPU architecture–dependent component is the `filebrowser` binary itself.  
If you use a different architecture, follow the section above to replace the binary.  
If you need assistance, please open an Issue.

## License
Licensed under the **GNU Affero General Public License v3 (AGPLv3)**.  
Portions of this plugin are derived from the original `filebrowser.koplugin` (AGPLv3).
