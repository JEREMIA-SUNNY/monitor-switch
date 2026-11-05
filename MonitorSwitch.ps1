<#
================================================================================
  Monitor Switch  -  flip one monitor between your PC and your laptop
  https://github.com/JEREMIA-SUNNY/monitor-switch

  Required Notice: Copyright (c) 2026 Jeremia Sunny (https://github.com/JEREMIA-SUNNY/monitor-switch)
  Required Notice: Monitor Switch was created by Jeremia Sunny. Copies, forks and modified versions must keep this credit and the link above.
  SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
  Free for personal / non-commercial use. Commercial use is NOT allowed
  without written permission. Full terms: LICENSE.md or
  https://polyformproject.org/licenses/noncommercial/1.0.0
================================================================================
  Put this SAME file on BOTH machines (PC and laptop) and run it on both.

    - Left-click the tray icon (bottom-right, near the clock)  -> switch screen
    - Or press  Ctrl + Alt + M                                  -> switch screen
    - Or say  "switch to laptop" / "switch to PC"               -> voice (turn on in the menu)
    - Right-click the tray icon for: switch to PC / switch to laptop,
      swap inputs, change hotkey, voice commands, monitor info,
      start with Windows, about, exit.

  It talks to the monitor through the video cable (DDC/CI) - the same thing
  the monitor's own Input button does. No extra hardware, nothing to install.

  FIRST TIME
    1. Make sure "DDC/CI" is ON in the monitor's on-screen menu
       (usually under System / Setup / Others - most monitors have it on).
    2. Double-click "Start Monitor Switch.cmd" (keep it next to this file).
    3. Right-click the tray icon -> "Start with Windows" so it's always there.
    4. If "Switch to PC" / "Switch to Laptop" go to the wrong machine,
       right-click the tray icon -> "Swap PC / Laptop inputs" (saved).

  HOW THE CLICK / HOTKEY DECIDES: the app detects whether it is running on
  the PC or the laptop and always switches to the OTHER machine. If it
  guesses wrong, set ThisMachine below to 'PC' or 'Laptop'.

  COMMAND LINE (for a desktop shortcut, macro key, Stream Deck...)
    MonitorSwitch.ps1 -Toggle     switch once and exit
    MonitorSwitch.ps1 -To 17      switch to input code 17 and exit
    MonitorSwitch.ps1 -Info       show monitors and their current input code
================================================================================
#>
param(
    [switch]$Toggle,
    [int]$To = -1,
    [switch]$Info,
    [switch]$Silent      # no "I'm running" popup (used when starting with Windows)
)

# ============================== SETTINGS ======================================
# Choices made from the tray menu ("Swap PC / Laptop inputs", "Change hotkey...")
# are saved in %APPDATA%\MonitorSwitch\settings.json and win over these defaults.
$PcInput     = 15            # input code that shows the PC      (15 = DisplayPort 1, 16 = DP 2)
$LaptopInput = 17            # input code that shows the laptop  (17 = HDMI 1, 18 = HDMI 2)
$ThisMachine = 'Auto'        # 'Auto', 'PC' or 'Laptop' - which computer this copy runs on
$PcName      = 'PC (DisplayPort)'
$LaptopName  = 'Laptop (HDMI)'
$HotkeyMods  = 'Ctrl+Alt'    # default hotkey
$HotkeyKey   = 'M'

# Voice commands - turn on with right-click > "Voice commands".
# Uses Windows' built-in offline speech recognizer. Nothing is recorded or sent anywhere.
$VoiceLaptop     = @('switch to laptop')                                      # say one of these -> laptop
$VoicePc         = @('switch to PC', 'switch to computer', 'switch to desktop')  # say one of these -> PC
$VoiceConfidence = 0.70      # 0.5 - 0.9. Higher = fewer false triggers, but you may need to speak clearer
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

trap {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Monitor Switch hit an error:`r`n`r`n$($_.Exception.Message)",
        'Monitor Switch', 'OK', 'Error')
    break
}

