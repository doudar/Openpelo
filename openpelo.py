import os
import sys
import platform
import urllib.request
from urllib.parse import urlparse
import zipfile
import subprocess
import certifi
import ssl
import threading
import json
import tkinter as tk
from tkinter import ttk, messagebox, filedialog
from pathlib import Path
from datetime import datetime
from typing import Optional

class OpenPeloGUI:
    def __init__(self):
        self.system = platform.system().lower()

        # --- Add/Modify this section for SSL configuration ---
        try:
            # For all systems, configure SSL to use certifi's CA bundle
            cafile = certifi.where()
            ssl_context = ssl.create_default_context(cafile=cafile)
            ssl._create_default_https_context = lambda: ssl_context
            
            os.environ['REQUESTS_CA_BUNDLE'] = cafile
            os.environ['SSL_CERT_FILE'] = cafile
            print(f"Successfully configured SSL to use certifi CA bundle: {cafile}")
        except Exception as e:
            print(f"Error setting up SSL with certifi: {e}")

        # Handle different directory structures between PyInstaller and normal Python execution
        if getattr(sys, 'frozen', False):
            # If running from PyInstaller bundle
            self.working_dir = Path(os.path.dirname(sys.executable))
        else:
            # If running as normal Python script
            self.working_dir = Path(os.path.dirname(os.path.abspath(__file__)))
            
        self.adb_path = self.working_dir / 'platform-tools' / ('adb.exe' if self.system == 'windows' else 'adb')
        
        # Media save location
        self.save_location = os.path.expanduser("~/Documents/OpenPelo")
        if not os.path.exists(self.save_location):
            os.makedirs(self.save_location)
        
        # Load available apps
        if getattr(sys, 'frozen', False):
            # If running from PyInstaller bundle
            base_path = Path(sys._MEIPASS)
            self.config_path = base_path / 'apps_config.json'
        else:
            # If running as normal Python script
            self.config_path = self.working_dir / 'apps_config.json'
            
        self.available_apps = self.load_config()
        
        # Setup GUI
        self.root = tk.Tk()
        self.root.title("OpenPelo")
        self.root.geometry("1000x700")  # Increased height for new section
        self.root.resizable(False, False)
        
        # Style
        self.style = ttk.Style()
        self.style.configure('Header.TLabel', font=('Helvetica', 14, 'bold'))
        self.style.configure('Status.TLabel', font=('Helvetica', 10))
        self.style.configure('Section.TLabelframe', padding=10)
        
        self.setup_gui()
        self.check_adb_thread = None
        self.install_thread = None
        self.recording_process = None
        self.is_recording = False

        # Ensure the window stays on top on launch (Windows console can steal focus)
        self.root.after(100, self._bring_to_front)

    def _subprocess_kwargs(self):
        """Common subprocess kwargs to avoid flashing a console window on Windows."""
        if self.system.startswith('win'):
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            return {
                'startupinfo': startupinfo,
                'creationflags': getattr(subprocess, 'CREATE_NO_WINDOW', 0)
            }
        return {}

    def _bring_to_front(self):
        """Bring main window to front and refocus after launch."""
        try:
            self.root.lift()
            self.root.focus_force()
            if self.system.startswith('win'):
                # Toggle topmost to ensure it raises above other windows
                self.root.attributes('-topmost', True)
                self.root.after(200, lambda: self.root.attributes('-topmost', False))
        except Exception:
            pass

    def setup_gui(self):
        # Configure grid
        self.root.grid_columnconfigure(0, weight=1)
        
        # Header (row 0)
        header = ttk.Label(
            self.root,
            text="Free Your Peloton",
            style='Header.TLabel',
            padding=(0, 10)
        )
        header.grid(row=0, column=0, columnspan=2, sticky='ew', padx=20)

        # Status frame (row 1)
        status_frame = ttk.Frame(self.root)
        status_frame.grid(row=1, column=0, columnspan=2, sticky='ew', padx=20, pady=10)
        status_frame.grid_columnconfigure(0, weight=1)
        
        self.status_label = ttk.Label(
            status_frame,
            text="Checking device connection...",
            style='Status.TLabel'
        )
        self.status_label.grid(row=0, column=0, sticky='w')

                # USB Debug Guide button
        self.debug_btn = tk.Button(
            self.root,
            text="Developer Mode Guide",
            command=self.show_debug_guide,
            bg='lightblue',
            relief='raised'
        )
        self.debug_btn.grid(row=0, column=1, padx=5, pady=0)
        
        # WiFi button
        self.wifi_btn = tk.Button(
            status_frame,
            text="📶 Connect via WiFi",
            command=self.show_wifi_guide,
            bg='lightyellow',
            relief='raised'
        )
        self.wifi_btn.grid(row=0, column=1, padx=5)
        
        self.refresh_btn = ttk.Button(
            status_frame,
            text="🔄 Refresh",
            command=self.check_device_connection
        )
        self.refresh_btn.grid(row=0, column=2, sticky='e')

        # Progress bar (row 2)
        self.progress = ttk.Progressbar(
            self.root,
            mode='indeterminate',
            length=560
        )
        self.progress.grid(row=2, column=0, columnspan=2, pady=10, padx=20)

        # Apps frame (row 4)
        self.apps_frame = ttk.LabelFrame(self.root, text="Available Apps", style='Section.TLabelframe')
        self.apps_frame.grid(row=3, column=0, columnspan=2, sticky='ew', padx=20, pady=10)
        self.apps_frame.grid_columnconfigure(0, weight=1)

        # App checkboxes
        self.app_vars = {}
        for i, (app_name, app_info) in enumerate(self.available_apps.items()):
            var = tk.BooleanVar()
            self.app_vars[app_name] = var
            
            ttk.Checkbutton(
                self.apps_frame,
                text=app_name,
                variable=var
            ).grid(row=i, column=0, sticky='w')
            
            ttk.Label(
                self.apps_frame,
                text=app_info.get('description', ''),
                style='Status.TLabel'
            ).grid(row=i, column=1, sticky='w', padx=10)

        # Buttons frame (row 4)
        buttons_frame = ttk.Frame(self.root)
        buttons_frame.grid(row=4, column=0, columnspan=2, sticky='ew', padx=20, pady=0)
        buttons_frame.grid_columnconfigure(1, weight=1)  # Space between buttons
        
        # Install button
        self.install_btn = tk.Button(
            buttons_frame,
            text="Install Selected Apps",
            command=self.install_selected_apps,
            state='disabled',
            bg='lightgreen',
            relief='raised'
        )
        self.install_btn.grid(row=0, column=3, padx=5, pady=(0, 10))

        # Install Local APK button
        self.install_local_btn = tk.Button(
            buttons_frame,
            text="Select different APK\n from computer",
            command=self.install_local_apk,
            state='disabled',
            bg='lightblue',
            relief='raised'
        )
        self.install_local_btn.grid(row=1, column=3, padx=5)

         # Media Controls Frame (row 5)
        media_frame = ttk.LabelFrame(self.root, text="Screen Recording Utility", style='Section.TLabelframe')
        media_frame.grid(row=5, column=0, columnspan=2, sticky='ew', padx=20, pady=10)
        media_frame.grid_columnconfigure(1, weight=1)

        # Save location
        ttk.Label(media_frame, text="Save Location:").grid(row=0, column=0, sticky='w', pady=5)
        self.save_location_var = tk.StringVar(value=self.save_location)
        save_entry = ttk.Entry(media_frame, textvariable=self.save_location_var, state='readonly')
        save_entry.grid(row=0, column=1, sticky='ew', padx=5)
        
        ttk.Button(
            media_frame,
            text="Browse",
            command=self.choose_save_location
        ).grid(row=0, column=2, padx=5)

        # Media buttons
        media_buttons_frame = ttk.Frame(media_frame)
        media_buttons_frame.grid(row=1, column=0, columnspan=3, pady=10)

        self.screenshot_btn = ttk.Button(
            media_buttons_frame,
            text="📸 Take Screenshot",
            command=self.take_screenshot,
            state='disabled'
        )
        self.screenshot_btn.pack(side='left', padx=5)

        self.record_btn = ttk.Button(
            media_buttons_frame,
            text="🔴 Start Recording",
            command=self.toggle_recording,
            state='disabled'
        )
        self.record_btn.pack(side='left', padx=5)

    def load_config(self):
        """Load available apps from config file, filtered by device ABI"""
        try:
            if not self.config_path.exists():
                error_msg = f"Config file not found at: {self.config_path}"
                print(error_msg)  # Also print to console for debugging
                messagebox.showerror("Error", error_msg)
                return {}
            
            with open(self.config_path, 'r') as f:
                config = json.load(f)
                all_apps = config.get('apps', {})

            # Get device ABI
            device_abi = self.get_device_abi()
            
            # Filter apps based on ABI
            if device_abi == "armeabi-v7a":
                # For gen 1 tablets, only show armeabi-v7a compatible apps
                return {name: info for name, info in all_apps.items()
                       if info.get('abi') == 'armeabi-v7a'}
            else:
                # For newer tablets, show arm64-v8a compatible apps
                return {name: info for name, info in all_apps.items()
                       if info.get('abi') == 'arm64-v8a'}
                
        except Exception as e:
            messagebox.showerror("Error", f"Error loading config: {e}")
            return {}

    def setup_adb(self):
        """Setup ADB from local files in the ADB folder if not already present"""
        if self.adb_path.exists():
            return True

        try:
            self.status_label.config(text="Extracting ADB from local files...")
            
            platform_tools_zip = {
                'windows': 'platform-tools-latest-windows.zip',
                'darwin': 'platform-tools-latest-darwin.zip',
                'linux': 'platform-tools-latest-linux.zip'
            }

            if self.system not in platform_tools_zip:
                messagebox.showerror("Error", f"Unsupported operating system: {self.system}")
                return False

            # Use local ADB files - handle PyInstaller bundled path
            # Check if running from frozen executable (PyInstaller)
            if getattr(sys, 'frozen', False):
                # If running from PyInstaller bundle - only one platform-specific zip is included
                base_path = Path(sys._MEIPASS)
                zip_filename = platform_tools_zip[self.system]
                zip_path = base_path / 'ADB' / zip_filename
            else:
                # If running as normal Python script - we might have all zips
                zip_path = self.working_dir / 'ADB' / platform_tools_zip[self.system]
                
            if not zip_path.exists():
                messagebox.showerror("Error", f"ADB file not found: {zip_path}")
                return False

            # Extract platform-tools
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                zip_ref.extractall(self.working_dir)
                
            # Note: We don't delete the zip file since it's our local copy

            # Make ADB executable on Unix-like systems
            if self.system != 'windows':
                os.chmod(self.adb_path, 0o755)

            return True
        except Exception as e:
            messagebox.showerror("Error", f"Error setting up ADB: {e}")
            return False

    def get_device_abi(self):
        """Get the device's CPU ABI"""
        try:
            result = subprocess.run(
                [str(self.adb_path), 'shell', 'getprop', 'ro.product.cpu.abi'],
                capture_output=True,
                text=True,
                **self._subprocess_kwargs()
            )
            return result.stdout.strip()
        except Exception:
            return None

    def is_device_connected(self):
        """Check if device is connected via ADB"""
        try:
            result = subprocess.run(
                [str(self.adb_path), 'devices'],
                capture_output=True,
                text=True,
                **self._subprocess_kwargs()
            )
            return len(result.stdout.strip().split('\n')) > 1
        except Exception:
            return False

    def choose_save_location(self):
        """Open directory chooser dialog"""
        new_location = filedialog.askdirectory(
            initialdir=self.save_location,
            title="Choose Save Location"
        )
        if new_location:
            self.save_location = new_location
            self.save_location_var.set(new_location)

    def take_screenshot(self):
        """Take a screenshot of the device screen"""
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"screenshot_{timestamp}.png"
            save_path = os.path.join(self.save_location, filename)
            
            # Take screenshot
            subprocess.run(
                [str(self.adb_path), 'shell', 'screencap', '-p', '/sdcard/screenshot.png'],
                check=True,
                **self._subprocess_kwargs()
            )
            
            # Pull screenshot from device
            subprocess.run(
                [str(self.adb_path), 'pull', '/sdcard/screenshot.png', save_path],
                check=True,
                **self._subprocess_kwargs()
            )
            
            # Clean up device
            subprocess.run(
                [str(self.adb_path), 'shell', 'rm', '/sdcard/screenshot.png'],
                check=True,
                **self._subprocess_kwargs()
            )
            
            messagebox.showinfo("Success", f"Screenshot saved to:\n{save_path}")
        except subprocess.CalledProcessError as e:
            messagebox.showerror("Error", f"Failed to take screenshot: {e}")

    def toggle_recording(self):
        """Toggle screen recording"""
        if not self.is_recording:
            try:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                self.current_recording = f"recording_{timestamp}.mp4"
                device_path = f"/sdcard/{self.current_recording}"
                
                # Start recording
                self.recording_process = subprocess.Popen(
                    [str(self.adb_path), 'shell', 'screenrecord', device_path],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    **self._subprocess_kwargs()
                )
                
                self.is_recording = True
                self.record_btn.config(text="⏹️ Stop Recording")
                self.screenshot_btn.config(state='disabled')
                
            except subprocess.CalledProcessError as e:
                messagebox.showerror("Error", f"Failed to start recording: {e}")
        else:
            try:
                # Stop recording
                if self.recording_process:
                    self.recording_process.terminate()
                    self.recording_process.wait(timeout=5)
                
                # Wait for the file to be written
                self.root.after(1000)
                
                # Pull recording from device
                save_path = os.path.join(self.save_location, self.current_recording)
                subprocess.run(
                    [str(self.adb_path), 'pull', f'/sdcard/{self.current_recording}', save_path],
                    check=True,
                    **self._subprocess_kwargs()
                )
                
                # Clean up device
                subprocess.run(
                    [str(self.adb_path), 'shell', 'rm', f'/sdcard/{self.current_recording}'],
                    check=True,
                    **self._subprocess_kwargs()
                )
                
                self.is_recording = False
                self.record_btn.config(text="🔴 Start Recording")
                self.screenshot_btn.config(state='normal')
                
                messagebox.showinfo("Success", f"Recording saved to:\n{save_path}")
                
            except subprocess.CalledProcessError as e:
                messagebox.showerror("Error", f"Failed to save recording: {e}")
            except Exception as e:
                messagebox.showerror("Error", f"An error occurred: {e}")

    def check_device_connection(self):
        """Check device connection in a separate thread"""
        def check():
            self.refresh_btn.config(state='disabled')
            self.progress.start()
            
            if not self.adb_path.exists():
                if not self.setup_adb():
                    self.status_label.config(
                        text="Failed to setup ADB. Please check your internet connection."
                    )
                    return
            
            if self.is_device_connected():
                # Get device ABI and update status
                device_abi = self.get_device_abi()
                abi_text = f" ({device_abi})" if device_abi else ""
                self.status_label.config(text=f"✅ Device connected{abi_text}")
                
                # Reload apps based on ABI
                self.available_apps = self.load_config()
                
                # Clear existing checkboxes
                for widget in self.apps_frame.winfo_children():
                    widget.destroy()
                
                # Recreate app checkboxes with filtered list
                self.app_vars = {}
                for i, (app_name, app_info) in enumerate(self.available_apps.items()):
                    var = tk.BooleanVar()
                    self.app_vars[app_name] = var
                    
                    ttk.Checkbutton(
                        self.apps_frame,
                        text=app_name,
                        variable=var
                    ).grid(row=i, column=0, sticky='w')
                    
                    ttk.Label(
                        self.apps_frame,
                        text=app_info.get('description', ''),
                        style='Status.TLabel'
                    ).grid(row=i, column=1, sticky='w', padx=10)
                
                self.install_btn.config(state='normal')
                self.install_local_btn.config(state='normal')
                self.screenshot_btn.config(state='normal')
                self.record_btn.config(state='normal')
            else:
                self.status_label.config(
                    text="❌ No device detected. Please connect your device and enable USB debugging."
                )
                self.install_btn.config(state='disabled')
                self.install_local_btn.config(state='disabled')
                self.screenshot_btn.config(state='disabled')
                self.record_btn.config(state='disabled')
                
                # Clear app checkboxes when no device is connected
                for widget in self.apps_frame.winfo_children():
                    widget.destroy()
                
                # Add informative text when no apps are shown
                ttk.Label(
                    self.apps_frame,
                    text="Compatible applications will be displayed here once your Peloton device is detected.",
                    style='Status.TLabel',
                    wraplength=400,
                    justify='center'
                ).grid(row=0, column=0, columnspan=2, pady=20)
            
            self.progress.stop()
            self.refresh_btn.config(state='normal')

        if not self.check_adb_thread or not self.check_adb_thread.is_alive():
            self.check_adb_thread = threading.Thread(target=check)
            self.check_adb_thread.start()

    def install_selected_apps(self):
        """Install selected apps in a separate thread"""
        selected_apps = {
            name: info for name, info in self.available_apps.items()
            if self.app_vars[name].get()
        }
        
        if not selected_apps:
            messagebox.showwarning("Warning", "Please select at least one app to install.")
            return

        def install():
            self.install_btn.config(state='disabled')
            self.refresh_btn.config(state='disabled')
            self.progress.start()

            for app_name, app_info in selected_apps.items():
                try:
                    self.status_label.config(text=f"Downloading {app_name}...")

                    # Resolve the actual download URL. If it's a GitHub URL, use the GitHub API
                    download_url = self.resolve_download_url(
                        app_info.get('url', ''),
                        app_info.get('package_name')
                    )

                    # Download the APK
                    apk_path = self.working_dir / app_info['package_name']
                    urllib.request.urlretrieve(download_url, apk_path)

                    # Install APK
                    self.status_label.config(text=f"Installing {app_name}...")
                    result = subprocess.run(
                        [str(self.adb_path), 'install', '-r', str(apk_path)],
                        capture_output=True,
                        text=True,
                        **self._subprocess_kwargs()
                    )

                    # Clean up APK file
                    apk_path.unlink()

                    if 'Success' not in result.stdout:
                        messagebox.showerror(
                            "Installation Error",
                            f"Error installing {app_name}: {result.stdout}"
                        )
                except Exception as e:
                    messagebox.showerror(
                        "Error",
                        f"Error installing {app_name}: {e}"
                    )

            self.status_label.config(text="Installation complete!")
            self.progress.stop()
            self.install_btn.config(state='normal')
            self.refresh_btn.config(state='normal')

        if not self.install_thread or not self.install_thread.is_alive():
            self.install_thread = threading.Thread(target=install)
            self.install_thread.start()

    def resolve_download_url(self, url: str, package_name: Optional[str] = None) -> str:
        """Resolve a final download URL.

        - If the URL points to GitHub (releases), query the GitHub API to find the APK asset.
        - Otherwise, return the URL as-is.

        Preference order for assets when using the API:
        1) Exact match to package_name (if provided)
        2) Any asset ending with .apk
        3) Fallback to the first asset
        """
        try:
            if not url:
                return url

            parsed = urlparse(url)
            host = (parsed.netloc or '').lower()
            path = parsed.path or ''

            is_github = 'github.com' in host or 'api.github.com' in host
            if not is_github:
                return url

            # Build API URL
            if 'api.github.com' in host:
                api_url = url
            else:
                # Convert common GitHub releases URLs to API
                # Supported patterns:
                #   /<owner>/<repo>/releases/latest
                #   /<owner>/<repo>/releases/tag/<tag>
                parts = [p for p in path.split('/') if p]
                if len(parts) >= 4 and parts[2] == 'releases':
                    owner, repo = parts[0], parts[1]
                    if parts[3] == 'latest':
                        api_url = f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
                    elif parts[3] == 'tag' and len(parts) >= 5:
                        tag = parts[4]
                        api_url = f"https://api.github.com/repos/{owner}/{repo}/releases/tags/{tag}"
                    else:
                        # Unknown releases pattern; fall back to original URL
                        return url
                else:
                    # Not a releases URL; could already be a direct asset link — use as-is
                    return url

            # Query GitHub API for assets
            with urllib.request.urlopen(api_url) as resp:
                release_data = json.loads(resp.read())
            assets = release_data.get('assets', []) or []
            if not assets:
                return url

            # Try exact match on package_name
            if package_name:
                for a in assets:
                    if a.get('name') == package_name:
                        return a.get('browser_download_url') or url

            # Then any APK
            for a in assets:
                name = a.get('name', '').lower()
                if name.endswith('.apk'):
                    return a.get('browser_download_url') or url

            # Fallback to first asset
            return assets[0].get('browser_download_url') or url

        except Exception:
            # On any error, just return the original URL
            return url

    def install_local_apk(self):
        """Install a local APK file selected by the user"""
        apk_path = filedialog.askopenfilename(
            title="Select APK File",
            filetypes=[("Android Package", "*.apk")],
            initialdir=os.path.expanduser("~")
        )
        
        if not apk_path:
            return
            
        def install():
            self.install_btn.config(state='disabled')
            self.install_local_btn.config(state='disabled')
            self.refresh_btn.config(state='disabled')
            self.progress.start()
            
            try:
                self.status_label.config(text="Installing APK...")
                result = subprocess.run(
                    [str(self.adb_path), 'install', '-r', apk_path],
                    capture_output=True,
                    text=True,
                    **self._subprocess_kwargs()
                )
                
                if 'Success' in result.stdout:
                    messagebox.showinfo("Success", "APK installed successfully!")
                    self.status_label.config(text="APK installation complete!")
                else:
                    messagebox.showerror(
                        "Installation Error",
                        f"Error installing APK: {result.stdout}"
                    )
                    self.status_label.config(text="APK installation failed.")
            except Exception as e:
                messagebox.showerror(
                    "Error",
                    f"Error installing APK: {str(e)}"
                )
                self.status_label.config(text="APK installation failed.")
            finally:
                self.progress.stop()
                self.install_btn.config(state='normal')
                self.install_local_btn.config(state='normal')
                self.refresh_btn.config(state='normal')
        
        # Run installation in a separate thread
        install_thread = threading.Thread(target=install)
        install_thread.start()

    def show_debug_guide(self):
        """Show the USB debugging guide window"""
        guide = UsbDebugGuide(self.root)
        guide.show()

    def show_wifi_guide(self):
        """Show the wireless ADB guide window"""
        guide = WirelessAdbGuide(self.root, self.adb_path, self._subprocess_kwargs())
        guide.show()

    def run(self):
        """Start the GUI application"""
        # Initial device check
        self.check_device_connection()
        # Start main loop
        self.root.mainloop()

