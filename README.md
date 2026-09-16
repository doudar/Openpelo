# OpenPelo

<img src="./images/Icon.png" alt="OpenPelo icon" width="150"/>

OpenPelo lets you install apps, manage files, and control your Android device
from a Windows, Mac, or Linux computer. It is designed primarily for Android-based
fitness equipment such as Peloton, Echelon, and NordicTrack, but it can work
with other Android tablets, phones, and TVs.

![OpenPelo home screen with a selected device, app catalog, ADB messages, and media controls](./images/screenshots/overview.png)

*Screenshots use sample devices, apps, and files.*

[Install](#install-a-release) · [Connect a device](#connect-a-device) ·
[Feature walkthrough](#feature-walkthrough) · [Troubleshooting](#troubleshooting) ·
[For contributors](#for-contributors)

## Features

| Feature | What you can do |
| --- | --- |
| Device connections | Connect over USB or WiFi, switch between devices, and reconnect automatically. |
| App installation | Choose from a catalog tailored to your device or install an APK (Android app file) from your computer. |
| Installed App Manager | Find, open, stop, reset, or uninstall apps, and save a list of what's installed. |
| File Manager | Browse device storage, transfer files, and organize files and folders. |
| Remote screen and media | Control the device through a screen preview, save PNG screenshots, and record MP4 videos. |
| Device tools | Choose a default launcher, rotate the screen, apply developer settings, and access Peloton-specific tools. |
| Ready to use | Includes the connection tools you need, with no separate ADB installation. |

## Install a release

Download the version for your computer from the
[GitHub Releases](../../releases) page:

- Windows: `OpenPelo_Setup_Windows.exe`
- macOS: `OpenPelo-macOS.dmg`
- Linux: `OpenPelo-Linux.tar.gz`

OpenPelo sets up its connection tools automatically the first time you open it.

## Connect a device

### USB

1. Enable Developer Options on the Android device.
2. Enable USB debugging.
3. Connect the device with a USB data cable.
4. Accept the device's **Allow USB debugging** prompt.
5. Launch OpenPelo, click **Refresh Devices** if needed, and choose the device
   from **Target Device**. The status banner and **ADB Messages** show connection
   progress.

The **Developer Mode Guide** on the home screen provides an in-app setup
walkthrough. Menu locations depend on the device and its firmware.

### WiFi

![Wireless Connection screen with discovery, USB setup, pairing fields, and connection status](./images/screenshots/wireless-connection.png)

1. Connect the computer and Android device to the same local network.
2. Open **Connect via WiFi**, follow the guide, and click
   **I'm Ready - Connect Device**.
3. For a new Android 11+ wireless-debugging connection, open the device's
   **Pair device with pairing code** dialog. Enter its IP address, **Pairing
   Port**, and six-digit **Pairing Code** in OpenPelo.
4. Enter the **Connection Port** from the device's main Wireless debugging
   screen. This is usually different from the pairing port.
5. Click **Connect** and check the status below the form. Click **Done** to
   return to the home screen, or **Connect Another** to clear the form and add
   another device.

Use **Scan for Devices** to find your device and fill in its connection details.
Enter the pairing code shown on the device yourself. If the scan finds nothing,
enter the details manually. You only need the pairing code and pairing port
the first time you pair a device.

### Set up WiFi through USB

With your device connected over USB and on the same WiFi network as your
computer, open the wireless connection form and click **Pair using USB**.
Choose your device if prompted. Once **Wireless ADB Enabled** appears, you
can unplug the cable and continue over WiFi.

### Automatic WiFi connection

After your first WiFi connection, OpenPelo remembers supported devices and
tries to reconnect automatically, including when you reopen the app. If it
doesn't reconnect after a device restart or network change, use **Connect via
WiFi** or **Pair using USB** again.

## Feature walkthrough

### 1. Choose the device and follow activity

Use **Target Device** to choose the device you want to manage.
The list identifies USB and WiFi connections. Peloton devices appear first;
other Android devices remain available. Check this selection before starting
an operation when multiple devices are connected.

The status banner shows whether you're connected. **ADB Messages** shows
progress and details if something goes wrong. Scroll back to read earlier
messages; the down-arrow control returns to the latest activity. **Refresh
Devices** checks the connection again and refreshes the compatible app list.

### 2. Install apps

1. Connect and select a device to populate **Available Apps**.
2. Read the descriptions and check the apps you want. Scroll inside the catalog
   to see more entries.
3. Click **Install Selected Apps**. OpenPelo downloads and installs the selected
   apps; follow **ADB Messages** for progress and results.
4. To install an APK you already have, click **Install Local APK** and choose
   the `.apk` file on your computer.

The bundled catalog includes fitness utilities such as SmartSpin2k and Grupetto,
launchers such as Lawnchair, app stores, browsers, file managers, and media or
streaming clients. OpenPelo adjusts the list for your device, with older app
versions available for older hardware. Some apps may still require a newer
version of Android.

If Android reports a **Signature Mismatch**, OpenPelo offers **Uninstall &
Reinstall**. That removes the existing app and its local data before reinstalling.
Choose **Cancel** to keep the current installation.

### 3. Manage installed apps

![Installed App Manager showing search, system-app filter, export, and per-app actions](./images/screenshots/installed-app-manager.png)

Open **Tools → Installed App Manager** to inspect apps on the selected device.

- **Search apps** finds apps by name or Android package name. Enable **System
  apps** to include built-in apps, and use **Refresh** to reload the list.
- **Launch** starts an app and opens the remote screen view. **Force stop**
  stops the app; **App settings** opens its Android settings and the remote
  screen view so you can interact with them.
- **Clear data** erases the app's saved settings and local data after
  confirmation. **Uninstall** removes an app you installed; this action is
  disabled for built-in apps.
- **Export visible list** saves the apps shown in the list to a text file in
  your save folder.

### 4. Browse and transfer device files

![File Manager showing device folders, sortable columns, file actions, and download destination controls](./images/screenshots/file-manager.png)

Open **Tools → File Manager** to browse your device's shared storage, with
shortcuts to **sdcard**, **Download**, **DCIM**, and **Movies**.

1. Click a folder to open it, use **Up one level**, or enter a folder location in
   **Device path** and press Enter.
2. Click the **Name**, **Size**, or **Modified** column header to sort. Click
   the same header again to reverse the order.
3. Use **Upload files here** to select local files and send them to the current
   device folder. Use **New folder** to create a folder there.
4. Use a row's **Download** action to copy a file or folder to your computer.
   **More actions → Download to...** selects a destination for just that
   download. **Rename** and **Delete** operate on the device; deletion requires
   confirmation.

The bottom of the dialog shows the download destination. **Change** updates the
save folder, while **Ask each time** prompts for a destination for each download.
The transfer area displays progress and results, and a completed download can
be located with **Open containing folder**.

### 5. View, control, and capture the device screen

The home screen's **Downloads & Media** section groups the save folder and
capture controls. Scroll down if it is below the visible area of the window.

| Control | Walkthrough |
| --- | --- |
| **Save folder** | Use **Change Location** to choose the computer folder used for media, file downloads, and app-list exports. **Open Folder** opens it in your file browser. |
| **Take Screenshot** | Save a picture of the device's display to your save folder. The PNG filename includes the date and time. |
| **View Screen** | Open **Remote Screen View**. Click the preview to tap the device; drag, use the mouse wheel, or press arrow keys to scroll. Use **Back**, **Home**, and **Recents** just as you would on the device. |
| **Record / Stop Rec** | Click **Record** to start recording the device screen. Click **Stop Rec** to finish and save an MP4 video to your save folder. Keep the device connected while saving. |

The screen preview updates periodically, so movement won't look as smooth as
it does on the device itself.

### 6. Configure the launcher and device tools

![OpenPelo Tools menu listing app and file managers, launcher, rotation, developer settings, Netflix, and updates](./images/screenshots/tools.png)

Open **Tools** in the upper-right corner for these additional controls:

- **Set Default Launcher:** install a launcher (home screen app) first, then
  open this tool to see available launchers. Click **Set Default** beside
  a launcher to make it your device's home screen.
- **Rotate Screen:** use **Rotate** to cycle the orientation in 90-degree steps,
  or enable **Auto-rotate** to follow how the device is held. Some apps have
  their own rotation settings.
- **Enable Developer Settings:** choose **Wireless Debugging** and/or **Stay
  Awake While Charging**, then click **Apply**. OpenPelo reports results for
  the requested settings. Connect your device before using this tool.
- **Enable/Disable Built-in Netflix:** a Peloton-specific tool with **Enable
  Netflix** and **Restore Defaults** actions. If enabling it affects other
  Peloton features, choose **Restore Defaults**.
- **Uninstall Peloton Apps:** choose which Peloton apps to remove. This is an
  advanced option; removing built-in apps can affect normal Peloton features.
- **Check For Updates:** checks OpenPelo's GitHub releases. When a newer version
  is found, the home screen shows **View Release**, which opens the release
  page for download. A failed check offers **Retry**.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No device or empty catalog | Enable USB debugging, use a data-capable cable, accept the device's authorization prompt, click **Refresh Devices**, and select **Target Device**. |
| Wireless pairing fails | Check the current six-digit code and pairing port in the device's pairing dialog. The connection port comes from the main Wireless debugging screen. |
| Scan finds nothing | Check that both devices are on the same network and wireless debugging is enabled. Try entering the address and ports manually. |
| A remembered WiFi device stops reconnecting | Make sure it's on the same network as your computer, then try **Connect via WiFi** or **Pair using USB** again. |
| An APK will not install | Check **ADB Messages** for the reason. Make sure the app supports your device and Android version. If you see **Signature Mismatch**, read the reinstall prompt before continuing. |
| A file or setting cannot be accessed | Some system folders and settings are protected by Android. Check **ADB Messages** for details. |
| Capture controls are missing from view | Scroll the home page to **Downloads & Media**, or enlarge the window. |

## For contributors

See [CONTRIBUTING.md](./CONTRIBUTING.md) for building from source, updating the
app catalog, and regenerating screenshots.

## Disclaimer

OpenPelo is independent and is not affiliated with, authorized by, endorsed
by, or otherwise connected to Peloton Interactive, Inc. Product and company
names are trademarks of their respective owners. Use this software at your own
risk.

## License

OpenPelo is available under the [MIT License](./LICENSE).
