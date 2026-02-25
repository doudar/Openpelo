# OpenPelo
<img src="./images/Icon.png" alt="icon" width="150"/>

OpenPelo is an easy-to-use app installer and device manager for **any Android device** — workout machines (Peloton, Echelon, NordicTrack, etc.), tablets, phones, and more. It handles ADB setup automatically, walks you through enabling developer mode, and provides a curated library of apps ideal for fitness equipment screens.

While OpenPelo works with any Android device, it's especially focused on making workout machines more versatile by providing streaming apps, custom launchers, file managers, and fitness tools — all installable with a few clicks over USB or WiFi.

Combine this with [SmartSpin2k](https://Github.com/doudar/SmartSpin2k/) to add automatic resistance and virtual shifting to your spin bike for the ultimate Zwift setup.
  
![image](./images/OpenPelo.png)

## Requirements

- USB cable (for initial setup) or WiFi network (for wireless connection)
- USB debugging enabled on your Android device

## Installation
Watch on YouTube:

[![how to video](https://img.youtube.com/vi/X3oN8JhHe_8/0.jpg)](https://www.youtube.com/watch?v=X3oN8JhHe_8)

### Option 1: Pre-built Executables (Recommended)
1. Go to the [Releases](../../releases) page
2. Download the appropriate file for your system:
   - Windows: `OpenPelo.exe`
   - Mac: `OpenPelo`
3. Run the downloaded file

### Option 2: Run from Source
1. Install Python 3.6 or higher:
   - Windows: Download from [python.org](https://www.python.org/downloads/)
   - Mac: Use Homebrew: `brew install python3`
2. Download this repository
3. Run `python openpelo.py` (Windows) or `python3 openpelo.py` (Mac). Depending on your python installation, it could also be 'py openpelo.py'.

## Usage

### Supported Devices

OpenPelo works with any Android device that supports USB debugging, including:
- **Workout Machines:** Peloton Bike/Tread, Echelon, NordicTrack, Bowflex, and other Android-based fitness equipment
- **Tablets & Phones:** Any Android tablet, phone, or TV device
- **Gen 1 Support:** Older devices with armeabi-v7a architecture are supported with dedicated app versions

### Option 1: USB Connection (Recommended for First Setup)
1. Connect your Android device to your computer via USB
2. Enable USB debugging on your device:
   - Go to Settings → About (or Device Preferences)
   - Tap 7 times on **Build Number** to enable Developer Options
   - Go back to Settings → Developer Options
   - Enable **USB debugging**
   - *(Optional)* Disable "Verify apps over USB" for faster installs
   
   > **Peloton-specific steps:** Make sure your bike sensor cable is connected, perform a Firmware Reset from Settings → System, finish setup and select "Skip Home Installation", enable **Gabeldorsche** in Developer Options, and force quit the "Device Management" app (found in Settings → Apps → System).

3. Run OpenPelo:
   - Double-click the downloaded executable
   - The installer will automatically detect your device
   - Wait for the "✅ Device connected" status
   - Select the apps you want to install
   - Click "Install Selected Apps" and wait for the installation to complete

### Option 2: Wireless ADB Connection
Once Developer Options are enabled (see above), you can connect wirelessly:

1. **Enable Wireless Debugging:**
   - Ensure your device and computer are on the same WiFi network
   - Go to Settings → Developer Options
   - Enable "Wireless debugging"
   - Tap on "Wireless debugging" text to open settings

2. **Connect via OpenPelo:**
   - Run OpenPelo
   - Click the "📶 Connect via WiFi" button
   - Follow the step-by-step guide
   - When prompted, tap "Pair device with pairing code" on your device
   - Enter the displayed IP address, port, and pairing code into OpenPelo
   - Click "Connect"
   - Wait for "Successfully connected!" message

3. **Use OpenPelo wirelessly:**
   - Once connected, you can use all features wirelessly
   - Select apps and install them as you would with USB

## Features

- **Easy-to-use interface** — No technical knowledge required
- **Works with any Android device** — Workout machines, tablets, phones, and more
- **USB and WiFi connections** — Connect via USB for initial setup, then go wireless
- **Curated app library** — Launchers, streaming apps, fitness tools, file managers, and more
- **Built-in device tools** — Screen rotation, developer settings, default launcher management, app uninstallation
- **Automatic ADB setup** — No need to install or configure ADB manually
- **Cross-platform** — Runs on Windows, Mac, and Linux
- **Gen 1 device support** — Dedicated app versions for older armeabi-v7a devices
- **mDNS device discovery** — Automatically scan for devices on your network
- **Configuration-based app management** — Easily add new apps via JSON config

## For Developers

### Adding New Apps

To add new apps to the installer, simply edit the `apps_config.json` file. The configuration format is:

### Automated Builds

This project uses GitHub Actions with [Nuitka](https://nuitka.net/) to build standalone executables for Windows, macOS (Intel and Apple Silicon), and Linux:
- Builds are triggered on pushes to main, pull requests, and when a release is created
- Nuitka compiles `openpelo.py` to optimized binaries while bundling required assets (ADB tools, configuration files, and certifi certificates)
- Produced artifacts are attached to releases: `OpenPelo.exe`, `OpenPelo-macOS-*.zip`, and `OpenPelo-linux.tar.gz`

The build process:
1. Sets up a Python environment on each runner
2. Installs Nuitka + supporting packages (zstandard, certifi, etc.)
3. Compiles OpenPelo with `--standalone --onefile` and includes runtime data directories
4. Packages platform-specific outputs (zip/tar.gz) and uploads them as release assets

To create a new release:
1. Go to the Releases page
2. Click "Create a new release"
3. Tag the version and publish
4. GitHub Actions will automatically build, package, and attach the Nuitka executables

### Building With Nuitka Locally

If you need to create a build outside of GitHub Actions:

1. Install dependencies:
    ```bash
    python -m pip install --upgrade pip
    pip install nuitka zstandard certifi pillow
    ```
2. Run Nuitka for your platform (examples):
    - **Windows PowerShell**
       ```powershell
       python -m nuitka `
          --standalone `
          --onefile `
          --enable-plugin=tk-inter `
          --include-package=certifi `
          --include-data-file=apps_config.json=apps_config.json `
          --include-data-file=usb_debug_steps.json=usb_debug_steps.json `
          --include-data-file=wireless_adb_steps.json=wireless_adb_steps.json `
          --include-data-dir=ADB=ADB `
          --include-data-dir=platform-tools=platform-tools `
          --windows-disable-console `
          --windows-icon-from-ico=Icon.ico `
          --output-filename=OpenPelo.exe `
          openpelo.py
       ```
    - **Linux**
       ```bash
       python -m nuitka \
          --standalone \
          --onefile \
          --enable-plugin=tk-inter \
          --include-package=certifi \
          --include-data-file=apps_config.json=apps_config.json \
          --include-data-file=usb_debug_steps.json=usb_debug_steps.json \
          --include-data-file=wireless_adb_steps.json=wireless_adb_steps.json \
          --include-data-dir=ADB=ADB \
          --include-data-dir=platform-tools=platform-tools \
          --output-filename=OpenPelo \
          openpelo.py
       ```
    - **macOS**
       ```bash
       python -m nuitka \
          --standalone \
          --onefile \
          --enable-plugin=tk-inter \
          --include-package=certifi \
          --include-data-file=apps_config.json=apps_config.json \
          --include-data-file=usb_debug_steps.json=usb_debug_steps.json \
          --include-data-file=wireless_adb_steps.json=wireless_adb_steps.json \
          --include-data-dir=ADB=ADB \
          --include-data-dir=platform-tools=platform-tools \
          --macos-disable-console \
          --output-filename=OpenPelo \
          openpelo.py
       ```
3. Package the resulting binary if needed (zip/tar.gz) before distribution.

```json
{
    "apps": {
        "App Name": {
            "url": "https://download.url/app.apk",
            "package_name": "com.example.app",
            "description": "Brief description of the app"
        }
    }
}
```

### Fields:
- `App Name`: Display name in the installer menu
- `url`: Direct download URL for the APK file
- `package_name`: Android package name (used for installation)
- `description`: Brief description of the app

## Troubleshooting

1. "❌ No device detected"
   - Ensure USB cable is properly connected
   - Check that USB debugging is enabled on your device
   - Try a different USB cable or port
   - Click the "🔄 Refresh" button after fixing the connection

2. "Failed to setup ADB"
   - Check your internet connection
   - Try running the installer with administrator/sudo privileges
   - If using antivirus, temporarily disable it during ADB installation
   - Restart the installer and try again

3. Installation Errors
   - If an app fails to install, check your device's storage space
   - Ensure your internet connection is stable
   - Try installing apps one at a time
   - Check the error message in the log panel for specific issues

4. Wireless Connection Issues
   - "Pairing Failed"
     - Verify your device and computer are on the same WiFi network
     - Double-check the IP address, port, and pairing code
     - Make sure wireless debugging is still enabled on your device
     - Try generating a new pairing code
   - "Connection Timeout"
     - Check your WiFi connection strength
     - Ensure no firewall is blocking the connection
     - Try moving your computer closer to the WiFi router
   - "Connection Failed after pairing"
     - The device may have disconnected. Try clicking "🔄 Refresh"
     - Try connecting again using the "📶 Connect via WiFi" button
     - Restart wireless debugging on your device and try again

## Security Note

This installer only downloads apps from trusted sources specified in the configuration file. However, users should always be cautious when installing third-party applications on their devices.

## Disclaimer

OpenPelo is an independent, open-source project and is not affiliated with, associated with, authorized by, endorsed by, or in any way officially connected with Peloton Interactive, Inc., or any of its subsidiaries or affiliates. The official Peloton website can be found at [https://www.onepeloton.com](https://www.onepeloton.com).

All product and company names including but not limited to "Peloton" are trademarks or registered trademarks of their respective holders. This tool is provided for educational and experimental purposes only. Use of OpenPelo is at your own risk; the developers assume no liability for any damage to your device, voiding of warranties, or other issues that may result from its use.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
