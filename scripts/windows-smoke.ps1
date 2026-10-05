param(
    [string]$Executable = (Join-Path $PSScriptRoot '..\apps\client\build\windows\x64\runner\Release\reelnest.exe'),
    [int]$ObservationSeconds = 12
)

$ErrorActionPreference = 'Stop'
if ($ObservationSeconds -lt 1 -or $ObservationSeconds -gt 60) {
    throw 'ObservationSeconds must be between 1 and 60.'
}
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$logRoot = Join-Path $PSScriptRoot '..\apps\client\build\smoke'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

# Start hidden. Process.MainWindowHandle ignores hidden windows, so query only
# windows belonging to this child process and probe their message loop instead.
if (-not ('ReelNestSmokeWindow' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class ReelNestSmokeWindow {
    public delegate bool EnumCallback(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumCallback callback, IntPtr parameter);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);
    public static IntPtr Find(uint process) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((window, parameter) => {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            if (owner != process) return true;
            var title = new StringBuilder(256);
            GetWindowText(window, title, title.Capacity);
            if (title.ToString() == "ReelNest") { found = window; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
'@
}

$app = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path -Parent $Executable) `
    -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $logRoot 'release.stdout.log') `
    -RedirectStandardError (Join-Path $logRoot 'release.stderr.log')
try {
    # Retain the native handle before exit. Windows PowerShell can otherwise
    # return a null Process.ExitCode for a Start-Process child that has closed.
    $processHandle = $app.Handle
    $startupDeadline = (Get-Date).AddSeconds(15)
    $window = [IntPtr]::Zero
    while ((Get-Date) -lt $startupDeadline) {
        $app.Refresh()
        if ($app.HasExited) { throw "Release app exited during startup: $($app.ExitCode)" }
        $window = [ReelNestSmokeWindow]::Find([uint32]$app.Id)
        if ($window -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 250
    }
    if ($window -eq [IntPtr]::Zero) { throw 'No ReelNest window was created.' }
    $deadline = (Get-Date).AddSeconds($ObservationSeconds)
    while ((Get-Date) -lt $deadline) {
        $app.Refresh()
        if ($app.HasExited) { throw "Release app exited unexpectedly: $($app.ExitCode)" }
        $response = [UIntPtr]::Zero
        $responsive = [ReelNestSmokeWindow]::SendMessageTimeout($window, 0,
            [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$response)
        if ($responsive -eq [IntPtr]::Zero) { throw 'ReelNest window is not responding.' }
        Start-Sleep -Milliseconds 500
    }
    if (-not [ReelNestSmokeWindow]::PostMessage($window, 0x0010, [UIntPtr]::Zero, [IntPtr]::Zero)) {
        throw 'Could not request a normal window close.'
    }
    if (-not $app.WaitForExit(8000)) { throw 'Release app did not close normally.' }
    $exitCode = [uint32]0
    if (-not [ReelNestSmokeWindow]::GetExitCodeProcess($processHandle, [ref]$exitCode)) {
        throw 'Could not read the release app exit code.'
    }
    if ($exitCode -ne 0) { throw "Release app exited with code $exitCode" }
    [ordered]@{
        Executable=$Executable
        CheckedAt=(Get-Date).ToString('o')
        HiddenWindowResponding=$true
        ObservationSeconds=$ObservationSeconds
        ClosedNormally=$true
        ExitCode=$exitCode
    } | ConvertTo-Json | Tee-Object -FilePath (Join-Path $logRoot 'release-startup.json')
} finally {
    $app.Refresh()
    if (-not $app.HasExited) { Stop-Process -Id $app.Id }
    $app.Dispose()
}