# ---------- Native part: DDC/CI monitor control + global hotkey ----------
if (-not ('MonSwitch.Ddc' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace MonSwitch
{
    public static class Ddc
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct PHYSICAL_MONITOR
        {
            public IntPtr hPhysicalMonitor;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string szPhysicalMonitorDescription;
        }

        delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, IntPtr lprcMonitor, IntPtr dwData);

        [DllImport("user32.dll")]
        static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

        [DllImport("dxva2.dll", SetLastError = true)]
        static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint count);

        [DllImport("dxva2.dll", SetLastError = true)]
        static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint count, [Out] PHYSICAL_MONITOR[] monitors);

        [DllImport("dxva2.dll", SetLastError = true)]
        static extern bool DestroyPhysicalMonitor(IntPtr hMonitor);

        [DllImport("dxva2.dll", SetLastError = true)]
        static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr hMonitor, byte vcpCode, IntPtr vcpType, out uint current, out uint maximum);

        [DllImport("dxva2.dll", SetLastError = true)]
        static extern bool SetVCPFeature(IntPtr hMonitor, byte vcpCode, uint value);

        const byte InputSource = 0x60;   // MCCS VCP code for "input source"

        static List<PHYSICAL_MONITOR> OpenAll()
        {
            List<IntPtr> handles = new List<IntPtr>();
            MonitorEnumProc proc = delegate(IntPtr h, IntPtr dc, IntPtr rc, IntPtr data) { handles.Add(h); return true; };
            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, proc, IntPtr.Zero);
            GC.KeepAlive(proc);

            List<PHYSICAL_MONITOR> result = new List<PHYSICAL_MONITOR>();
            foreach (IntPtr h in handles)
            {
                uint n;
                if (!GetNumberOfPhysicalMonitorsFromHMONITOR(h, out n) || n == 0) continue;
                PHYSICAL_MONITOR[] arr = new PHYSICAL_MONITOR[n];
                if (GetPhysicalMonitorsFromHMONITOR(h, n, arr)) result.AddRange(arr);
            }
            return result;
        }

        static void CloseAll(List<PHYSICAL_MONITOR> list)
        {
            foreach (PHYSICAL_MONITOR m in list) DestroyPhysicalMonitor(m.hPhysicalMonitor);
        }

        static bool TryRead(IntPtr h, out uint raw)
        {
            uint cur, max;
            for (int i = 0; i < 3; i++)
            {
                if (GetVCPFeatureAndVCPFeatureReply(h, InputSource, IntPtr.Zero, out cur, out max))
                {
                    raw = cur;
                    return true;
                }
                Thread.Sleep(60);
            }
            raw = 0;
            return false;
        }

        // Input code the monitor is showing right now, or -1 if no monitor answers.
        public static int GetInput()
        {
            List<PHYSICAL_MONITOR> mons = OpenAll();
            try
            {
                foreach (PHYSICAL_MONITOR m in mons)
                {
                    uint raw;
                    if (TryRead(m.hPhysicalMonitor, out raw)) return (int)(raw & 0xFF);
                }
                return -1;
            }
            finally { CloseAll(mons); }
        }

        // Tell every DDC/CI-capable monitor to switch input. Returns how many accepted.
        public static int SetInput(uint code)
        {
            List<PHYSICAL_MONITOR> mons = OpenAll();
            int ok = 0;
            try
            {
                foreach (PHYSICAL_MONITOR m in mons)
                {
                    for (int i = 0; i < 3; i++)
                    {
                        if (SetVCPFeature(m.hPhysicalMonitor, InputSource, code)) { ok++; break; }
                        Thread.Sleep(60);
                    }
                }
            }
            finally { CloseAll(mons); }
            return ok;
        }

        public static string Describe()
        {
            List<PHYSICAL_MONITOR> mons = OpenAll();
            StringBuilder sb = new StringBuilder();
            try
            {
                if (mons.Count == 0) sb.Append("No monitors found.\r\n");
                int i = 1;
                foreach (PHYSICAL_MONITOR m in mons)
                {
                    uint raw;
                    string state = TryRead(m.hPhysicalMonitor, out raw)
                        ? string.Format("current input code = {0}    (raw 0x{1:X})", raw & 0xFF, raw)
                        : "no reply (built-in laptop screen, or DDC/CI is OFF in the monitor menu)";
                    sb.Append(string.Format("Monitor {0} - {1}:\r\n    {2}\r\n", i, m.szPhysicalMonitorDescription, state));
                    i++;
                }
            }
            finally { CloseAll(mons); }
            return sb.ToString();
        }
    }

    public class HotkeyWindow : NativeWindow, IDisposable
    {
        [DllImport("user32.dll", SetLastError = true)]
        static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll")]
        static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        const int WM_HOTKEY = 0x0312;
        const uint MOD_NOREPEAT = 0x4000;

        public event EventHandler Pressed;
        public bool Registered { get; private set; }

        public HotkeyWindow()
        {
            CreateHandle(new CreateParams());
        }

        // (Re)register the hotkey. Returns false if another app already owns it.
        public bool Set(uint modifiers, uint key)
        {
            Clear();
            Registered = RegisterHotKey(Handle, 1, modifiers | MOD_NOREPEAT, key);
            return Registered;
        }

        public void Clear()
        {
            if (Registered) UnregisterHotKey(Handle, 1);
            Registered = false;
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY)
            {
                EventHandler h = Pressed;
                if (h != null) h(this, EventArgs.Empty);
            }
            base.WndProc(ref m);
        }

        public void Dispose()
        {
            Clear();
            DestroyHandle();
        }
    }
}
'@
}

