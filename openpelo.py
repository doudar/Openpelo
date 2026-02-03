import os
import sys
import platform
import re
import urllib.request
from urllib.parse import urlparse
import zipfile
import logging
import shlex
import subprocess
import certifi
import ssl
import threading
import time
import json
import socket
from concurrent.futures import ThreadPoolExecutor, as_completed
import tkinter as tk
from tkinter import ttk, messagebox, filedialog
from pathlib import Path
from datetime import datetime
from typing import Optional, Callable, List, Set

logging.basicConfig(level=logging.INFO)

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
        
        self._pending_log_messages = []

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
        self.root.minsize(1000, 700)
        self.root.resizable(True, True)
        
        # Style
        self.style = ttk.Style()
        self.style.configure('Header.TLabel', font=('Helvetica', 14, 'bold'))
        self.style.configure('Status.TLabel', font=('Helvetica', 10))
        self.style.configure('Section.TLabelframe', padding=10)
        
        self.setup_gui()
        self._device_name_cache = {}
        self._device_serial_cache = {}
        self._last_device_info = None
        self._last_device_count = 0
        self.check_adb_thread = None
        self.install_thread = None
        self.local_install_thread = None
        self.recording_process = None
        self.is_recording = False
        # Heartbeat / connection tracking
        self.HEARTBEAT_INTERVAL_MS = 5000  # 5s heartbeat
        self._heartbeat_running = False
        self._last_connection_state = None  # True/False
        self._last_device_abi = None
        self.wireless_dialog = None
        self.device_check_vars = {}
        self._current_devices: List[dict] = []
        self._selected_device_cache: List[str] = []
        self._processing_devices = False
        self.recording_serial = None

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

    def _close_wireless_dialog(self):
        dialog = getattr(self, 'wireless_dialog', None)
        if not dialog:
            return
        try:
            dialog.request_auto_close()
        except AttributeError:
            try:
                dialog._on_close()
            except Exception:
                try:
                    dialog.window.destroy()
                except Exception:
                    pass

    def setup_gui(self):
        # Menu Bar
        menubar = tk.Menu(self.root)
        self.tools_menu = tk.Menu(menubar, tearoff=0)
        self.tools_menu.add_command(label="Uninstall Peloton Apps", command=self.show_uninstall_tool)
        self.tools_menu.add_separator()
        self.tools_menu.add_command(label="Take Screenshot", command=self.take_screenshot, state='disabled')
        self.tools_menu.add_command(label="Start Recording", command=self.toggle_recording, state='disabled')
        menubar.add_cascade(label="Tools", menu=self.tools_menu)
        self.root.config(menu=menubar)

        # Configure grid
        self.root.grid_columnconfigure(0, weight=1)
        self.root.grid_rowconfigure(3, weight=1, minsize=90)
        self.root.grid_rowconfigure(4, weight=1)
        
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

        # Device selection panel (row 1 inside status frame)
        self.device_selection_frame = ttk.Frame(status_frame)
        self.device_selection_frame.grid(row=1, column=0, columnspan=3, sticky='ew', pady=(6, 0))
        self.device_selection_frame.grid_columnconfigure(0, weight=1)
        self.device_selection_note = ttk.Label(
            self.device_selection_frame,
            text="No devices detected.",
            style='Status.TLabel'
        )
        self.device_selection_note.grid(row=0, column=0, sticky='w')

        # Progress bar (row 2)
        self.progress = ttk.Progressbar(
            self.root,
            mode='indeterminate',
            length=560
        )
        self.progress.grid(row=2, column=0, columnspan=2, pady=10, padx=20)
        

        # ADB log frame (row 3)
        self.adb_log_frame = ttk.LabelFrame(self.root, text="ADB Messages")
        self.adb_log_frame.grid(row=3, column=0, columnspan=2, sticky='nsew', padx=20, pady=5)
        self.adb_log_frame.configure(height=200)
        
        self.adb_log = tk.Text(self.adb_log_frame, height=8, wrap='word', state='disabled')
        self.adb_log.configure(font=('TkFixedFont', 9))
        self.adb_scrollbar = ttk.Scrollbar(self.adb_log_frame, orient='vertical', command=self.adb_log.yview)
        self.adb_log.pack(side='left', fill='both', expand=True)
        self.adb_scrollbar.pack(side='right', fill='y')
        self.adb_log.config(yscrollcommand=self.adb_scrollbar.set)

        self.adb_log.tag_configure('command', foreground='#0b6fa4')
        self.adb_log.tag_configure('stdout', foreground='#1f1f1f')
        self.adb_log.tag_configure('stderr', foreground='#b00020')
        self.adb_log.tag_configure('error', foreground='#b00020', font=('Helvetica', 9, 'bold'))
        self.adb_log.tag_configure('status', foreground='#2c7a7b')
        self.adb_log.tag_configure('info', foreground='#444444')

        self._flush_pending_logs()

        # Apps frame (row 4)
        # Use default style (no internal padding) so scrollbar sits flush
        self.apps_frame = ttk.LabelFrame(self.root, text="Available Apps")
        self.apps_frame.grid(row=4, column=0, columnspan=2, sticky='nsew', padx=20, pady=10)

        # Use default border/highlight (remove 0 settings) to match Uninstaller look
        self.apps_canvas = tk.Canvas(self.apps_frame)
        self.apps_scrollbar = ttk.Scrollbar(self.apps_frame, orient='vertical', command=self.apps_canvas.yview)
        self.apps_canvas.configure(yscrollcommand=self.apps_scrollbar.set)
        
        # Pack order matches PelotonUninstaller: Content Left, Scrollbar Right
        self.apps_canvas.pack(side='left', fill='both', expand=True)
        self.apps_scrollbar.pack(side='right', fill='y')
        self.apps_canvas.pack(side='left', fill='both', expand=True)

        self.apps_inner = ttk.Frame(self.apps_canvas)
        self.apps_inner_window = self.apps_canvas.create_window((0, 0), window=self.apps_inner, anchor='nw')
        self.apps_inner.grid_columnconfigure(0, weight=0)
        self.apps_inner.grid_columnconfigure(1, weight=1)

        self.apps_inner.bind(
            '<Configure>',
            lambda event: self.apps_canvas.configure(scrollregion=self.apps_canvas.bbox('all'))
        )
        self.apps_canvas.bind(
            '<Configure>',
            lambda event: self.apps_canvas.itemconfigure(self.apps_inner_window, width=event.width)
        )

        for widget in (self.apps_canvas, self.apps_inner):
            widget.bind('<MouseWheel>', self._on_apps_mousewheel)
            widget.bind('<Button-4>', self._on_apps_mousewheel)
            widget.bind('<Button-5>', self._on_apps_mousewheel)

        self.apps_canvas.configure(height=220)

        self.app_vars = {}
        self._display_apps_placeholder()

        # Buttons frame (row 5)
        buttons_frame = ttk.Frame(self.root)
        buttons_frame.grid(row=5, column=0, columnspan=2, sticky='ew', padx=20, pady=0)
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

         # Media Settings Frame (row 6) - renamed from Screen Recording Utility
        media_frame = ttk.LabelFrame(self.root, text="Media Settings", style='Section.TLabelframe')
        media_frame.grid(row=6, column=0, columnspan=2, sticky='ew', padx=20, pady=10)
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

        ttk.Button(
            media_frame,
            text="Open Folder",
            command=self.open_save_location
        ).grid(row=0, column=3, padx=5)

    def _format_command(self, parts):
        string_parts = [str(part) for part in parts]
        try:
            return shlex.join(string_parts)
        except AttributeError:
            formatted = []
            for part in string_parts:
                if ' ' in part or '\t' in part:
                    formatted.append(f'"{part}"')
                else:
                    formatted.append(part)
            return ' '.join(formatted)

    def log_adb_message(self, message: Optional[str], tag: str = 'info'):
        if message is None:
            return
        text = str(message)
        if not text:
            return
        timestamp = datetime.now().strftime("[%H:%M:%S] ")
        lines = text.splitlines() or ['']

        if tag in ('stdout', 'status'):
            lowered = text.lower()
            if 'connected to ' in lowered or 'connected via wifi' in lowered:
                if hasattr(self, 'root'):
                    try:
                        self.root.after(0, self._close_wireless_dialog)
                    except Exception:
                        pass

        if not hasattr(self, 'adb_log') or not hasattr(self, 'root'):
            self._pending_log_messages.append((timestamp, lines, tag))
            return

        def append_lines():
            self._write_log_lines(timestamp, lines, tag)

        try:
            self.root.after(0, append_lines)
        except Exception:
            self._pending_log_messages.append((timestamp, lines, tag))

    def _format_device_checkbox_label(self, info: dict) -> str:
        name = info.get('name') or info.get('serial') or 'Device'
        transport = info.get('transport')
        if transport == 'wifi':
            if info.get('ip'):
                address = info['ip']
                if info.get('port'):
                    address = f"{address}:{info['port']}"
                return f"{name} • WiFi ({address})"
            return f"{name} • WiFi"
        return f"{name} • USB"

    def _get_selected_serials(self) -> List[str]:
        return [serial for serial, var in self.device_check_vars.items() if var.get()]

    def _set_device_selection(self, serials: List[str]):
        serial_set = set(serials)
        for serial, var in self.device_check_vars.items():
            var.set(serial in serial_set)
        self._selected_device_cache = [serial for serial in serials if serial in self.device_check_vars]

    def _choose_default_device(self, devices: List[dict]) -> Optional[str]:
        for device in devices:
            if device.get('transport') == 'wifi':
                return device.get('serial')
        return devices[0]['serial'] if devices else None

    def _update_install_buttons_state(self):
        has_device = bool(self._get_selected_serials())
        busy = False
        try:
            busy = (
                (self.install_thread and self.install_thread.is_alive())
                or (self.local_install_thread and self.local_install_thread.is_alive())
            )
        except AttributeError:
            pass

        state = 'normal' if has_device and not busy else 'disabled'
        try:
            self.install_btn.config(state=state)
            self.install_local_btn.config(state=state)
        except Exception:
            pass

    def _update_device_selection(self, devices: List[dict]):
        prev_selected = set(self._selected_device_cache or [])
        for widget in self.device_selection_frame.winfo_children():
            widget.destroy()

        self.device_check_vars = {}

        if not devices:
            self.device_selection_note = ttk.Label(
                self.device_selection_frame,
                text="No devices detected.",
                style='Status.TLabel'
            )
            self.device_selection_note.grid(row=0, column=0, sticky='w')
            self._selected_device_cache = []
            self._update_install_buttons_state()
            return

        instructions = ttk.Label(
            self.device_selection_frame,
            text="Select the device(s) to target.",
            style='Status.TLabel'
        )
        instructions.grid(row=0, column=0, sticky='w', pady=(0, 4))

        for idx, device in enumerate(devices, start=1):
            serial = device.get('serial')
            var = tk.BooleanVar(value=serial in prev_selected)
            chk = ttk.Checkbutton(
                self.device_selection_frame,
                text=self._format_device_checkbox_label(device),
                variable=var,
                command=self.on_device_selection_change
            )
            chk.grid(row=idx, column=0, sticky='w', pady=2)
            self.device_check_vars[serial] = var

        if not any(var.get() for var in self.device_check_vars.values()):
            default_serial = self._choose_default_device(devices)
            if default_serial:
                self.device_check_vars[default_serial].set(True)

        self._selected_device_cache = self._get_selected_serials()
        self._update_install_buttons_state()

    def on_device_selection_change(self):
        self._selected_device_cache = self._get_selected_serials()
        self._update_install_buttons_state()
        if self._current_devices:
            self._process_connected_devices(self._current_devices, update_selection=False)

    def _require_single_device(self, action: str) -> Optional[str]:
        selected = self._get_selected_serials()
        if not selected:
            messagebox.showwarning("No Device Selected", f"Select a device to {action}.")
            return None
        if len(selected) > 1:
            messagebox.showwarning(
                "Multiple Devices Selected",
                f"Select only one device to {action}."
            )
            return None
        return selected[0]

    def _process_connected_devices(self, devices: List[dict], update_selection: bool) -> bool:
        if self._processing_devices:
            return bool(devices)
        self._processing_devices = True
        try:
            self._current_devices = list(devices)
            previous_count = self._last_device_count
            previous_info = self._last_device_info or {}
            previous_serial = previous_info.get('serial')
            previous_ip = previous_info.get('ip')
            previous_transport = previous_info.get('transport')
            previous_abi = self._last_device_abi

            if update_selection:
                self._update_device_selection(devices)

            selected = [
                serial for serial in self._selected_device_cache
                if any(d.get('serial') == serial for d in devices)
            ]
            self._set_device_selection(selected)

            if devices and not self._selected_device_cache:
                default_serial = self._choose_default_device(devices)
                if default_serial:
                    self._set_device_selection([default_serial])

            has_selection = bool(self._selected_device_cache)

            if not devices:
                self.status_label.config(
                    text="❌ No device detected. Please connect your device and enable USB debugging."
                )
                self._display_apps_placeholder()
                self._last_device_info = None
                self._last_device_abi = None
                self._last_device_count = 0
                self._selected_device_cache = []
                # Update Tools Menu
                try:
                    self.tools_menu.entryconfig("Take Screenshot", state='disabled')
                except Exception: pass
                if not self.is_recording:
                    try:
                         self.tools_menu.entryconfig("Start Recording", state='disabled')
                    except Exception: pass
                self._update_install_buttons_state()
                return False

            primary_device = None
            if has_selection:
                target_serial = self._selected_device_cache[0]
                primary_device = next((d for d in devices if d.get('serial') == target_serial), None)
            if not primary_device:
                primary_device = next((d for d in devices if d.get('transport') == 'wifi'), devices[0])
                if primary_device:
                    self._set_device_selection([primary_device.get('serial')])
                    has_selection = True

            device_abi = self.get_device_abi(primary_device['serial']) if primary_device else None
            resolved_abi = device_abi or previous_abi

            status_text = self._build_connection_status(primary_device, resolved_abi) if primary_device else "✅ Connected"
            extra_selected = len(self._selected_device_cache) - 1
            if extra_selected > 0:
                status_text = f"{status_text} (+{extra_selected} more)"
            self.status_label.config(text=status_text)

            if len(devices) > 1 and len(devices) != previous_count and primary_device:
                self.log_adb_message(
                    f"Multiple devices detected. Prioritizing {primary_device['serial']} ({primary_device['transport']}).",
                    tag='info'
                )

            should_reload_apps = (
                self._last_connection_state is not True
                or (primary_device and previous_serial != primary_device['serial'])
                or (primary_device and primary_device.get('transport') != previous_transport)
                or (device_abi and device_abi != previous_abi)
            )

            if should_reload_apps:
                self.available_apps = self.load_config(resolved_abi)
                self._render_available_apps()

            if primary_device and (
                self._last_connection_state is not True
                or previous_serial != primary_device.get('serial')
                or previous_ip != primary_device.get('ip')
                or previous_transport != primary_device.get('transport')
            ):
                self.log_adb_message(status_text, tag='status')

            self.install_btn.config(state='normal' if has_selection else 'disabled')
            self.install_local_btn.config(state='normal' if has_selection else 'disabled')
            if not has_selection:
                self.status_label.config(text="Select a device to continue.")
                try:
                    self.tools_menu.entryconfig("Take Screenshot", state='disabled')
                except Exception: pass
                if not self.is_recording:
                    try:
                        self.tools_menu.entryconfig("Start Recording", state='disabled')
                    except Exception: pass
                self._display_apps_placeholder("Select a device to view compatible applications.")
            else:
                try:
                    self.tools_menu.entryconfig("Take Screenshot", state='normal')
                except Exception: pass
                if not self.is_recording:
                    try:
                        self.tools_menu.entryconfig("Start Recording", state='normal')
                    except Exception: pass
            if self.is_recording:
                try:
                    self.tools_menu.entryconfig("Start Recording", state='normal')
                except Exception: pass

            self._last_device_info = primary_device
            self._last_device_abi = resolved_abi or None
            self._last_device_count = len(devices)
            self._update_install_buttons_state()
            return True
        finally:
            self._processing_devices = False

    def _write_log_lines(self, timestamp: str, lines, tag: str):
        if not hasattr(self, 'adb_log'):
            self._pending_log_messages.append((timestamp, lines, tag))
            return
        try:
            self.adb_log.configure(state='normal')
            for idx, line in enumerate(lines):
                prefix = timestamp if idx == 0 else ' ' * len(timestamp)
                self.adb_log.insert('end', f"{prefix}{line}\n", (tag,))
            self.adb_log.configure(state='disabled')
            self.adb_log.see('end')
        except tk.TclError:
            self._pending_log_messages.append((timestamp, lines, tag))

    def _flush_pending_logs(self):
        if not getattr(self, '_pending_log_messages', None):
            return
        pending = list(self._pending_log_messages)
        self._pending_log_messages.clear()
        for timestamp, lines, tag in pending:
            self._write_log_lines(timestamp, lines, tag)

    def adb_run(self, *adb_args, log_to_panel: bool = True, **kwargs):
        command = [str(self.adb_path), *[str(arg) for arg in adb_args]]
        run_kwargs = self._subprocess_kwargs().copy()
        run_kwargs.update(kwargs)

        if 'text' not in run_kwargs and (
            run_kwargs.get('capture_output') or ('stdout' not in run_kwargs and 'stderr' not in run_kwargs)
        ):
            run_kwargs.setdefault('text', True)

        if 'capture_output' not in run_kwargs and 'stdout' not in run_kwargs and 'stderr' not in run_kwargs:
            run_kwargs['capture_output'] = True

        capture_output = run_kwargs.get('capture_output', False)

        if log_to_panel:
            self.log_adb_message(f"$ {self._format_command(command)}", tag='command')

        try:
            result = subprocess.run(command, **run_kwargs)
        except subprocess.CalledProcessError as exc:
            if log_to_panel:
                if exc.stdout:
                    self.log_adb_message(exc.stdout.rstrip(), tag='stdout')
                if exc.stderr:
                    self.log_adb_message(exc.stderr.rstrip(), tag='stderr')
                self.log_adb_message(f"Command failed with exit code {exc.returncode}", tag='error')
            raise
        except Exception as exc:
            if log_to_panel:
                self.log_adb_message(f"Command error: {exc}", tag='error')
            raise

        if log_to_panel and capture_output:
            if result.stdout:
                self.log_adb_message(result.stdout.rstrip(), tag='stdout')
            if result.stderr:
                self.log_adb_message(result.stderr.rstrip(), tag='stderr')

        return result

    def _adb_shell_getprop(self, prop: str, serial: Optional[str] = None) -> str:
        args = []
        if serial:
            args.extend(['-s', serial])
        args.extend(['shell', 'getprop', prop])
        try:
            result = self.adb_run(*args, log_to_panel=False, timeout=5)
            return (result.stdout or '').strip()
        except Exception:
            return ''

    def get_device_name(self, serial: Optional[str]) -> str:
        if not serial:
            return ''
        if serial in self._device_name_cache:
            return self._device_name_cache[serial]

        manufacturer = self._adb_shell_getprop('ro.product.manufacturer', serial)
        model = self._adb_shell_getprop('ro.product.model', serial)

        name_parts = []
        if manufacturer:
            name_parts.append(manufacturer.strip().title())
        if model:
            name_parts.append(model.strip())

        friendly_name = ' '.join(name_parts).strip() or serial
        self._device_name_cache[serial] = friendly_name
        return friendly_name

    def get_physical_serial(self, serial: Optional[str]) -> str:
        if not serial:
            return ''
        if serial in self._device_serial_cache:
            return self._device_serial_cache[serial]

        physical = self._adb_shell_getprop('ro.serialno', serial) or ''
        self._device_serial_cache[serial] = physical
        return physical

    def get_connected_devices(self, log: bool = False):
        try:
            result = self.adb_run('devices', log_to_panel=log, timeout=5)
        except Exception:
            return []

        output = (result.stdout or '').splitlines()
        lines = [line.strip() for line in output if line.strip()]
        if len(lines) <= 1:
            return []

        devices = []
        for raw in lines[1:]:
            if '\t' in raw:
                serial, status = raw.split('\t', 1)
            else:
                parts = raw.split()
                if len(parts) < 2:
                    continue
                serial, status = parts[0], parts[-1]
            serial = serial.strip()
            status = status.strip()
            if status != 'device':
                continue

            is_mdns_alias = serial.startswith('adb-') and serial.endswith('-tcp')

            if ':' in serial:
                transport = 'wifi'
                host, _, host_port = serial.partition(':')
                ip = host
                port = host_port or None
            elif is_mdns_alias:
                transport = 'wifi'
                ip, port = None, None
            else:
                transport = 'usb'
                ip, port = None, None

            devices.append({
                'serial': serial,
                'transport': transport,
                'ip': ip,
                'port': port,
                'name': self.get_device_name(serial),
                'physical_serial': self.get_physical_serial(serial) or serial,
                '_mdns_alias': is_mdns_alias
            })

        has_direct_wifi = any(d['transport'] == 'wifi' and not d.get('_mdns_alias') for d in devices)
        if has_direct_wifi:
            devices = [
                d for d in devices
                if not (d['transport'] == 'wifi' and d.get('_mdns_alias'))
            ]

            wifi_physical_serials = {
                d.get('physical_serial')
                for d in devices
                if d['transport'] == 'wifi' and d.get('physical_serial')
            }

            if wifi_physical_serials:
                devices = [
                    d for d in devices
                    if not (
                        d['transport'] == 'usb'
                        and (d.get('physical_serial') or d.get('serial')) in wifi_physical_serials
                    )
                ]

            for device in devices:
                device.pop('_mdns_alias', None)

        return devices

    def _build_connection_status(self, device_info: Optional[dict], abi: Optional[str] = None) -> str:
        if not device_info:
            base = "✅ Connected"
        else:
            name = device_info.get('name') or device_info.get('serial') or 'device'
            transport = device_info.get('transport')
            if transport == 'wifi' and device_info.get('ip'):
                address = device_info['ip']
                if device_info.get('port'):
                    address = f"{address}:{device_info['port']}"
                base = f"✅ Connected to {name} on {address}"
            else:
                base = f"✅ Connected to {name}"

        if abi:
            base = f"{base} ({abi})"

        return base

    def _clear_apps_view(self):
        if not hasattr(self, 'apps_inner'):
            return
        for widget in self.apps_inner.winfo_children():
            widget.destroy()
        if hasattr(self, 'apps_canvas'):
            try:
                self.apps_canvas.yview_moveto(0)
            except Exception:
                pass

    def _on_apps_mousewheel(self, event):
        canvas = getattr(self, 'apps_canvas', None)
        if canvas is None:
            return 'break'
        try:
            if getattr(event, 'delta', 0):
                direction = -1 if event.delta > 0 else 1
                canvas.yview_scroll(direction, 'units')
            elif getattr(event, 'num', None) in (4, 5):
                direction = -1 if event.num == 4 else 1
                canvas.yview_scroll(direction, 'units')
        except Exception:
            pass
        return 'break'

    def _display_apps_placeholder(self, message: Optional[str] = None):
        placeholder = message or (
            "Compatible applications will be displayed here once your Peloton device is detected."
        )
        self._clear_apps_view()
        self.app_vars = {}
        ttk.Label(
            self.apps_inner,
            text=placeholder,
            style='Status.TLabel',
            wraplength=440,
            justify='center'
        ).grid(row=0, column=0, sticky='nsew', padx=10, pady=20)

    def _render_available_apps(self):
        self._clear_apps_view()
        self.app_vars = {}

        if not self.available_apps:
            self._display_apps_placeholder("No compatible applications found for this device.")
            return

        for i, (app_name, app_info) in enumerate(self.available_apps.items()):
            var = tk.BooleanVar()
            self.app_vars[app_name] = var

            ttk.Checkbutton(
                self.apps_inner,
                text=app_name,
                variable=var
            ).grid(row=i, column=0, sticky='w', padx=(10, 0), pady=2)

            ttk.Label(
                self.apps_inner,
                text=app_info.get('description', ''),
                style='Status.TLabel'
            ).grid(row=i, column=1, sticky='w', padx=10, pady=2)

    def load_config(self, device_abi: Optional[str] = None):
        """Load available apps from config file, filtered by device ABI."""
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
            if device_abi is None:
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

    def get_device_abi(self, serial: Optional[str] = None) -> Optional[str]:
        """Get the device's CPU ABI."""
        args = []
        if serial:
            args.extend(['-s', serial])
        args.extend(['shell', 'getprop', 'ro.product.cpu.abi'])
        try:
            result = self.adb_run(*args, log_to_panel=False, timeout=5)
            return (result.stdout or '').strip()
        except Exception:
            return None

    def is_device_connected(self) -> bool:
        """Check if at least one device is connected via ADB."""
        return bool(self.get_connected_devices())

    def _schedule_heartbeat(self):
        if not self._heartbeat_running:
            return
        # Schedule next tick
        self.root.after(self.HEARTBEAT_INTERVAL_MS, self._heartbeat_tick)

    def _heartbeat_tick(self):
        """Periodic lightweight device status check; only triggers full refresh on state change."""
        try:
            # Avoid overlapping with an active check or install thread
            busy = (self.check_adb_thread and self.check_adb_thread.is_alive()) or \
                   (self.install_thread and self.install_thread.is_alive())
            if not busy:
                devices = self.get_connected_devices()
                connected_now = bool(devices)
                if connected_now != self._last_connection_state:
                    # State changed: run full refresh
                    self.check_device_connection()
                elif connected_now:
                    primary = next((d for d in devices if d['transport'] == 'wifi'), devices[0])
                    self._last_device_info = primary
                    status_text = self._build_connection_status(primary, self._last_device_abi)
                    self.status_label.config(text=status_text)
                    self._last_device_count = len(devices)
                else:
                    # Still disconnected; keep message consistent
                    self.status_label.config(
                        text="❌ No device detected. Please connect your device and enable USB debugging."
                    )
                    self._last_device_count = 0
        finally:
            self._schedule_heartbeat()

    def start_heartbeat(self):
        if not self._heartbeat_running:
            self._heartbeat_running = True
            # Quick first tick
            self.root.after(1500, self._heartbeat_tick)

    def choose_save_location(self):
        """Open directory chooser dialog"""
        new_location = filedialog.askdirectory(
            initialdir=self.save_location,
            title="Choose Save Location"
        )
        if new_location:
            self.save_location = new_location
            self.save_location_var.set(new_location)

    def open_save_location(self):
        """Open the save location folder in file explorer"""
        path = self.save_location
        if not os.path.exists(path):
            messagebox.showwarning("Warning", "Save location does not exist.")
            return
            
        try:
            if self.system == 'windows':
                os.startfile(path)
            elif self.system == 'darwin':
                subprocess.Popen(['open', path])
            else:
                subprocess.Popen(['xdg-open', path])
        except Exception as e:
            messagebox.showerror("Error", f"Could not open folder: {e}")

    def take_screenshot(self):
        """Take a screenshot of the device screen"""
        serial = self._require_single_device("take a screenshot")
        if not serial:
            return
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"screenshot_{timestamp}.png"
            save_path = os.path.join(self.save_location, filename)
            
            # Take screenshot
            self.adb_run('-s', serial, 'shell', 'screencap', '-p', '/sdcard/screenshot.png', check=True)

            # Pull screenshot from device
            self.adb_run('-s', serial, 'pull', '/sdcard/screenshot.png', save_path, check=True)

            # Clean up device
            self.adb_run('-s', serial, 'shell', 'rm', '/sdcard/screenshot.png', check=True)
            
            messagebox.showinfo("Success", f"Screenshot saved to:\n{save_path}")
            self.log_adb_message(f"Screenshot saved to {save_path}", tag='status')
        except subprocess.CalledProcessError as e:
            messagebox.showerror("Error", f"Failed to take screenshot: {e}")

    def toggle_recording(self):
        """Toggle screen recording"""
        if not self.is_recording:
            serial = self._require_single_device("record the screen")
            if not serial:
                return
            try:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                self.current_recording = f"recording_{timestamp}.mp4"
                device_path = f"/sdcard/{self.current_recording}"
                self.recording_serial = serial
                
                # Start recording
                record_cmd = [str(self.adb_path), '-s', serial, 'shell', 'screenrecord', device_path]
                self.log_adb_message(f"$ {self._format_command(record_cmd)}", tag='command')
                self.log_adb_message(f"Recording started: {device_path}", tag='info')
                self.recording_process = subprocess.Popen(
                    record_cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    **self._subprocess_kwargs()
                )
                
                self.is_recording = True
                try:
                    self.tools_menu.entryconfig("Start Recording", label="Stop Recording")
                except Exception: pass
                try:
                    self.tools_menu.entryconfig("Take Screenshot", state='disabled')
                except Exception: pass
                
            except subprocess.CalledProcessError as e:
                self.recording_serial = None
                if self._current_devices:
                    self._process_connected_devices(self._current_devices, update_selection=False)
                messagebox.showerror("Error", f"Failed to start recording: {e}")
            except Exception as e:
                self.recording_serial = None
                if self._current_devices:
                    self._process_connected_devices(self._current_devices, update_selection=False)
                messagebox.showerror("Error", f"Failed to start recording: {e}")
        else:
            try:
                serial = self.recording_serial or self._require_single_device("stop recording")
                if not serial:
                    return
                # Stop recording
                if self.recording_process:
                    self.recording_process.terminate()
                    self.recording_process.wait(timeout=5)
                    self.log_adb_message("Screen recording stopped", tag='info')
                self.recording_process = None
                
                # Wait for the file to be written
                self.root.after(1000)
                
                # Pull recording from device
                save_path = os.path.join(self.save_location, self.current_recording)
                self.adb_run('-s', serial, 'pull', f'/sdcard/{self.current_recording}', save_path, check=True)
                
                # Clean up device
                self.adb_run('-s', serial, 'shell', 'rm', f'/sdcard/{self.current_recording}', check=True)
                
                self.is_recording = False
                try: 
                    self.tools_menu.entryconfig("Stop Recording", label="Start Recording") 
                except Exception: pass
                try:
                    self.tools_menu.entryconfig("Take Screenshot", state='normal')
                except Exception: pass
                self.recording_serial = None
                if self._current_devices:
                    self._process_connected_devices(self._current_devices, update_selection=False)
                
                messagebox.showinfo("Success", f"Recording saved to:\n{save_path}")
                self.log_adb_message(f"Recording saved to {save_path}", tag='status')
                
            except subprocess.CalledProcessError as e:
                self.is_recording = False
                try: 
                    self.tools_menu.entryconfig("Stop Recording", label="Start Recording") 
                except Exception: pass
                self.recording_serial = None
                self.recording_process = None
                if self._current_devices:
                    self._process_connected_devices(self._current_devices, update_selection=False)
                messagebox.showerror("Error", f"Failed to save recording: {e}")
            except Exception as e:
                self.is_recording = False
                try: 
                    self.tools_menu.entryconfig("Stop Recording", label="Start Recording") 
                except Exception: pass
                self.recording_serial = None
                self.recording_process = None
                if self._current_devices:
                    self._process_connected_devices(self._current_devices, update_selection=False)
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
            
            devices = self.get_connected_devices(log=True)
            connected = self._process_connected_devices(devices, update_selection=True)
            self._last_connection_state = connected
            
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

        serial = self._require_single_device("install the selected apps")
        if not serial:
            return

        device_label = next(
            (
                f"{info.get('name') or serial}"
                for info in self._current_devices
                if info.get('serial') == serial
            ),
            serial
        )

        def install():
            self.install_btn.config(state='disabled')
            self.install_local_btn.config(state='disabled')
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
                    result = self.adb_run('-s', serial, 'install', '-r', '-d', '-g', '-t', str(apk_path))
                    
                    output = (result.stdout or '') + (result.stderr or '')

                    if 'INSTALL_FAILED_UPDATE_INCOMPATIBLE' in output:
                        # Try to parse properties package name first
                        match = re.search(r'Package\s+([a-zA-Z0-9_\.]+)\s+signatures', output)
                        conflicting_pkg = match.group(1) if match else app_info.get('package_name')

                        if messagebox.askyesno(
                            "App Update Required",
                            f"The installed version of '{app_name}' is not compatible with this update.\n\n"
                            "Would you like to uninstall the old version and install the new one?\n"
                            "(Your app data will be reset)",
                            icon='warning'
                        ):
                            self.previous_status = self.status_label.cget("text")
                            self.status_label.config(text=f"Uninstalling old {app_name}...")
                            self.adb_run('-s', serial, 'uninstall', conflicting_pkg)
                            self.status_label.config(text=f"Retrying install of {app_name}...")
                            result = self.adb_run('-s', serial, 'install', '-r', '-d', '-g', '-t', str(apk_path))
                            output = (result.stdout or '') + (result.stderr or '')

                    # Clean up APK file
                    apk_path.unlink()

                    if 'Success' not in result.stdout:
                        messagebox.showerror(
                            "Installation Error",
                            f"Error installing {app_name}: {output}"
                        )
                    else:
                        self.log_adb_message(f"{app_name} installed successfully.", tag='status')
                except Exception as e:
                    messagebox.showerror(
                        "Error",
                        f"Error installing {app_name}: {e}"
                    )

            self.status_label.config(text=f"Installation complete on {device_label}!")
            self.progress.stop()
            self.install_thread = None
            self._update_install_buttons_state()
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

        serial = self._require_single_device("install the APK")
        if not serial:
            return
            
        def install():
            self.install_btn.config(state='disabled')
            self.install_local_btn.config(state='disabled')
            self.refresh_btn.config(state='disabled')
            self.progress.start()
            
            try:
                self.status_label.config(text="Installing APK...")
                result = self.adb_run('-s', serial, 'install', '-r', '-d', '-g', '-t', apk_path)
                
                output = (result.stdout or '') + (result.stderr or '')
                
                if 'INSTALL_FAILED_UPDATE_INCOMPATIBLE' in output:
                    self.log_adb_message(f"Signature mismatch detected. Parsing package name...", tag='info')
                    # Search specifically for the package name in the error message
                    match = re.search(r'Package\s+([a-zA-Z0-9_\.]+)\s+signatures', output)
                    pkg_name = match.group(1) if match else None
                    
                    if pkg_name:
                        self.log_adb_message(f"Found conflicting package: {pkg_name}", tag='info')
                        if messagebox.askyesno(
                            "App Update Required",
                            f"The installed version of '{pkg_name}' is not compatible with this update.\n\n"
                            "Would you like to uninstall the old version and install the new one?\n"
                            "(Your app data will be reset)",
                            icon='warning'
                        ):
                             self.status_label.config(text=f"Uninstalling {pkg_name}...")
                             self.adb_run('-s', serial, 'uninstall', pkg_name)
                             self.status_label.config(text="Retrying installation...")
                             result = self.adb_run('-s', serial, 'install', '-r', '-d', '-g', '-t', apk_path)
                    else:
                        self.log_adb_message("Could not extract package name from error message.", tag='error')

                if 'Success' in result.stdout:
                    messagebox.showinfo("Success", "APK installed successfully!")
                    self.status_label.config(text="APK installation complete!")
                    self.log_adb_message(f"Installed {Path(apk_path).name} successfully.", tag='status')
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
                self.local_install_thread = None
                self._update_install_buttons_state()
                self.refresh_btn.config(state='normal')
        
        # Run installation in a separate thread
        install_thread = threading.Thread(target=install)
        self.local_install_thread = install_thread
        install_thread.start()

    def show_debug_guide(self):
        """Show the USB debugging guide window"""
        guide = UsbDebugGuide(self.root)
        guide.show()

    def show_uninstall_tool(self):
        """Show the Peloton uninstaller tool"""
        tool = PelotonUninstaller(self.root, self)
        tool.show()

    def show_wifi_guide(self):
        """Show the wireless ADB guide window"""
        guide = WirelessAdbGuide(self.root, self.adb_path, self._subprocess_kwargs(), app=self)
        guide.show()

    def run(self):
        """Start the GUI application"""
        # Initial device check
        self.check_device_connection()
        # Start heartbeat after initial check
        self.start_heartbeat()
        # Start main loop
        self.root.mainloop()

