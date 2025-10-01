import os
import sys
import platform
import urllib.request
import zipfile
import subprocess
import certifi
import ssl
import threading
import json
import tkinter as tk
from tkinter import ttk, messagebox
from pathlib import Path

class PelotonInstallerGUI:
    def __init__(self):
        self.system = platform.system().lower()
        
        # Handle different directory structures between PyInstaller and normal Python execution
        if getattr(sys, 'frozen', False):
            # If running from PyInstaller bundle
            self.working_dir = Path(os.path.dirname(sys.executable))
        else:
            # If running as normal Python script
            self.working_dir = Path(os.path.dirname(os.path.abspath(__file__)))
            
        self.adb_path = self.working_dir / 'platform-tools' / ('adb.exe' if self.system == 'windows' else 'adb')
        
        # Setup SSL for macOS
        if self.system == 'darwin':
            try:
                import certifi
            except ImportError:
                subprocess.check_call([sys.executable, "-m", "pip", "install", "certifi"])
                import certifi
            # Setup global SSL context
            ssl_context = ssl.create_default_context(cafile=certifi.where())
            opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ssl_context))
            urllib.request.install_opener(opener)
        
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
        self.root.title("Peloton App Installer")
        self.root.geometry("600x400")
        self.root.resizable(False, False)
        
        # Style
        self.style = ttk.Style()
        self.style.configure('Header.TLabel', font=('Helvetica', 14, 'bold'))
        self.style.configure('Status.TLabel', font=('Helvetica', 10))
        
        self.setup_gui()
        self.check_adb_thread = None
        self.install_thread = None

    def setup_gui(self):
        # Configure grid
        self.root.grid_columnconfigure(0, weight=1)
        
        # Header (row 0)
        header = ttk.Label(
            self.root,
            text="Peloton App Installer",
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

        # Apps frame (row 3)
        apps_frame = ttk.LabelFrame(self.root, text="Available Apps", padding=10)
        apps_frame.grid(row=3, column=0, columnspan=2, sticky='ew', padx=20, pady=10)
        apps_frame.grid_columnconfigure(0, weight=1)

        # App checkboxes
        self.app_vars = {}
        for i, (app_name, app_info) in enumerate(self.available_apps.items()):
            var = tk.BooleanVar()
            self.app_vars[app_name] = var
            
            ttk.Checkbutton(
                apps_frame,
                text=app_name,
                variable=var
            ).grid(row=i, column=0, sticky='w')
            
            ttk.Label(
                apps_frame,
                text=app_info.get('description', ''),
                style='Status.TLabel'
            ).grid(row=i, column=1, sticky='w', padx=10)

        # Buttons frame (row 4)
        buttons_frame = ttk.Frame(self.root)
        buttons_frame.grid(row=4, column=0, columnspan=2, sticky='ew', padx=20, pady=20)
        buttons_frame.grid_columnconfigure(1, weight=1)  # Space between buttons
        
        # USB Debug Guide button
        self.debug_btn = tk.Button(
            buttons_frame,
            text="Peloton Developer Mode Guide",
            command=self.show_debug_guide,
            bg='lightblue',
            relief='raised'
        )
        self.debug_btn.grid(row=0, column=0, padx=5, pady=5)
        
        # Install button
        self.install_btn = tk.Button(
            buttons_frame,
            text="Install Selected Apps",
            command=self.install_selected_apps,
            state='disabled',
            bg='lightgreen',
            relief='raised'
        )
        self.install_btn.grid(row=0, column=2, padx=5, pady=5)

    def load_config(self):
        """Load available apps from config file"""
        try:
            if not self.config_path.exists():
                error_msg = f"Config file not found at: {self.config_path}"
                print(error_msg)  # Also print to console for debugging
                messagebox.showerror("Error", error_msg)
                return {}
            
            with open(self.config_path, 'r') as f:
                config = json.load(f)
                return config.get('apps', {})
        except Exception as e:
            error_msg = f"Error loading config: {e}"
            print(error_msg)  # Also print to console for debugging
            messagebox.showerror("Error", error_msg)
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

    def is_device_connected(self):
        """Check if Peloton is connected via ADB"""
        try:
            result = subprocess.run(
                [str(self.adb_path), 'devices'],
                capture_output=True,
                text=True
            )
            return len(result.stdout.strip().split('\n')) > 1
        except Exception:
            return False

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
                self.status_label.config(text="✅ Peloton connected")
                self.install_btn.config(state='normal')
            else:
                self.status_label.config(
                    text="❌ No Peloton detected. Please connect your device and enable USB debugging."
                )
                self.install_btn.config(state='disabled')
            
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
                    
                    # Handle SmartSpin2k differently as it comes in a zip file
                    if app_name == "SmartSpin2k":
                        # Get the actual download URL from GitHub API
                        response = urllib.request.urlopen(app_info['url'])
                        release_data = json.loads(response.read())
                        zip_url = next(asset['browser_download_url'] for asset in release_data['assets'] if asset['name'].endswith('.zip'))
                        
                        # Download and process zip file
                        zip_path = self.working_dir / "smartspin2k_temp.zip"
                        urllib.request.urlretrieve(zip_url, zip_path)
                        
                        # Extract APK from zip
                        apk_path = None
                        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                            # Find the APK file in the zip
                            apk_file = next(f for f in zip_ref.namelist() if f.endswith('.apk'))
                            # Extract only the APK file
                            zip_ref.extract(apk_file, self.working_dir)
                            apk_path = self.working_dir / apk_file
                        
                        # Clean up zip file
                        zip_path.unlink()
                    else:
                        # Handle other apps normally
                        apk_path = self.working_dir / f"{app_name.lower().replace(' ', '_')}.apk"
                        urllib.request.urlretrieve(app_info['url'], apk_path)

                    # Install APK
                    self.status_label.config(text=f"Installing {app_name}...")
                    result = subprocess.run(
                        [str(self.adb_path), 'install', '-r', str(apk_path)],
                        capture_output=True,
                        text=True
                    )

                    # Clean up APK file and any extracted directories
                    apk_path.unlink()
                    if app_name == "SmartSpin2k":
                        # Clean up extracted build directory if it exists
                        build_dir = self.working_dir / "build"
                        if build_dir.exists():
                            import shutil
                            shutil.rmtree(build_dir)

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

    def show_debug_guide(self):
        """Show the USB debugging guide window"""
        guide = UsbDebugGuide(self.root)
        guide.show()

    def show_wifi_guide(self):
        """Show the wireless ADB guide window"""
        guide = WirelessAdbGuide(self.root, self.adb_path, {})
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
                
                # Step 2: Get the connection port (usually 5555, but ask user or use default)
                # The pairing port is different from the connection port
                # Typically, wireless debugging uses port 5555 for connection after pairing
                connection_port = "5555"
                
                self.status_label.config(text="Connecting to device...")
                self.window.update()
                
                connect_result = subprocess.run(
                    [str(self.adb_path), 'connect', f'{ip}:{connection_port}'],
                    capture_output=True,
                    text=True,
                    timeout=30,
                    **self.subprocess_kwargs
                )
                
                if connect_result.returncode != 0 or 'failed' in connect_result.stdout.lower():
                    error_msg = connect_result.stdout + connect_result.stderr
                    self.status_label.config(text="Connection failed!")
                    messagebox.showerror(
                        "Connection Failed",
                        f"Failed to connect to device. Please try again.\n\nError: {error_msg}"
                    )
                    self.connect_btn.config(state='normal')
                    self.cancel_btn.config(state='normal')
                    return
                
                # Success
                self.status_label.config(text="Successfully connected!")
                messagebox.showinfo(
                    "Success",
                    f"Successfully connected to device via WiFi!\n\nYou can now use the installer wirelessly."
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
                working_dir = Path(os.path.dirname(os.path.abspath(__file__)))
                steps_path = working_dir / 'usb_debug_steps.json'
            
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
            text="On your Peloton tablet, tap the three dots in the bottom right corner to open the Settings menu.",
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
    app = PelotonInstallerGUI()
    app.run()

if __name__ == "__main__":
    main()