# ---------- Helpers ----------
$script:Tray       = $null
$script:LastSwitch = [datetime]::MinValue

function Show-Message([string]$text, [string]$kind = 'Info') {
    if ($script:Tray) {
        $script:Tray.ShowBalloonTip(5000, 'Monitor Switch', $text, [System.Windows.Forms.ToolTipIcon]::$kind)
    } else {
        $icon = if ($kind -eq 'Info') { 'Information' } else { $kind }
        [void][System.Windows.Forms.MessageBox]::Show($text, 'Monitor Switch', 'OK', $icon)
    }
}

function Switch-Input([int]$code) {
    # ignore accidental double-clicks / double key presses
    if (((Get-Date) - $script:LastSwitch).TotalSeconds -lt 2) { return }
    $script:LastSwitch = Get-Date
    try {
        $accepted = [MonSwitch.Ddc]::SetInput([uint32]$code)
        if ($accepted -eq 0) {
            Show-Message "The monitor didn't accept the switch.`nCheck that DDC/CI is ON in the monitor's on-screen menu." 'Warning'
        }
    } catch {
        Show-Message "Error while switching: $($_.Exception.Message)" 'Error'
    }
}

function Get-ThisMachine {
    if ($ThisMachine -eq 'PC' -or $ThisMachine -eq 'Laptop') { return $ThisMachine }
    $portable = 8, 9, 10, 11, 14, 30, 31, 32               # laptop / notebook / tablet / convertible
    $desktop  = 3, 4, 5, 6, 7, 13, 15, 16, 24, 35, 36      # desktop / tower / all-in-one / mini PC
    try {
        $types = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes)
        foreach ($t in $types) { if ($portable -contains [int]$t) { return 'Laptop' } }
        foreach ($t in $types) { if ($desktop  -contains [int]$t) { return 'PC' } }
    } catch {}
    try { if (Get-CimInstance Win32_Battery -ErrorAction Stop) { return 'Laptop' } } catch {}
    return 'PC'
}

# You always press the button on the machine that's on screen,
# so "switch" simply means: go to the other machine.
function Invoke-Toggle {
    if ($script:Me -eq 'Laptop') { Switch-Input $PcInput } else { Switch-Input $LaptopInput }
}

function Show-Info {
    try { $now = [MonSwitch.Ddc]::Describe() } catch { $now = "Error reading monitors: $($_.Exception.Message)`r`n" }
    $other = if ($script:Me -eq 'Laptop') { $PcName } else { $LaptopName }
    $hkState = if (-not $script:Hotkey) { 'tray app not running in this window' }
               elseif ($script:Hotkey.Registered) { 'active' }
               else { 'OFF - another app is using it (right-click > Change hotkey...)' }
    $voiceState = if ($script:Voice) { "ON (speech: $($script:Voice.RecognizerName)) - say '$($VoiceLaptop[0])' or '$($VoicePc[0])'" }
                  else { 'off (right-click > Voice commands)' }
    $text = "This computer is: $($script:Me)    (ThisMachine = '$ThisMachine')`r`n" +
        "Click / hotkey switches to: $other`r`n" +
        "Hotkey: $(Get-HotkeyLabel) - $hkState`r`n" +
        "Voice: $voiceState`r`n`r`n" +
        "Input codes in use:`r`n" +
        "    PcInput     = $PcInput    ($PcName)`r`n" +
        "    LaptopInput = $LaptopInput    ($LaptopName)`r`n`r`n" +
        "What the monitor reports:`r`n" + $now + "`r`n" +
        "Note: some monitors report different numbers than the ones they`r`n" +
        "accept for switching. If 'Switch to PC' and 'Switch to Laptop' in the`r`n" +
        "menu go to the right machine, your settings are correct. If they're`r`n" +
        "the wrong way round, use 'Swap PC / Laptop inputs'.`r`n`r`n" +
        "Monitor Switch by $AuthorName - $ProjectUrl"
    [void][System.Windows.Forms.MessageBox]::Show($text, 'Monitor Switch - monitor info', 'OK', 'Information')
}