class WirelessAdbGuide:
    def __init__(self, parent, adb_path, subprocess_kwargs, app=None):
        self.parent = parent
        self.adb_path = adb_path
        self.subprocess_kwargs = subprocess_kwargs
        self.app = app  # Reference to main application for triggering refresh
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
            pairing_dialog = WirelessPairingDialog(self.parent, self.adb_path, self.subprocess_kwargs, app=self.app)
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
    # Allow up to two minutes for devices to expose the connect service after pairing
    CONNECT_WAIT_SECONDS = 120
    # Minimum interval between mdns refresh attempts while waiting
    MDNS_REFRESH_INTERVAL = 10
    # Short pause when waiting for missing connection info
    MISSING_INFO_WAIT = 3
    # Pause between connection retry attempts
    CONNECT_RETRY_WAIT = 5
    # Timeout for adb mdns discovery calls
    MDNS_DISCOVERY_TIMEOUT = 10
    # Timeout for adb pair command
    PAIR_TIMEOUT_SECONDS = 90
    # Timeout for adb connect command
    CONNECT_COMMAND_TIMEOUT = 20

    def __init__(self, parent, adb_path, subprocess_kwargs, app=None):
        self.parent = parent
        self.adb_path = adb_path
        self.subprocess_kwargs = subprocess_kwargs
        self.app = app  # Main app reference for immediate UI update
        self.window = tk.Toplevel(parent)
        self.window.title("Wireless Pairing")
        self.window.geometry("520x520")
        self.window.resizable(False, False)
        self.window.protocol("WM_DELETE_WINDOW", self._on_close)
        
        if self.app:
            self._run_adb = lambda *args, **kwargs: self.app.adb_run(*args, **kwargs)
        else:
            def _runner(*args, **kwargs):
                params = (self.subprocess_kwargs or {}).copy()
                params.setdefault('capture_output', True)
                params.setdefault('text', True)
                params.update(kwargs)
                return subprocess.run([str(self.adb_path), *args], **params)
            self._run_adb = _runner
        
        self.discovered_devices = {}
        self.device_index_map = []
        self.selected_device_key = None
        self._port_scan_thread = None
        self._port_scan_stop = None
        self._port_scan_target = None
        self._port_prompt = None
        self._port_progress_dialog = None
        self._port_progress_bar = None
        self._manual_port_mode = False
        self._pairing_in_progress = False
        self._current_scan_ignore_ports = set()
        self._port_scan_total = 0
        
        self.setup_gui()
        if self.app:
            self.app.wireless_dialog = self
    
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
            text="Select your Peloton from the scan results and enter the pairing code shown on the wireless debugging screen. Most fields will auto-fill after scanning.",
            wraplength=480,
            justify='center',
            padding=(0, 10)
        )
        info_label.pack(fill='x', padx=20)

        devices_frame = ttk.LabelFrame(self.window, text="Discovered Devices")
        devices_frame.pack(fill='both', expand=False, padx=20, pady=(0, 10))

        controls_frame = ttk.Frame(devices_frame)
        controls_frame.pack(fill='x', padx=5, pady=(5, 0))

        self.scan_btn = ttk.Button(
            controls_frame,
            text="Scan for devices",
            command=self.scan_for_devices
        )
        self.scan_btn.pack(side='right')

        self.devices_list = tk.Listbox(devices_frame, height=5, activestyle='dotbox')
        self.devices_list.pack(fill='both', expand=True, padx=5, pady=5)
        self.devices_list.bind('<<ListboxSelect>>', self.on_device_select)

        self.no_devices_label = ttk.Label(
            devices_frame,
            text="No devices found yet. Open the wireless debugging pairing screen on your Peloton, then click Scan.",
            style='Status.TLabel',
            wraplength=440,
            justify='center'
        )
        self.no_devices_label.pack(fill='x', padx=5, pady=(0, 5))
        
        # Input fields frame
        input_frame = ttk.Frame(self.window)
        input_frame.pack(fill='both', expand=True, padx=20, pady=10)

        # Pairing Code
        ttk.Label(input_frame, text="Pairing Code:").grid(row=0, column=0, sticky='w', pady=5)
        self.code_var = tk.StringVar()
        self.code_entry = ttk.Entry(input_frame, textvariable=self.code_var, width=30)
        self.code_entry.grid(row=0, column=1, pady=5, padx=5)

        # IP Address
        ttk.Label(input_frame, text="IP Address:").grid(row=1, column=0, sticky='w', pady=5)
        self.ip_var = tk.StringVar()
        self.ip_entry = ttk.Entry(input_frame, textvariable=self.ip_var, width=30)
        self.ip_entry.grid(row=1, column=1, pady=5, padx=5)
        
        # Port
        ttk.Label(input_frame, text="Port from pairing screen:").grid(row=2, column=0, sticky='w', pady=5)
        self.port_var = tk.StringVar()
        self.port_entry = ttk.Entry(input_frame, textvariable=self.port_var, width=30)
        self.port_entry.grid(row=2, column=1, pady=5, padx=5)
        
        # Connection Port
        ttk.Label(input_frame, text="Port from wireless debugging screen:").grid(row=3, column=0, sticky='w', pady=5)
        self.conport_var = tk.StringVar()
        self.conport_entry = ttk.Entry(input_frame, textvariable=self.conport_var, width=30)
        self.conport_entry.grid(row=3, column=1, pady=5, padx=5)

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
            command=self._on_close
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
        self.conport_var.trace('w', self.check_fields)
        self.conport_entry.config(state='normal')

    def _parse_mdns_services(self, output: str):
        devices = {}
        unparsed = []

        def parse_host_port(token: str):
            host = token.strip()
            port = None
            if not host:
                return host, port
            if host.startswith('['):
                closing = host.find(']')
                if closing != -1:
                    remainder = host[closing + 1:]
                    candidate = remainder.lstrip(':')
                    host = host[1:closing]
                    if candidate.isdigit():
                        port = candidate
                        return host, port
            if ':' in host:
                candidate_host, candidate_port = host.rsplit(':', 1)
                if candidate_port.isdigit():
                    return candidate_host.strip('[]'), candidate_port
            return host.strip('[]'), port

        def build_service_name(instance: str, service_type: str) -> str:
            base = f"{instance}.{service_type}".rstrip('.')
            if not base.endswith('.local'):
                base = f"{base}.local"
            if not base.endswith('.'):
                base = f"{base}."
            return base

        for raw in (output or '').splitlines():
            line = raw.strip()
            if not line or line.lower().startswith('list of discovered'):
                continue
            if line.startswith('====') or line.startswith('----'):
                continue

            parts = line.split()
            if len(parts) < 3:
                unparsed.append(raw)
                continue

            instance = parts[0].strip().rstrip('.')
            service_type = parts[1].strip().rstrip('.')
            host_port_token = parts[-1]
            host, port = parse_host_port(host_port_token)

            if port is None and len(parts) >= 4 and parts[-1].isdigit():
                port = parts[-1]
                host = parts[-2]

            if not instance or not host or not port:
                unparsed.append(raw)
                continue

            key = instance
            entry = devices.setdefault(key, {'name': key})

            service_name = build_service_name(instance, service_type)
            if '_adb-tls-pairing' in service_type:
                entry.update({
                    'pairing_service': service_name,
                    'pairing_ip': host,
                    'pairing_port': port
                })
            elif '_adb-tls-connect' in service_type:
                entry.update({
                    'connect_service': service_name,
                    'connect_ip': host,
                    'connect_port': port
                })
            elif service_type == '_adb._tcp':
                entry.update({
                    'connect_ip': host,
                    'connect_port': port
                })

        if unparsed:
            logging.warning("Unparsed adb mdns lines encountered: %d", len(unparsed))
        return devices

    def _discover_mdns_devices(self):
        result = self._run_adb('mdns', 'services', timeout=self.MDNS_DISCOVERY_TIMEOUT)
        return self._parse_mdns_services(result.stdout)

    def _build_connect_service_name(self, pairing_service: Optional[str]) -> Optional[str]:
        if not pairing_service or '_adb-tls-pairing' not in pairing_service:
            return None
        base_service = pairing_service.split('._adb-tls-pairing', 1)[0]
        if not base_service:
            return None
        connect_service = f"{base_service}._adb-tls-connect._tcp.local"
        if pairing_service.endswith('.'):
            connect_service += '.'
        return connect_service

    def _format_device_display(self, key, info):
        address = info.get('pairing_ip') or info.get('connect_ip') or 'Unknown IP'
        pairing_port = info.get('pairing_port')
        suffix = f":{pairing_port}" if pairing_port else ""
        return f"{key} ({address}{suffix})"

    def scan_for_devices(self):
        """Scan the local network for wireless debugging devices using adb mdns."""
        try:
            self.scan_btn.config(state='disabled')
        except Exception as e:
            logging.debug("Unable to disable scan button: %s", e)
        self.status_label.config(text="Scanning for devices...")

        def worker():
            devices = {}
            error = None
            try:
                devices = self._discover_mdns_devices()
            except Exception as e:
                error = str(e)

            def update_ui():
                self.discovered_devices = devices
                self.device_index_map = []
                self.devices_list.delete(0, tk.END)
                for key, info in devices.items():
                    self.device_index_map.append(key)
                    self.devices_list.insert(tk.END, self._format_device_display(key, info))
                if devices:
                    self.no_devices_label.config(
                        text="Select a device from the list, then enter the pairing code to connect."
                    )
                else:
                    self.no_devices_label.config(
                        text="No devices found yet. Open the wireless debugging pairing screen on your Peloton, then click Scan."
                    )
                    self._dismiss_port_prompt()
                    self._stop_port_scan()
                    self.selected_device_key = None
                if error:
                    messagebox.showerror("Scan Failed", f"Failed to scan for devices:\n{error}")
                try:
                    self.scan_btn.config(state='normal')
                except Exception as e:
                    logging.debug("Unable to re-enable scan button: %s", e)
                self.status_label.config(text="")
                self.check_fields()

            self.window.after(0, update_ui)

        threading.Thread(target=worker, daemon=True).start()

    def on_device_select(self, event=None):
        selection = self.devices_list.curselection()
        if not selection:
            self._manual_port_mode = False
            self._dismiss_port_prompt()
            self._stop_port_scan()
            self.selected_device_key = None
            self.check_fields()
            return
        index = selection[0]
        if index >= len(self.device_index_map):
            return
        self._manual_port_mode = False
        self._dismiss_port_prompt()
        self._stop_port_scan()
        key = self.device_index_map[index]
        self.selected_device_key = key
        device = self.discovered_devices.get(key, {})
        self.ip_var.set(device.get('pairing_ip', device.get('connect_ip', '')))
        self.port_var.set(device.get('pairing_port', ''))
        connect_port = device.get('connect_port', '')
        self.conport_var.set(connect_port)
        if connect_port:
            self.status_label.config(text=f"Selected {key}. Enter the pairing code to continue.")
        else:
            self.conport_var.set('')
            self._show_port_scan_prompt(key, self.ip_var.get().strip())
            self.status_label.config(text=f"Selected {key}. Choose how to provide the wireless debugging port.")
        self.check_fields()
        self.conport_entry.config(state='normal')
    
    def check_fields(self, *args):
        """Enable connect button when all fields are filled"""
        code = self.code_var.get().strip()
        manual_ready = self.ip_var.get().strip() and self.port_var.get().strip() and self.conport_var.get().strip()
        has_device = self.selected_device_key is not None
        if code and (manual_ready or has_device):
            self.connect_btn.config(state='normal')
        else:
            self.connect_btn.config(state='disabled')
    
    def pair_and_connect(self):
        """Pair and connect to the device via WiFi"""
        ip = self.ip_var.get().strip()
        port = self.port_var.get().strip()
        code = self.code_var.get().strip()
        conport = self.conport_var.get().strip()
        selected_device_key = self.selected_device_key
        selected_device = self.discovered_devices.get(selected_device_key) if selected_device_key else None
        selected_device_snapshot = dict(selected_device) if selected_device else None

        self._stop_port_scan()
        self._dismiss_port_prompt()

        if not code:
            messagebox.showerror("Error", "Please enter the pairing code.")
            return
        if not selected_device and (not ip or not port or not conport):
            messagebox.showerror(
                "Error",
                "Select a device from the scan list or enter the IP/ports manually."
            )
            return
        
        # Disable buttons during connection
        self.connect_btn.config(state='disabled')
        self.cancel_btn.config(state='disabled')
        self._pairing_in_progress = True
        
        def connect():
            try:
                run_adb = self._run_adb

                # Step 1: Pair with the device
                self.status_label.config(text="Pairing with device...")
                self.window.update()

                pair_args = ['pair']
                pairing_ip = None
                pairing_port = None
                if selected_device_snapshot:
                    pairing_ip = selected_device_snapshot.get('pairing_ip')
                    pairing_port = selected_device_snapshot.get('pairing_port')
                if pairing_ip and pairing_port:
                    pair_args.append(f"{pairing_ip}:{pairing_port}")
                elif selected_device_snapshot and selected_device_snapshot.get('pairing_service'):
                    pair_args.append(f"--mdns-service={selected_device_snapshot['pairing_service']}")
                else:
                    pair_args.append(f'{ip}:{port}')
                pair_args.append(code)

                pair_result = run_adb(*pair_args, timeout=self.PAIR_TIMEOUT_SECONDS)

                if pair_result.returncode != 0 or 'Failed' in pair_result.stdout or 'failed' in pair_result.stderr:
                    error_msg = "\n".join(filter(None, [pair_result.stdout, pair_result.stderr]))
                    self.status_label.config(text="Pairing failed!")
                    messagebox.showerror(
                        "Pairing Failed",
                        f"Failed to pair with device. Please check the information and try again.\n\nError: {error_msg}"
                    )
                    self.connect_btn.config(state='normal')
                    self.cancel_btn.config(state='normal')
                    return
                
                # Step 2: Connect to the device
                # After pairing, allow time for the device to expose the connect service.
                self.status_label.config(text="Waiting to complete connection (up to 2 minutes)...")
                self.window.update()

                connect_timeout_seconds = self.CONNECT_WAIT_SECONDS
                connect_deadline = time.time() + connect_timeout_seconds
                mdns_refresh_interval = self.MDNS_REFRESH_INTERVAL
                missing_info_wait = self.MISSING_INFO_WAIT
                retry_wait = self.CONNECT_RETRY_WAIT
                last_mdns_refresh = 0
                connected = False
                last_error = ""

                selected_device_info = dict(selected_device_snapshot) if selected_device_snapshot else None

                while time.time() < connect_deadline and not connected:
                    device_info = selected_device_info or {}
                    needs_refresh = selected_device_key and (
                        not device_info.get('connect_service') or not device_info.get('connect_ip')
                    )
                    if needs_refresh:
                        try:
                            if (time.time() - last_mdns_refresh) >= mdns_refresh_interval:
                                refreshed = self._discover_mdns_devices()
                                last_mdns_refresh = time.time()
                                self.discovered_devices.update(refreshed)
                                device_info = {**device_info, **refreshed.get(selected_device_key, {})}
                                selected_device_info = device_info
                        except Exception as e:
                            last_error = str(e)

                    connect_service = device_info.get('connect_service')
                    if not connect_service:
                        connect_service = self._build_connect_service_name(device_info.get('pairing_service'))
                    if connect_service and not any(
                        entry.get('connect_service') == connect_service
                        for entry in self.discovered_devices.values()
                    ):
                        connect_service = None

                    connect_ip = device_info.get('connect_ip') or device_info.get('pairing_ip') or ip
                    connect_port = device_info.get('connect_port') or conport

                    connect_args = ['connect']
                    if connect_ip and connect_port:
                        connect_args.append(f'{connect_ip}:{connect_port}')
                    else:
                        time.sleep(missing_info_wait)
                        continue

                    connect_result = run_adb(*connect_args, timeout=self.CONNECT_COMMAND_TIMEOUT)
                    if connect_result.returncode == 0 and (
                        'connected' in connect_result.stdout.lower() or 'already' in connect_result.stdout.lower()
                    ):
                        connected = True
                        break
                    last_error = "\n".join(filter(None, [connect_result.stdout, connect_result.stderr]))
                    time.sleep(retry_wait)

                if not connected:
                    self.status_label.config(text="Auto-connect failed!")
                    messagebox.showwarning(
                        "Connection Info Needed",
                        "Automatic connection failed. Please make sure wireless debugging is open on your Peloton and try again.\n\n"
                        f"{last_error}"
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
                if self.app:
                    self._pairing_in_progress = False
                    self.app.check_device_connection()
                    try:
                        self.app._close_wireless_dialog()
                    except Exception:
                        pass
                else:
                    self._pairing_in_progress = False
                    self._on_close()
                
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
            finally:
                self._pairing_in_progress = False
        
        # Run in a thread to avoid blocking the UI
        thread = threading.Thread(target=connect)
        thread.start()
    
    def show(self):
        try:
            self.scan_for_devices()
        except Exception as e:
            logging.debug("Auto-scan failed to start: %s", e)
        self.window.grab_set()  # Make window modal
        self.window.focus_set()

    def _on_close(self):
        self._dismiss_port_prompt()
        self._stop_port_scan()
        if self.app and getattr(self.app, 'wireless_dialog', None) is self:
            self.app.wireless_dialog = None
        try:
            self.window.destroy()
        except Exception:
            pass

    def _dismiss_port_prompt(self):
        prompt = self._port_prompt
        self._port_prompt = None
        if not prompt:
            return
        try:
            prompt.grab_release()
        except Exception:
            pass
        try:
            prompt.destroy()
        except Exception:
            pass
        try:
            self.window.grab_set()
        except Exception:
            pass

    def _dismiss_port_progress(self):
        dialog = self._port_progress_dialog
        bar = self._port_progress_bar
        self._port_progress_dialog = None
        self._port_progress_bar = None
        if bar:
            try:
                bar.stop()
            except Exception:
                pass
        if not dialog:
            return
        try:
            dialog.grab_release()
        except Exception:
            pass
        try:
            dialog.destroy()
        except Exception:
            pass
        try:
            self.window.grab_set()
        except Exception:
            pass

    def _show_port_scan_prompt(self, target_key: str, ip: str):
        if self._manual_port_mode or not ip:
            return
        self._dismiss_port_prompt()
        prompt = tk.Toplevel(self.window)
        prompt.title("Scan For Port")
        prompt.transient(self.window)
        prompt.grab_set()

        ttk.Label(
            prompt,
            text="Scan to fill remaining port?",
            padding=(20, 15)
        ).pack(fill='x')

        ttk.Label(
            prompt,
            text="We can scan ports 30000-50000 automatically or you can enter it manually.",
            wraplength=340,
            justify='center'
        ).pack(fill='x', padx=20)

        button_frame = ttk.Frame(prompt)
        button_frame.pack(fill='x', padx=20, pady=(10, 15))

        def start_scan():
            self._manual_port_mode = False
            self._dismiss_port_prompt()
            self._start_port_scan(target_key, ip)

        def manual_entry():
            self._dismiss_port_prompt()
            self._cancel_port_scan_and_enable_manual()

        ttk.Button(button_frame, text="Start Scan", command=start_scan).pack(side='left', expand=True, padx=5)
        ttk.Button(button_frame, text="Enter Manually", command=manual_entry).pack(side='right', expand=True, padx=5)

        prompt.protocol("WM_DELETE_WINDOW", manual_entry)
        self._port_prompt = prompt

    def _show_port_progress_dialog(self, total_ports: int):
        self._dismiss_port_progress()
        dialog = tk.Toplevel(self.window)
        dialog.title("Scanning Port")
        dialog.transient(self.window)
        dialog.grab_set()

        ttk.Label(
            dialog,
            text="Scanning ports 30000-50000...",
            padding=(20, 10)
        ).pack(fill='x')

        bar = ttk.Progressbar(dialog, mode='determinate', length=260)
        bar.pack(fill='x', padx=20, pady=(0, 10))
        try:
            bar['maximum'] = max(total_ports, 1)
        except Exception:
            bar.config(maximum=max(total_ports, 1))
        bar['value'] = 0

        ttk.Button(
            dialog,
            text="Enter manually",
            command=self._cancel_port_scan_and_enable_manual
        ).pack(pady=(0, 15))

        dialog.protocol("WM_DELETE_WINDOW", self._cancel_port_scan_and_enable_manual)
        self._port_progress_dialog = dialog
        self._port_progress_bar = bar

    def _cancel_port_scan_and_enable_manual(self):
        self._manual_port_mode = True
        self._dismiss_port_progress()
        self._stop_port_scan()
        self.status_label.config(text="Enter the wireless debugging port shown on your Peloton.")
        try:
            self.conport_entry.focus_set()
        except Exception:
            pass

    def _update_port_progress(self, scanned: int, total_ports: Optional[int] = None):
        bar = self._port_progress_bar
        if not bar:
            return
        try:
            if total_ports and total_ports > 0:
                bar.configure(maximum=max(total_ports, 1))
            maximum = float(bar.cget('maximum'))
            value = min(float(scanned), maximum)
            bar.configure(value=value)
        except Exception:
            try:
                bar.config(value=scanned)
            except Exception:
                pass

    def request_auto_close(self):
        if self._pairing_in_progress:
            return
        try:
            self.window.after(0, self._on_close)
        except Exception:
            self._on_close()

    def _probe_port(self, ip: str, port: int, stop_event: threading.Event, timeout: float = 0.05) -> bool:
        if stop_event.is_set():
            return False
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        try:
            result = sock.connect_ex((ip, port))
            return result == 0
        except OSError:
            return False
        finally:
            try:
                sock.close()
            except OSError:
                pass

    def _scan_open_port(
        self,
        ip: str,
        stop_event: threading.Event,
        ports_to_scan: List[int],
        progress_callback: Optional[Callable[[int], None]] = None
    ) -> Optional[int]:
        executor = ThreadPoolExecutor(max_workers=32)
        open_port = None
        scanned = 0
        try:
            futures = {}
            for port in ports_to_scan:
                if stop_event.is_set():
                    break
                futures[executor.submit(self._probe_port, ip, port, stop_event)] = port
            for future in as_completed(futures):
                if stop_event.is_set():
                    break
                port = futures.get(future)
                if port is None:
                    continue
                scanned += 1
                if progress_callback:
                    try:
                        progress_callback(scanned)
                    except Exception:
                        pass
                try:
                    if future.result():
                        open_port = port
                        stop_event.set()
                        break
                except Exception:
                    continue
        finally:
            executor.shutdown(wait=False, cancel_futures=True)
        return open_port

    def _start_port_scan(self, target_key: str, ip: str):
        if not ip or self._manual_port_mode:
            return
        self._stop_port_scan()
        stop_event = threading.Event()
        self._port_scan_stop = stop_event
        self._port_scan_target = target_key
        ignored_ports = set()
        pairing_port_value = self.port_var.get().strip()
        if pairing_port_value.isdigit():
            ignored_ports.add(int(pairing_port_value))
        self._current_scan_ignore_ports = ignored_ports
        ports_to_scan = [port for port in range(30000, 50001) if port not in ignored_ports]
        self._port_scan_total = len(ports_to_scan)
        if not ports_to_scan:
            self.status_label.config(text="Enter the wireless debugging port shown on your Peloton.")
            return

        self._show_port_progress_dialog(self._port_scan_total)
        self._update_port_progress(0, self._port_scan_total)
        self.status_label.config(text="Scanning for wireless debugging port...")

        def report_progress(scanned_count: int):
            self.window.after(0, lambda count=scanned_count: self._update_port_progress(count, self._port_scan_total))

        def worker():
            port = self._scan_open_port(ip, stop_event, ports_to_scan, report_progress)
            self.window.after(0, lambda: self._handle_port_scan_result(target_key, stop_event, port, ignored_ports))

        thread = threading.Thread(target=worker, daemon=True)
        self._port_scan_thread = thread
        thread.start()

    def _stop_port_scan(self):
        stop_event = self._port_scan_stop
        if stop_event:
            stop_event.set()
        thread = self._port_scan_thread
        if thread and thread.is_alive():
            thread.join(timeout=0.1)
        self._port_scan_stop = None
        self._port_scan_thread = None
        self._port_scan_target = None
        self._current_scan_ignore_ports = set()
        self._port_scan_total = 0
        self._dismiss_port_progress()

    def _handle_port_scan_result(
        self,
        target_key: str,
        stop_event: threading.Event,
        port: Optional[int],
        ignored_ports: Optional[Set[int]] = None
    ):
        if self._port_scan_stop is not stop_event:
            self._dismiss_port_progress()
            return
        self._port_scan_stop = None
        self._port_scan_thread = None
        self._port_scan_target = None
        if self._manual_port_mode:
            self._dismiss_port_progress()
            return
        self._dismiss_port_progress()
        if self.selected_device_key != target_key:
            self._port_scan_total = 0
            return
        if port and ignored_ports and port in ignored_ports:
            port = None
        if port:
            if not self.conport_var.get().strip():
                self.conport_var.set(str(port))
            self.status_label.config(text=f"Detected wireless debugging port {port}. Enter the pairing code to continue.")
        else:
            self.status_label.config(text="Unable to detect the wireless debugging port. Enter it manually from your Peloton screen.")
        self._port_scan_total = 0

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

class PelotonUninstaller:
    def __init__(self, parent, app):
        self.window = tk.Toplevel(parent)
        self.window.title("Uninstall Peloton Apps")
        self.window.geometry("600x600")
        self.app = app
        self.packages = []
        self.vars = {}

        self.setup_gui()
        self.refresh_packages()

    def setup_gui(self):
        # Warning Header
        warning_frame = tk.Frame(self.window, bg='#ffebee')
        warning_frame.pack(fill='x', padx=10, pady=10)
        
        warning_label = tk.Label(
            warning_frame,
            text="⚠️ WARNING: IRREVERSIBLE ACTION ⚠️\n\nUninstalling core Peloton system applications may render\nyour tablet completely UNUSABLE (brick it).\n\nProceed only if you absolutely know what you are doing.",
            fg='#c62828',
            bg='#ffebee',
            font=('Helvetica', 10, 'bold'),
            justify='center',
            padx=10,
            pady=10
        )
        warning_label.pack(fill='x')

        # List Frame
        list_frame = ttk.LabelFrame(self.window, text="Detected Peloton Packages")
        list_frame.pack(fill='both', expand=True, padx=10, pady=5)
        
        canvas = tk.Canvas(list_frame)
        scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=canvas.yview)
        self.scrollable_frame = ttk.Frame(canvas)

        self.scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )

        canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)

        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        # Binding mouse wheel for the canvas
        def _on_mousewheel(event):
            canvas.yview_scroll(int(-1*(event.delta/120)), "units")
        
        canvas.bind_all("<MouseWheel>", _on_mousewheel)
        
        # Buttons
        btn_frame = ttk.Frame(self.window)
        btn_frame.pack(fill='x', padx=10, pady=10)
        
        ttk.Button(btn_frame, text="Select All", command=self.select_all).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="Deselect All", command=self.deselect_all).pack(side='left', padx=5)
        
        self.uninstall_btn = ttk.Button(
            btn_frame, 
            text="🗑️ UNINSTALL SELECTED", 
            command=self.uninstall_selected
        )
        self.uninstall_btn.pack(side='right', padx=5)

    def select_all(self):
        for v in self.vars.values():
            v.set(True)

    def deselect_all(self):
        for v in self.vars.values():
            v.set(False)

    def refresh_packages(self):
        for widget in self.scrollable_frame.winfo_children():
            widget.destroy()
        self.vars = {}
        
        serial = self.app._require_single_device("scan packages")
        if not serial:
            self.window.destroy()
            return

        try:
            # List packages
            result = self.app.adb_run('-s', serial, 'shell', 'pm', 'list', 'packages')
            if result.returncode != 0:
                raise Exception(result.stderr or "Unknown error")
            
            output = result.stdout or ""
            packages = []
            for line in output.splitlines():
                if not line.strip(): continue
                # Line format: package:com.example.app
                pkg = line.replace('package:', '').strip()
                
                # Filter: contains "peloton" (case-insensitive) AND NOT contains "affernet" OR "sensor"
                pkg_lower = pkg.lower()
                if 'peloton' in pkg_lower and 'affernet' not in pkg_lower and 'sensor' not in pkg_lower:
                    packages.append(pkg)
            
            packages.sort()
            
            if not packages:
                ttk.Label(self.scrollable_frame, text="No Peloton packages found matching criteria.").pack(padx=10, pady=10)
                return

            for pkg in packages:
                var = tk.BooleanVar()
                self.vars[pkg] = var
                cb = ttk.Checkbutton(self.scrollable_frame, text=pkg, variable=var)
                cb.pack(anchor='w', padx=5, pady=2)
                
        except Exception as e:
            messagebox.showerror("Scan Error", f"Failed to list packages: {e}", parent=self.window)

    def uninstall_selected(self):
        selected = [pkg for pkg, var in self.vars.items() if var.get()]
        if not selected:
            messagebox.showwarning("No Selection", "Please select at least one package to uninstall.", parent=self.window)
            return

        if not messagebox.askyesno(
            "Confirm Uninstall", 
            f"Are you sure you want to uninstall {len(selected)} packages?\n\n"
             "This action is IRREVERSIBLE and could BRICK your device.\n\n"
             "Do you want to proceed?",
            icon='warning',
            parent=self.window
        ):
            return

        serial = self.app._require_single_device("uninstall packages")
        if not serial:
            return

        self.uninstall_btn.state(['disabled'])
        self.app.progress.start()
        
        threading.Thread(target=self._run_uninstall_thread, args=(serial, selected), daemon=True).start()

    def _run_uninstall_thread(self, serial, selected):
        success_count = 0
        fail_count = 0
        
        for pkg in selected:
            try:
                self.app.log_adb_message(f"Uninstalling {pkg}...", tag='command')
                
                # Method 1: Standard uninstall
                result = self.app.adb_run('-s', serial, 'uninstall', pkg)
                output = (result.stdout or "") + (result.stderr or "")
                
                if result.returncode == 0 and 'Success' in output:
                    success_count += 1
                    self.app.log_adb_message(f"Uninstalled {pkg}", tag='status')
                else:
                    # Method 2: System app uninstall (pm uninstall --user 0)
                    # This is required for pre-installed system apps which cannot be fully removed
                    self.app.log_adb_message(f"Standard install failed ({output.strip()}), trying user 0 override...", tag='info')
                    result = self.app.adb_run('-s', serial, 'shell', 'pm', 'uninstall', '--user', '0', pkg)
                    output = (result.stdout or "") + (result.stderr or "")

                    if result.returncode == 0 and 'Success' in output:
                        success_count += 1
                        self.app.log_adb_message(f"Uninstalled {pkg} (user 0)", tag='status')
                    else:
                        fail_count += 1
                        self.app.log_adb_message(f"Failed to uninstall {pkg}: {output.strip()}", tag='error')

            except Exception as e:
                fail_count += 1
                self.app.log_adb_message(f"Exception uninstalling {pkg}: {e}", tag='error')
        
        self.window.after(0, lambda: self._on_uninstall_complete(success_count, fail_count))

    def _on_uninstall_complete(self, success_count, fail_count):
        self.app.progress.stop()
        self.uninstall_btn.state(['!disabled'])
        self.refresh_packages()
        
        messagebox.showinfo(
            "Uninstall Complete", 
            f"Result:\n✅ {success_count} uninstalled\n❌ {fail_count} failed",
            parent=self.window
        )
        
    def show(self):
        self.window.deiconify()
        self.window.lift()
        self.window.focus_force()

def main():
    app = OpenPeloGUI()
    app.run()

if __name__ == "__main__":
    main()