class WirelessAdbGuide:
    def __init__(self, parent, adb_path, subprocess_kwargs):
        self.parent = parent
        self.adb_path = adb_path
        self.subprocess_kwargs = subprocess_kwargs
        self.window = tk.Toplevel(parent)
        self.window.title("Wireless ADB Setup Guide")
        self.window.geometry("500x350")
        self.window.resizable(False, False)
        
        # Load steps
        try:
            # Get the correct path whether running as script or frozen exe
            if getattr(sys, 'frozen', False):
                # Running as compiled executable
                base_path = Path(sys._MEIPASS)
                steps_path = base_path / 'wireless_adb_steps.json'
            else:
                # Running as script
                working_dir = Path(os.path.dirname(os.path.abspath(__file__)))
                steps_path = working_dir / 'wireless_adb_steps.json'
            
            with open(steps_path, 'r') as f:
                self.steps = json.load(f)['steps']
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load wireless ADB steps: {str(e)}")
            self.steps = []
        self.current_step = 0
        
        # Setup GUI
        self.setup_gui()
        
    def setup_gui(self):
        # Title
        self.title_label = ttk.Label(
            self.window,
            text="Step 1: Access Settings",
            style='Header.TLabel',
            padding=(0, 10)
        )
        self.title_label.pack(fill='x', padx=20)
        
        # Description
        self.desc_frame = ttk.Frame(self.window)
        self.desc_frame.pack(fill='both', expand=True, padx=20)
        
        self.desc_label = ttk.Label(
            self.desc_frame,
            text="",
            wraplength=460,
            justify='center',
            padding=(0, 20)
        )
        self.desc_label.pack(fill='both', expand=True)
        
        # Navigation buttons
        nav_frame = ttk.Frame(self.window)
        nav_frame.pack(fill='x', padx=20, pady=20)
        
        self.back_btn = ttk.Button(
            nav_frame,
            text="← Back",
            command=self.prev_step,
            state='disabled'
        )
        self.back_btn.pack(side='left')
        
        self.next_btn = ttk.Button(
            nav_frame,
            text="Next →",
            command=self.next_step
        )
        self.next_btn.pack(side='right')
        
        # Progress label
        self.progress_label = ttk.Label(
            nav_frame,
            text=f"Step 1 of {len(self.steps)}",
            padding=(0, 5)
        )
        self.progress_label.pack()
    
    def update_content(self):
        step = self.steps[self.current_step]
        self.title_label.config(text=f"Step {self.current_step + 1}: {step['title']}")
        self.desc_label.config(text=step['description'])
        self.progress_label.config(text=f"Step {self.current_step + 1} of {len(self.steps)}")
        
        # Update button states
        self.back_btn.config(state='normal' if self.current_step > 0 else 'disabled')
        
        # Change last step button to "Next" which will open pairing dialog
        if self.current_step == len(self.steps) - 1:
            self.next_btn.config(text="Next →")
        else:
            self.next_btn.config(text="Next →")
    
    def next_step(self):
        if self.current_step < len(self.steps) - 1:
            self.current_step += 1
            self.update_content()
        else:
            # Open pairing dialog
            self.window.destroy()
            pairing_dialog = WirelessPairingDialog(self.parent, self.adb_path, self.subprocess_kwargs)
            pairing_dialog.show()
    
    def prev_step(self):
        if self.current_step > 0:
            self.current_step -= 1
            self.update_content()
    
    def show(self):
        self.update_content()  # Initialize with first step
        self.window.grab_set()  # Make window modal
        self.window.focus_set()