# ---------- Credit / About ----------
$AuthorName = 'Jeremia Sunny'
$ProjectUrl = 'https://github.com/JEREMIA-SUNNY/monitor-switch'

function Show-About {
    $text = "Monitor Switch`r`n" +
        "Made by $AuthorName`r`n" +
        "$ProjectUrl`r`n`r`n" +
        "Switch one monitor between your PC and laptop with a click or a hotkey.`r`n`r`n" +
        "Free for personal and non-commercial use under the`r`n" +
        "PolyForm Noncommercial License 1.0.0. Commercial use needs permission.`r`n" +
        "If you share or change it, keep this credit and the license.`r`n`r`n" +
        "Open the project page on GitHub?"
    $answer = [System.Windows.Forms.MessageBox]::Show($text, 'About Monitor Switch', 'YesNo', 'Information')
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) { Start-Process $ProjectUrl }
}

# ---------- Hotkey: register, save, change ----------
$script:Hotkey     = $null
$script:SwitchItem = $null
$SettingsFile = Join-Path $env:APPDATA 'MonitorSwitch\settings.json'

function Get-HotkeyLabel {
    if ($script:HotkeyMods) { return "$($script:HotkeyMods)+$($script:HotkeyKey)" }
    return [string]$script:HotkeyKey
}

function ConvertTo-ModFlags([string]$text) {
    $flags = 0
    foreach ($part in ($text -split '\+')) {
        switch ($part.Trim().ToLower()) {
            'alt'     { $flags = $flags -bor 1 }
            'ctrl'    { $flags = $flags -bor 2 }
            'control' { $flags = $flags -bor 2 }
            'shift'   { $flags = $flags -bor 4 }
            'win'     { $flags = $flags -bor 8 }
        }
    }
    return $flags
}

function Register-Hotkey {
    if (-not $script:Hotkey) { return $false }
    try { $vk = [uint32][int][System.Windows.Forms.Keys]$script:HotkeyKey }
    catch { $script:Hotkey.Clear(); return $false }
    return $script:Hotkey.Set([uint32](ConvertTo-ModFlags $script:HotkeyMods), $vk)
}

function Read-Settings {
    try {
        if (Test-Path -LiteralPath $SettingsFile) {
            $s = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
            if ($s.HotkeyKey) {
                $script:HotkeyMods = [string]$s.HotkeyMods
                $script:HotkeyKey  = [string]$s.HotkeyKey
            }
            if ($null -ne $s.PcInput -and $null -ne $s.LaptopInput) {
                $script:PcInput     = [int]$s.PcInput
                $script:LaptopInput = [int]$s.LaptopInput
            }
            if ($null -ne $s.VoiceEnabled) {
                $script:VoiceOn = [bool]$s.VoiceEnabled
            }
        }
    } catch {}
}

function Save-Settings {
    try {
        $dir = Split-Path -Parent $SettingsFile
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        [pscustomobject]@{
            HotkeyMods  = $script:HotkeyMods
            HotkeyKey   = $script:HotkeyKey
            PcInput      = $script:PcInput
            LaptopInput  = $script:LaptopInput
            VoiceEnabled = [bool]$script:VoiceOn
        } | ConvertTo-Json | Set-Content -LiteralPath $SettingsFile -Encoding UTF8
    } catch {
        Show-Message "Couldn't save settings: $($_.Exception.Message)" 'Warning'
    }
}

function Invoke-SwapInputs {
    $script:PcInput, $script:LaptopInput = $script:LaptopInput, $script:PcInput
    Save-Settings
    Show-Message "Swapped and saved. PC = input $($script:PcInput), Laptop = input $($script:LaptopInput).`nDo the same on the other computer."
}

# ---------- Voice commands (offline Windows speech recognition) ----------
# Only compiled and started when you turn voice on, so the rest of the app
# keeps working even if speech isn't available on this PC.
$script:Voice     = $null     # the running listener
$script:VoiceOn   = $false    # saved choice from the menu
$script:VoiceItem = $null

function Initialize-VoiceType {
    if ('MonSwitch.Voice' -as [type]) { return }
    Add-Type -AssemblyName System.Speech
    Add-Type -ReferencedAssemblies System.Speech, System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Globalization;
using System.Speech.Recognition;
using System.Windows.Forms;

namespace MonSwitch
{
    public class VoiceEventArgs : EventArgs
    {
        private readonly string _command;
        private readonly string _text;
        private readonly float _confidence;

        public VoiceEventArgs(string command, string text, float confidence)
        {
            _command = command;
            _text = text;
            _confidence = confidence;
        }

        public string Command { get { return _command; } }
        public string Text { get { return _text; } }
        public float Confidence { get { return _confidence; } }
    }

    public class Voice : IDisposable
    {
        private SpeechRecognitionEngine _engine;
        private Control _ui;
        private readonly float _minConfidence;
        private volatile bool _disposed;

        // Both events are raised on the UI thread (the thread that created this object).
        public event EventHandler<VoiceEventArgs> Command;
        public event EventHandler<VoiceEventArgs> Stopped;

        public string RecognizerName { get; private set; }

        public static int RecognizerCount()
        {
            return SpeechRecognitionEngine.InstalledRecognizers().Count;
        }

        // The phrases are English, so prefer an English recognizer.
        private static RecognizerInfo Pick()
        {
            var all = SpeechRecognitionEngine.InstalledRecognizers();
            if (all.Count == 0) return null;
            CultureInfo ui = CultureInfo.CurrentUICulture;
            if (ui.TwoLetterISOLanguageName == "en")
            {
                foreach (RecognizerInfo r in all)
                    if (string.Equals(r.Culture.Name, ui.Name, StringComparison.OrdinalIgnoreCase)) return r;
            }
            foreach (RecognizerInfo r in all)
                if (string.Equals(r.Culture.Name, "en-US", StringComparison.OrdinalIgnoreCase)) return r;
            foreach (RecognizerInfo r in all)
                if (r.Culture.TwoLetterISOLanguageName == "en") return r;
            return all[0];
        }

        public Voice(string[] phrases, string[] commands, float minConfidence)
        {
            if (phrases == null || commands == null || phrases.Length == 0 || phrases.Length != commands.Length)
                throw new ArgumentException("The voice phrases at the top of MonitorSwitch.ps1 are not set up correctly.");
            _minConfidence = minConfidence;

            try
            {
                // A hidden control on the UI thread, used to hand results back to that thread.
                _ui = new Control();
                if (_ui.Handle == IntPtr.Zero)
                    throw new InvalidOperationException("Could not create a window for voice commands.");

                RecognizerInfo info = Pick();
                if (info == null)
                    throw new InvalidOperationException("No Windows speech recognizer is installed on this computer.");
                RecognizerName = info.Culture.Name;

                _engine = new SpeechRecognitionEngine(info);

                Choices choices = new Choices();
                for (int i = 0; i < phrases.Length; i++)
                    choices.Add(new SemanticResultValue(phrases[i], commands[i]).ToGrammarBuilder());

                GrammarBuilder builder = new GrammarBuilder();
                builder.Culture = info.Culture;
                builder.Append(new SemanticResultKey("cmd", choices.ToGrammarBuilder()).ToGrammarBuilder());
                _engine.LoadGrammar(new Grammar(builder));

                try
                {
                    _engine.SetInputToDefaultAudioDevice();
                }
                catch (Exception ex)
                {
                    throw new InvalidOperationException("No microphone found. Connect or turn on a microphone, then try again.", ex);
                }

                _engine.SpeechRecognized += OnRecognized;
                _engine.RecognizeCompleted += OnCompleted;
                _engine.RecognizeAsync(RecognizeMode.Multiple);
            }
            catch
            {
                Dispose();
                throw;
            }
        }

        private void OnRecognized(object sender, SpeechRecognizedEventArgs e)
        {
            RecognitionResult r = e.Result;
            if (r == null || r.Confidence < _minConfidence) return;
            if (r.Semantics == null || !r.Semantics.ContainsKey("cmd")) return;
            object value = r.Semantics["cmd"].Value;
            if (value == null) return;
            Post(Command, new VoiceEventArgs(value.ToString(), r.Text, r.Confidence));
        }

        private void OnCompleted(object sender, RecognizeCompletedEventArgs e)
        {
            if (_disposed || e.Cancelled) return;
            string why = e.Error != null ? e.Error.Message : "the microphone stopped sending sound.";
            Post(Stopped, new VoiceEventArgs("stopped", why, 0f));
        }

        private void Post(EventHandler<VoiceEventArgs> handler, VoiceEventArgs args)
        {
            Control ui = _ui;
            if (handler == null || ui == null || _disposed || ui.IsDisposed || !ui.IsHandleCreated) return;
            try
            {
                ui.BeginInvoke(new MethodInvoker(delegate
                {
                    if (!_disposed) handler(this, args);
                }));
            }
            catch (InvalidOperationException)
            {
                // window already gone - app is closing
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;

            SpeechRecognitionEngine engine = _engine;
            _engine = null;
            if (engine != null)
            {
                engine.SpeechRecognized -= OnRecognized;
                engine.RecognizeCompleted -= OnCompleted;
                try { engine.RecognizeAsyncCancel(); } catch (Exception) { }
                try { engine.Dispose(); } catch (Exception) { }
            }

            Control ui = _ui;
            _ui = null;
            if (ui != null) ui.Dispose();
        }
    }
}
'@
}

function Get-InnerMessage($err) {
    $ex = $err.Exception
    while ($ex.InnerException) { $ex = $ex.InnerException }
    return $ex.Message
}

function Invoke-VoiceCommand([string]$command) {
    switch ($command) {
        'laptop' { Switch-Input $script:LaptopInput }
        'pc'     { Switch-Input $script:PcInput }
    }
}

function Start-Voice {
    if ($script:Voice) { return $true }
    try {
        Initialize-VoiceType
        $phrases  = New-Object System.Collections.Generic.List[string]
        $commands = New-Object System.Collections.Generic.List[string]
        foreach ($p in @($VoiceLaptop)) { if ("$p".Trim()) { $phrases.Add("$p".Trim()); $commands.Add('laptop') } }
        foreach ($p in @($VoicePc))     { if ("$p".Trim()) { $phrases.Add("$p".Trim()); $commands.Add('pc') } }

        $v = [MonSwitch.Voice]::new($phrases.ToArray(), $commands.ToArray(), [float]$VoiceConfidence)
        $v.add_Command({ param($s, $e) Invoke-VoiceCommand $e.Command })
        $v.add_Stopped({
            param($s, $e)
            Stop-Voice
            Update-VoiceUi
            Show-Message "Voice commands stopped: $($e.Text)`nClick 'Voice commands' in the menu to start again." 'Warning'
        })
        $script:Voice = $v
        return $true
    } catch {
        $script:Voice = $null
        $why = Get-InnerMessage $_
        Show-Message ("Voice commands couldn't start: $why`n" +
            "Check that a microphone is connected and that Settings > Privacy & security > Microphone > " +
            "'Let desktop apps access your microphone' is ON.") 'Warning'
        return $false
    }
}

function Stop-Voice {
    $v = $script:Voice
    $script:Voice = $null
    if ($v) { try { $v.Dispose() } catch {} }
}

function Update-VoiceUi {
    if ($script:VoiceItem) { $script:VoiceItem.Checked = [bool]$script:Voice }
}

function Set-VoiceEnabled([bool]$on) {
    if ($on) {
        if (Start-Voice) {
            $script:VoiceOn = $true
            Save-Settings
            Show-Message "Voice commands ON. Say:`n""$(@($VoiceLaptop)[0])""  or  ""$(@($VoicePc)[0])"""
        }
    } else {
        Stop-Voice
        $script:VoiceOn = $false
        Save-Settings
    }
    Update-VoiceUi
}

function Update-HotkeyUi {
    $label  = Get-HotkeyLabel
    $active = [bool]($script:Hotkey -and $script:Hotkey.Registered)
    if ($script:SwitchItem) {
        $script:SwitchItem.ShortcutKeyDisplayString = $(if ($active) { $label } else { "$label (OFF)" })
    }
    if ($script:Tray) {
        $tip = if ($active) { "Monitor Switch ($($script:Me)) - click or $label" }
               else         { "Monitor Switch ($($script:Me)) - click to switch" }
        if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
        $script:Tray.Text = $tip
    }
}

function Show-HotkeyDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Monitor Switch - change hotkey'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.Font = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 10
    $form.ClientSize = New-Object System.Drawing.Size -ArgumentList 380, 160
    $form.KeyPreview = $true

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Press the new key combination.`nUse Ctrl, Alt and/or Shift with a key - e.g. Ctrl+Alt+S or Ctrl+Shift+F9."
    $lbl.SetBounds(14, 12, 352, 44)

    $box = New-Object System.Windows.Forms.TextBox
    $box.ReadOnly = $true
    $box.TabStop = $false
    $box.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
    $box.SetBounds(14, 64, 352, 28)
    $box.Text = Get-HotkeyLabel

    $save = New-Object System.Windows.Forms.Button
    $save.Text = 'Save'
    $save.SetBounds(198, 112, 80, 32)
    $save.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.SetBounds(286, 112, 80, 32)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.Controls.AddRange(@($lbl, $box, $save, $cancel))
    $form.CancelButton = $cancel
    $form.add_Shown({ $form.Activate() })     # make sure key presses land in this dialog

    $state = @{ Mods = ''; Key = '' }
    $form.add_KeyDown({
        param($s, $e)
        $e.SuppressKeyPress = $true
        $e.Handled = $true
        $name = $e.KeyCode.ToString()
        $modOnly = 'ControlKey','ShiftKey','Menu','LControlKey','RControlKey','LShiftKey','RShiftKey','LMenu','RMenu','LWin','RWin'
        if ($modOnly -contains $name) { return }
        $parts = @()
        if ($e.Control) { $parts += 'Ctrl' }
        if ($e.Alt)     { $parts += 'Alt' }
        if ($e.Shift)   { $parts += 'Shift' }
        if ($parts.Count -eq 0) {
            $state.Key = ''
            $box.Text = 'Hold Ctrl, Alt or Shift too'
            return
        }
        $state.Mods = $parts -join '+'
        $state.Key  = $name
        $box.Text   = "$($state.Mods)+$name"
    })

    # Release the current hotkey while the dialog is open, so pressing it here is
    # captured as the new choice instead of switching the monitor.
    $oldMods = $script:HotkeyMods
    $oldKey  = $script:HotkeyKey
    if ($script:Hotkey) { $script:Hotkey.Clear() }

    $result = $form.ShowDialog()
    $form.Dispose()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and $state.Key) {
        $script:HotkeyMods = $state.Mods
        $script:HotkeyKey  = $state.Key
        if (Register-Hotkey) {
            Save-Settings
            Update-HotkeyUi
            Show-Message "Hotkey changed to $(Get-HotkeyLabel)."
            return
        }
        $taken = Get-HotkeyLabel
        $script:HotkeyMods = $oldMods
        $script:HotkeyKey  = $oldKey
        [void](Register-Hotkey)
        Update-HotkeyUi
        [void][System.Windows.Forms.MessageBox]::Show(
            "$taken is already used by another app.`nPlease try a different combination.",
            'Monitor Switch', 'OK', 'Warning')
        return
    }

    # cancelled - put the old hotkey back
    [void](Register-Hotkey)
    Update-HotkeyUi
}