class WirelessPairingDialog:
    def __init__(self, parent, adb_path, subprocess_kwargs):
        self.parent = parent
        self.adb_path = adb_path
        self.subprocess_kwargs = subprocess_kwargs
        self.window = tk.Toplevel(parent)
        self.window.title("Wireless Pairing")
        self.window.geometry("400x350")
        self.window.resizable(False, False)
        
        self.setup_gui()
    
    def setup_gui(self):
        # Header
        header = ttk.Label(
            self.window,
            text="Enter Pairing Information",
            style='Header.TLabel',
            padding=(0, 10)
        )
        header.pack(fill='x', padx=20)
        
        # Info text
        info_label = ttk.Label(
            self.window,
            text="Enter the information shown on your Peloton's wireless debugging pairing dialog:",
            wraplength=360,
            justify='center',
            padding=(0, 10)
        )
        info_label.pack(fill='x', padx=20)
        
        # Input fields frame
        input_frame = ttk.Frame(self.window)
        input_frame.pack(fill='both', expand=True, padx=20, pady=10)
        
        # IP Address
        ttk.Label(input_frame, text="IP Address:").grid(row=0, column=0, sticky='w', pady=5)
        self.ip_var = tk.StringVar()
        self.ip_entry = ttk.Entry(input_frame, textvariable=self.ip_var, width=30)
        self.ip_entry.grid(row=0, column=1, pady=5, padx=5)
        
        # Port
        ttk.Label(input_frame, text="Port:").grid(row=1, column=0, sticky='w', pady=5)
        self.port_var = tk.StringVar()
        self.port_entry = ttk.Entry(input_frame, textvariable=self.port_var, width=30)
        self.port_entry.grid(row=1, column=1, pady=5, padx=5)
        
        # Pairing Code
        ttk.Label(input_frame, text="Pairing Code:").grid(row=2, column=0, sticky='w', pady=5)
        self.code_var = tk.StringVar()
        self.code_entry = ttk.Entry(input_frame, textvariable=self.code_var, width=30)
        self.code_entry.grid(row=2, column=1, pady=5, padx=5)
        
        # Status label
        self.status_label = ttk.Label(
            self.window,
            text="",
            style='Status.TLabel',
            wraplength=360,
            justify='center'
        )
        self.status_label.pack(fill='x', padx=20, pady=10)
        
        # Buttons
        button_frame = ttk.Frame(self.window)
        button_frame.pack(fill='x', padx=20, pady=10)
        
        self.cancel_btn = ttk.Button(
            button_frame,
            text="Cancel",
            command=self.window.destroy
        )
        self.cancel_btn.pack(side='left', padx=5)
        
        self.connect_btn = tk.Button(
            button_frame,
            text="Connect",
            command=self.pair_and_connect,
            bg='lightgreen',
            relief='raised',
            state='disabled'
        )
        self.connect_btn.pack(side='right', padx=5)
        
        # Enable connect button when all fields have values
        self.ip_var.trace('w', self.check_fields)
        self.port_var.trace('w', self.check_fields)
        self.code_var.trace('w', self.check_fields)
    
    def check_fields(self, *args):
        """Enable connect button when all fields are filled"""
        if self.ip_var.get() and self.port_var.get() and self.code_var.get():
            self.connect_btn.config(state='normal')
        else:
            self.connect_btn.config(state='disabled')
    
    def pair_and_connect(self):
        """Pair and connect to the device via WiFi"""
        ip = self.ip_var.get().strip()
        port = self.port_var.get().strip()
        code = self.code_var.get().strip()
        
        if not ip or not port or not code:
            messagebox.showerror("Error", "Please fill in all fields")
            return
        
        # Disable buttons during connection
        self.connect_btn.config(state='disabled')
        self.cancel_btn.config(state='disabled')
        
        def connect():
            try:
                # Step 1: Pair with the device
                self.status_label.config(text="Pairing with device...")
                self.window.update()
                
                pair_result = subprocess.run(
                    [str(self.adb_path), 'pair', f'{ip}:{port}', code],
                    capture_output=True,
                    text=True,
                    timeout=30,
                    **self.subprocess_kwargs
                )
                
                if pair_result.returncode != 0 or 'Failed' in pair_result.stdout or 'failed' in pair_result.stderr:
                    error_msg = pair_result.stdout + pair_result.stderr
                    self.status_label.config(text="Pairing failed!")
                    messagebox.showerror(
                        "Pairing Failed",
                        f"Failed to pair with device. Please check the information and try again.\n\nError: {error_msg}"
                    )
                    self.connect_btn.config(state='normal')
                    self.cancel_btn.config(state='normal')
                    return
                
                # Step 2: Connect to the device
                # After pairing, we need to connect. The connection port is shown on the main
                # wireless debugging screen (not the pairing dialog). Try common ports.
                self.status_label.config(text="Connecting to device...")
                self.window.update()
                
                # Try to find the device's connection port by checking adb devices
                # After pairing, the device should show up
                devices_result = subprocess.run(
                    [str(self.adb_path), 'devices'],
                    capture_output=True,
                    text=True,
                    timeout=10,
                    **self.subprocess_kwargs
                )
                
                # Check if device is already connected after pairing
                if 'device' in devices_result.stdout and ip in devices_result.stdout:
                    # Device is already connected after pairing
                    self.status_label.config(text="Successfully connected!")
                    messagebox.showinfo(
                        "Success",
                        f"Successfully connected to device via WiFi!\n\nYou can now use OpenPelo wirelessly."
                    )
                    self.window.destroy()
                    return
                
                # Try common wireless debugging ports
                connection_ports = ["5555", "5556", "37000", "40000"]
                connected = False
                
                for connection_port in connection_ports:
                    try:
                        connect_result = subprocess.run(
                            [str(self.adb_path), 'connect', f'{ip}:{connection_port}'],
                            capture_output=True,
                            text=True,
                            timeout=10,
                            **self.subprocess_kwargs
                        )
                        
                        if connect_result.returncode == 0 and 'connected' in connect_result.stdout.lower():
                            connected = True
                            break
                    except:
                        continue
                
                if not connected:
                    self.status_label.config(text="Auto-connect failed!")
                    messagebox.showwarning(
                        "Connection Info Needed",
                        "Automatic connection failed. Please check the main wireless debugging screen on your Peloton for the connection IP and port (different from the pairing port), then try using 'adb connect IP:PORT' manually or restart OpenPelo and try again."
                    )
                    self.connect_btn.config(state='normal')
                    self.cancel_btn.config(state='normal')
                    return
                
                # Success
                self.status_label.config(text="Successfully connected!")
                messagebox.showinfo(
                    "Success",
                    f"Successfully connected to device via WiFi!\n\nYou can now use OpenPelo wirelessly."
                )
                self.window.destroy()
                
            except subprocess.TimeoutExpired:
                self.status_label.config(text="Connection timeout!")
                messagebox.showerror(
                    "Timeout",
                    "Connection timed out. Please make sure your Peloton and computer are on the same WiFi network and try again."
                )
                self.connect_btn.config(state='normal')
                self.cancel_btn.config(state='normal')
            except Exception as e:
                self.status_label.config(text="Connection error!")
                messagebox.showerror(
                    "Error",
                    f"An error occurred during connection:\n{str(e)}"
                )
                self.connect_btn.config(state='normal')
                self.cancel_btn.config(state='normal')
        
        # Run in a thread to avoid blocking the UI
        thread = threading.Thread(target=connect)
        thread.start()
    
    def show(self):
        self.window.grab_set()  # Make window modal
        self.window.focus_set()