# ---------- Start with Windows (per-user, no admin needed) ----------
$RunKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName = 'MonitorSwitch'
$RunCmd  = '"{0}\System32\conhost.exe" --headless "{0}\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "{1}" -Silent' -f $env:SystemRoot, $PSCommandPath

function Test-Autostart {
    return [bool](Get-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue)
}
function Set-Autostart([bool]$on) {
    if ($on) { [void](New-ItemProperty -Path $RunKey -Name $RunName -Value $RunCmd -PropertyType String -Force) }
    else     { Remove-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue }
}

$script:Me = Get-ThisMachine
Read-Settings

# ---------- One-shot command-line modes ----------
if ($Info)     { Show-Info;           return }
if ($To -ge 0) { Switch-Input $To;    return }
if ($Toggle)   { Invoke-Toggle;       return }

# ---------- Tray app ----------
$created = $false
$mutex = [System.Threading.Mutex]::new($true, 'Local\MonitorSwitchTray', [ref]$created)
if (-not $created) {
    Show-Message 'Monitor Switch is already running - look for its icon near the clock.'
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()

function New-TrayIcon {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $c     = [System.Drawing.Color]::FromArgb(255, 56, 132, 255)
    $pen   = New-Object System.Drawing.Pen -ArgumentList $c, 2.5
    $brush = New-Object System.Drawing.SolidBrush -ArgumentList $c
    $g.DrawRectangle($pen, 2, 3, 27, 19)        # screen
    $g.FillRectangle($brush, 13, 23, 6, 3)      # stand neck
    $g.FillRectangle($brush, 8, 26, 16, 3)      # stand base
    $arrow = New-Object System.Drawing.Pen -ArgumentList $c, 2
    $arrow.CustomEndCap = New-Object System.Drawing.Drawing2D.AdjustableArrowCap -ArgumentList 3, 3
    $g.DrawLine($arrow, 8, 10, 23, 10)          # ->
    $g.DrawLine($arrow, 23, 16, 8, 16)          # <-
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = New-TrayIcon
$tray.Text = 'Monitor Switch'
$script:Tray = $tray

$menu = New-Object System.Windows.Forms.ContextMenuStrip
function Add-Item([string]$text, [scriptblock]$onClick, [string]$keys = '') {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem -ArgumentList $text
    if ($keys) { $item.ShortcutKeyDisplayString = $keys }
    $item.add_Click($onClick)
    [void]$menu.Items.Add($item)
    return $item
}
function Add-Separator { [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) }

$creditItem = Add-Item "Monitor Switch - by $AuthorName" { Show-About }
$creditItem.ForeColor = [System.Drawing.SystemColors]::GrayText
Add-Separator
$script:SwitchItem = Add-Item 'Switch screen now' { Invoke-Toggle }
$script:SwitchItem.Font = New-Object System.Drawing.Font -ArgumentList $script:SwitchItem.Font, ([System.Drawing.FontStyle]::Bold)
Add-Separator
[void](Add-Item "Switch to $PcName"     { Switch-Input $PcInput })
[void](Add-Item "Switch to $LaptopName" { Switch-Input $LaptopInput })
Add-Separator
[void](Add-Item 'Swap PC / Laptop inputs' { Invoke-SwapInputs })
[void](Add-Item 'Change hotkey...' { Show-HotkeyDialog })
$script:VoiceItem = Add-Item 'Voice commands' { Set-VoiceEnabled (-not $script:VoiceItem.Checked) }
[void](Add-Item 'Monitor info / input codes...' { Show-Info })
$autoItem = Add-Item 'Start with Windows' { param($s) $s.Checked = -not $s.Checked; Set-Autostart $s.Checked }
$autoItem.Checked = Test-Autostart
Add-Separator
[void](Add-Item 'About Monitor Switch...' { Show-About })
[void](Add-Item 'Exit' { [System.Windows.Forms.Application]::Exit() })
$tray.ContextMenuStrip = $menu

$tray.add_MouseClick({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Invoke-Toggle }
})

# Global hotkey
$script:Hotkey = New-Object MonSwitch.HotkeyWindow
$script:Hotkey.add_Pressed({ Invoke-Toggle })
[void](Register-Hotkey)
Update-HotkeyUi

$tray.Visible = $true
if (-not $script:Hotkey.Registered) {
    Show-Message "$(Get-HotkeyLabel) is already used by another app, so the hotkey is OFF. Right-click this icon > Change hotkey... to pick another. Clicking the icon still works." 'Warning'
} elseif (-not $Silent) {
    Show-Message "Running in the tray. Click the icon or press $(Get-HotkeyLabel) to switch screens."
}

# Turn voice back on if it was on last time (if it fails now, it tries again next start)
if ($script:VoiceOn) { [void](Start-Voice) }
Update-VoiceUi

[System.Windows.Forms.Application]::Run()

# cleanup on Exit
Stop-Voice
$script:Hotkey.Dispose()
$tray.Visible = $false
$tray.Dispose()
$mutex.ReleaseMutex()
$mutex.Dispose()