class UsbDebugGuide:
    def __init__(self, parent):
        self.window = tk.Toplevel(parent)
        self.window.title("USB Debugging Guide")
        self.window.geometry("500x300")
        self.window.resizable(False, False)
        
        # Load steps
        try:
            # Get the correct path whether running as script or frozen exe
            if getattr(sys, 'frozen', False):
                # Running as compiled executable
                base_path = Path(sys._MEIPASS)
                steps_path = base_path / 'usb_debug_steps.json'
            else:
                # Running as script
                steps_path = self.working_dir / 'usb_debug_steps.json'
            
            with open(steps_path, 'r') as f:
                self.steps = json.load(f)['steps']
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load debug steps: {str(e)}")
            self.steps = []
        self.current_step = 0
        
        # Setup GUI
        self.setup_gui()
        
    def setup_gui(self):
        # Title
        self.title_label = ttk.Label(
            self.window,
            text="Step 1: Access Settings",
            style='Header.TLabel',
            padding=(0, 10)
        )
        self.title_label.pack(fill='x', padx=20)
        
        # Description
        self.desc_frame = ttk.Frame(self.window)
        self.desc_frame.pack(fill='both', expand=True, padx=20)
        
        self.desc_label = ttk.Label(
            self.desc_frame,
            text="On your tablet, tap the three dots in the bottom right corner to open the Settings menu.",
            wraplength=460,
            justify='center',
            padding=(0, 20)
        )
        self.desc_label.pack(fill='both', expand=True)
        
        # Navigation buttons
        nav_frame = ttk.Frame(self.window)
        nav_frame.pack(fill='x', padx=20, pady=20)
        
        self.back_btn = ttk.Button(
            nav_frame,
            text="← Back",
            command=self.prev_step,
            state='disabled'
        )
        self.back_btn.pack(side='left')
        
        self.next_btn = ttk.Button(
            nav_frame,
            text="Next →",
            command=self.next_step
        )
        self.next_btn.pack(side='right')
        
        # Progress label
        self.progress_label = ttk.Label(
            nav_frame,
            text=f"Step 1 of {len(self.steps)}",
            padding=(0, 5)
        )
        self.progress_label.pack()
    
    def update_content(self):
        step = self.steps[self.current_step]
        self.title_label.config(text=f"Step {self.current_step + 1}: {step['title']}")
        self.desc_label.config(text=step['description'])
        self.progress_label.config(text=f"Step {self.current_step + 1} of {len(self.steps)}")
        
        # Update button states
        self.back_btn.config(state='normal' if self.current_step > 0 else 'disabled')
        self.next_btn.config(text="Finish" if self.current_step == len(self.steps) - 1 else "Next →")
    
    def next_step(self):
        if self.current_step < len(self.steps) - 1:
            self.current_step += 1
            self.update_content()
        else:
            self.window.destroy()
    
    def prev_step(self):
        if self.current_step > 0:
            self.current_step -= 1
            self.update_content()
    
    def show(self):
        self.update_content()  # Initialize with first step
        self.window.grab_set()  # Make window modal
        self.window.focus_set()

def main():
    app = OpenPeloGUI()
    app.run()

if __name__ == "__main__":
    main()