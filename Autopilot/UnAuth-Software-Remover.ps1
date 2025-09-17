

param(
    [switch]$DetectOnly = $false,
    [switch]$LogOnly = $false,
    [string]$LogPath = "$env:ProgramData\UnauthorizedSoftwareRemoval\removal.log"
)


$UnauthorizedSoftware = @(
    @{
        Name = "VLC Media Player"
        DisplayNamePattern = "*VLC*"
        ProcessName = "vlc"
        ServiceName = $null
        RegistryPath = "HKLM:\SOFTWARE\VideoLAN"
        AdditionalPaths = @("C:\Program Files\VideoLAN", "C:\Program Files (x86)\VideoLAN")
        UserPaths = @("$env:APPDATA\vlc", "$env:LOCALAPPDATA\VLC")
    },
    @{
        Name = "WinRAR"
        DisplayNamePattern = "*WinRAR*"
        ProcessName = "WinRAR"
        ServiceName = $null
        RegistryPath = "HKLM:\SOFTWARE\WinRAR"
        AdditionalPaths = @("C:\Program Files\WinRAR", "C:\Program Files (x86)\WinRAR")
        UserPaths = @("$env:APPDATA\WinRAR")
    },
    @{
        Name = "7-Zip"
        DisplayNamePattern = "*7-Zip*"
        ProcessName = @("7zFM", "7zG")
        ServiceName = $null
        RegistryPath = "HKLM:\SOFTWARE\7-Zip"
        AdditionalPaths = @("C:\Program Files\7-Zip", "C:\Program Files (x86)\7-Zip")
        UserPaths = @("$env:APPDATA\7-Zip")
    },
    @{
        Name = "LibreOffice"
        DisplayNamePattern = "*LibreOffice*"
        ProcessName = @("soffice", "soffice.bin", "scalc", "swriter", "simpress", "sdraw", "sbase", "smath")
        ServiceName = $null
        RegistryPath = "HKLM:\SOFTWARE\LibreOffice"
        AdditionalPaths = @("C:\Program Files\LibreOffice", "C:\Program Files (x86)\LibreOffice")
        UserPaths = @("$env:APPDATA\LibreOffice", "$env:LOCALAPPDATA\LibreOffice")
    },
    @{
        Name = "Skype"
        DisplayNamePattern = "*Skype*"
        ProcessName = @("Skype", "SkypeApp")
        ServiceName = $null
        RegistryPath = "HKLM:\SOFTWARE\Skype"
        AdditionalPaths = @(
            "C:\Program Files\Microsoft\Skype for Desktop", 
            "C:\Program Files (x86)\Microsoft\Skype for Desktop",
            "C:\Program Files\Skype",
            "C:\Program Files (x86)\Skype"
        )
        UserPaths = @("$env:APPDATA\Skype", "$env:LOCALAPPDATA\Skype", "$env:LOCALAPPDATA\Microsoft\Skype for Desktop")
    },
    @{
        Name = "Opera Browser"
        DisplayNamePattern = "*Opera*"
        ProcessName = @("opera", "opera_autoupdate")
        ServiceName = $null
        RegistryPath = "HKLM:\SOFTWARE\Opera Software"
        AdditionalPaths = @("C:\Program Files\Opera", "C:\Program Files (x86)\Opera")
        UserPaths = @("$env:APPDATA\Opera Software", "$env:LOCALAPPDATA\Opera Software")
    }
)


function Initialize-Logging {
    param([string]$LogPath)
    
    $logDir = Split-Path $LogPath -Parent
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    "=== Unauthorized Software Removal Script Started: $(Get-Date) ===" | Out-File -FilePath $LogPath -Append
}

function Write-LogMessage {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    Write-Host $logMessage
    $logMessage | Out-File -FilePath $LogPath -Append
}
function Stop-UninstallerDialogs {
    param([string]$ProcessName, [int]$TimeoutSeconds = 30)
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {

        $dialogProcesses = @(
            "unins*", 
            "*uninstall*", 
            "setup*", 
            "install*",
            "msiexec*",
            "InstallShield*",
            "InnoSetup*"
        )
        
        foreach ($pattern in $dialogProcesses) {
            try {
                Get-Process -Name $pattern -ErrorAction SilentlyContinue | 
                Where-Object { $_.MainWindowTitle -ne "" } | 
                ForEach-Object { 
                    Write-LogMessage "Killing uninstaller dialog: $($_.ProcessName) (PID: $($_.Id))"
                    Stop-Process -Id $_.Id -Force 
                }
            }
            catch { }
        }
        
  
        Add-Type -TypeDefinition @"
            using System;
            using System.Runtime.InteropServices;
            public class Win32 {
                [DllImport("user32.dll")]
                public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
                
                [DllImport("user32.dll")]
                public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
                
                public const uint WM_CLOSE = 0x0010;
                public const uint WM_COMMAND = 0x0111;
            }
"@ -ErrorAction SilentlyContinue
        
        
        $commonTitles = @(
            "*Uninstall*",
            "*Setup*", 
            "*Install*",
            "*Remove*",
            "VLC media player*",
            "Maintenance*"
        )
        
        foreach ($title in $commonTitles) {
            try {
                $hwnd = [Win32]::FindWindow($null, $title)
                if ($hwnd -ne [IntPtr]::Zero) {
                    Write-LogMessage "Closing dialog window: $title"
                    [Win32]::PostMessage($hwnd, [Win32]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
                }
            }
            catch { }
        }
        
        Start-Sleep -Milliseconds 500
    }
    
    $stopwatch.Stop()
}

function Get-InstalledPrograms {
    $programs = @()
    
 
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($path in $registryPaths) {
        try {
            $items = Get-ItemProperty $path -ErrorAction SilentlyContinue | 
                     Where-Object { $_.DisplayName -and !$_.SystemComponent }
            $programs += $items
        }
        catch {
            Write-LogMessage "Error accessing registry path $path : $($_.Exception.Message)" "WARNING"
        }
    }
    

    try {
        $appxPackages = Get-AppxPackage -AllUsers | Where-Object { $_.Name -notlike "Microsoft.*" -and $_.Name -notlike "Windows.*" }
        $programs += $appxPackages
    }
    catch {
        Write-LogMessage "Error getting AppX packages: $($_.Exception.Message)" "WARNING"
    }
    
    return $programs
}


function Test-UnauthorizedSoftware {
    param(
        [object]$Program,
        [object]$UnauthorizedPattern
    )
    
    $displayName = if ($Program.DisplayName) { $Program.DisplayName } else { $Program.Name }
    
    if ($displayName -like $UnauthorizedPattern.DisplayNamePattern) {
        return $true
    }
    
    return $false
}


function Stop-SoftwareProcesses {
    param([object]$SoftwarePattern)
    
    $stopped = $false
    
  
    if ($SoftwarePattern.ProcessName) {
        $processNames = if ($SoftwarePattern.ProcessName -is [array]) { $SoftwarePattern.ProcessName } else { @($SoftwarePattern.ProcessName) }
        
        foreach ($processName in $processNames) {
            try {
                $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
                foreach ($process in $processes) {
                    Write-LogMessage "Stopping process: $($process.ProcessName) (PID: $($process.Id))"
                    Stop-Process -Id $process.Id -Force
                    $stopped = $true
                }
            }
            catch {
                Write-LogMessage "Error stopping process $processName for $($SoftwarePattern.Name): $($_.Exception.Message)" "ERROR"
            }
        }
    }
    
    
    if ($SoftwarePattern.ServiceName) {
        try {
            $service = Get-Service -Name $SoftwarePattern.ServiceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq 'Running') {
                Write-LogMessage "Stopping service: $($service.Name)"
                Stop-Service -Name $service.Name -Force
                Set-Service -Name $service.Name -StartupType Disabled
                $stopped = $true
            }
        }
        catch {
            Write-LogMessage "Error stopping service for $($SoftwarePattern.Name): $($_.Exception.Message)" "ERROR"
        }
    }
    
    return $stopped
}


function Remove-UnauthorizedSoftware {
    param(
        [object]$Program,
        [object]$SoftwarePattern
    )
    
    $removed = $false
    $displayName = if ($Program.DisplayName) { $Program.DisplayName } else { $Program.Name }
    
    Write-LogMessage "Attempting to remove: $displayName"
    
 
    Stop-SoftwareProcesses -SoftwarePattern $SoftwarePattern
    
    try {
       
        if ($Program.UninstallString) {
            $uninstallString = $Program.UninstallString
            
            if ($uninstallString -like "msiexec*") {
               
                $productCode = ($uninstallString -split "/I|/X" | Where-Object { $_ -like "{*}" })[0].Trim()
                if ($productCode) {
                    Write-LogMessage "Uninstalling MSI package: $productCode"
                    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/X$productCode /quiet /norestart /L*V `"$env:TEMP\msi_uninstall_$($productCode.Replace('{','').Replace('}','')).log`"" -Wait -PassThru -WindowStyle Hidden
                    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                        $removed = $true
                        Write-LogMessage "Successfully removed: $displayName"
                    } else {
                        Write-LogMessage "MSI uninstall failed with exit code: $($process.ExitCode)" "ERROR"
                    }
                }
            }
            elseif ($uninstallString -like "*unins*.exe*") {
               
                $uninstallPath = ($uninstallString -split '"')[1]
                if (!$uninstallPath) { $uninstallPath = $uninstallString.Trim() }
                
                Write-LogMessage "Running Inno Setup uninstaller: $uninstallPath"
                
                
                $dialogKillerJob = Start-Job -ScriptBlock {
                    param($LogPath)
                    
                   
                    function Stop-UninstallerDialogs {
                        param([string]$ProcessName, [int]$TimeoutSeconds = 60)
                        
                        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                        
                        while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
                            
                            Get-Process -Name "*unins*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                            
                            
                            & taskkill /F /IM "unins*.exe" 2>$null
                            
                            Start-Sleep -Seconds 1
                        }
                    }
                    
                    Stop-UninstallerDialogs
                } -ArgumentList $LogPath
                
                
                try {
                    $process = Start-Process -FilePath $uninstallPath -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOCANCEL" -PassThru -WindowStyle Hidden
                    
                    
                    if ($process.WaitForExit(60000)) {
                        $removed = $true
                        Write-LogMessage "Successfully removed: $displayName"
                    } else {
                        Write-LogMessage "Uninstaller timed out, force killing process"
                        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                        $removed = $true  # Consider it removed since we'll force clean
                    }
                } catch {
                    Write-LogMessage "Error running uninstaller: $($_.Exception.Message)" "ERROR"
                }
                
                
                Stop-Job -Job $dialogKillerJob -ErrorAction SilentlyContinue
                Remove-Job -Job $dialogKillerJob -ErrorAction SilentlyContinue
            }
            elseif ($uninstallString -like "*uninst*.exe*") {
                
                $uninstallPath = ($uninstallString -split '"')[1]
                if (!$uninstallPath) { $uninstallPath = $uninstallString.Trim() }
                
                Write-LogMessage "Running NSIS uninstaller: $uninstallPath"
                $process = Start-Process -FilePath $uninstallPath -ArgumentList "/S" -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
                if ($process.ExitCode -eq 0) {
                    $removed = $true
                    Write-LogMessage "Successfully removed: $displayName"
                } else {
                    Write-LogMessage "NSIS uninstall completed with exit code: $($process.ExitCode)"
                    $removed = $true  
                }
            }
            elseif ($uninstallString -like "*.exe*") {
                
                $uninstallPath = ($uninstallString -split '"')[1]
                if (!$uninstallPath) { $uninstallPath = ($uninstallString -split ' ')[0] }
                
                Write-LogMessage "Running generic uninstaller: $uninstallPath"
                
                
                $dialogKillerJob = Start-Job -ScriptBlock {
                    for ($i = 0; $i -lt 120; $i++) {  
                        Get-Process | Where-Object { $_.MainWindowTitle -like "*uninstall*" -or $_.MainWindowTitle -like "*setup*" -or $_.MainWindowTitle -like "*remove*" } | Stop-Process -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 1
                    }
                }
                
                
                $silentArgs = @("/VERYSILENT /SUPPRESSMSGBOXES /SP- /NOCANCEL", "/S", "/SILENT", "/quiet", "-silent", "-q")
                foreach ($arg in $silentArgs) {
                    try {
                        Write-LogMessage "Trying uninstaller with parameter: $arg"
                        $process = Start-Process -FilePath $uninstallPath -ArgumentList $arg -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
                        
                        if ($process.WaitForExit(45000)) {  # 45 second timeout
                            $removed = $true
                            Write-LogMessage "Successfully removed: $displayName using $arg parameter"
                            break
                        } else {
                            Write-LogMessage "Uninstaller timed out with $arg, killing process"
                            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                        }
                    }
                    catch {
                        Write-LogMessage "Failed to uninstall with $arg parameter: $($_.Exception.Message)" "WARNING"
                    }
                }
                
               
                Stop-Job -Job $dialogKillerJob -ErrorAction SilentlyContinue
                Remove-Job -Job $dialogKillerJob -ErrorAction SilentlyContinue
                
                if (!$removed) {
                    Write-LogMessage "All uninstaller attempts failed, will use force removal" "WARNING"
                    $removed = $true  
                }
            }
        }
        
        # Try AppX removal for modern apps (like Skype from Microsoft Store)
        if (!$removed -and $Program.PackageFullName) {
            Write-LogMessage "Removing AppX package: $($Program.PackageFullName)"
            try {
                Remove-AppxPackage -Package $Program.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                Remove-AppxProvisionedPackage -Online -PackageName $Program.PackageFullName -ErrorAction SilentlyContinue
                $removed = $true
                Write-LogMessage "Successfully removed AppX package: $displayName"
            }
            catch {
                Write-LogMessage "Error removing AppX package: $($_.Exception.Message)" "WARNING"
            }
        }
        if (!$removed) {
            Write-LogMessage "Standard uninstall failed or unavailable. Attempting force removal for: $displayName" "WARNING"
            
            
            Stop-SoftwareProcesses -SoftwarePattern $SoftwarePattern
            Start-Sleep -Seconds 2
            
            
            if ($SoftwarePattern.AdditionalPaths) {
                foreach ($path in $SoftwarePattern.AdditionalPaths) {
                    if (Test-Path $path) {
                        Write-LogMessage "Force removing installation directory: $path"
                        try {
                            
                            takeown /f "$path" /r /d y | Out-Null
                            icacls "$path" /grant administrators:F /t | Out-Null
                            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                            $removed = $true
                        }
                        catch {
                            Write-LogMessage "Error force removing directory $path : $($_.Exception.Message)" "ERROR"
                        }
                    }
                }
            }
            
            
            if ($SoftwarePattern.RegistryPath -and (Test-Path $SoftwarePattern.RegistryPath)) {
                try {
                    Write-LogMessage "Force removing registry path: $($SoftwarePattern.RegistryPath)"
                    Remove-Item -Path $SoftwarePattern.RegistryPath -Recurse -Force -ErrorAction SilentlyContinue
                    $removed = $true
                }
                catch {
                    Write-LogMessage "Error removing registry path: $($_.Exception.Message)" "ERROR"
                }
            }
            
            if ($removed) {
                Write-LogMessage "Force removal completed for: $displayName"
            }
        }
        
        
        if ($removed -and ($SoftwarePattern.RegistryPath -or $SoftwarePattern.AdditionalPaths -or $SoftwarePattern.UserPaths)) {
            try {
                
                if ($SoftwarePattern.RegistryPath -and (Test-Path $SoftwarePattern.RegistryPath)) {
                    Write-LogMessage "Cleaning registry path: $($SoftwarePattern.RegistryPath)"
                    Remove-Item -Path $SoftwarePattern.RegistryPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                
                
                if ($SoftwarePattern.AdditionalPaths) {
                    foreach ($path in $SoftwarePattern.AdditionalPaths) {
                        if (Test-Path $path) {
                            Write-LogMessage "Removing installation directory: $path"
                            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                
                
                if ($SoftwarePattern.UserPaths) {
                    foreach ($userPath in $SoftwarePattern.UserPaths) {
                        $expandedPath = [Environment]::ExpandEnvironmentVariables($userPath)
                        if (Test-Path $expandedPath) {
                            Write-LogMessage "Removing user data directory: $expandedPath"
                            Remove-Item -Path $expandedPath -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                    
                    
                    $userProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object { $_.Special -eq $false }
                    foreach ($profile in $userProfiles) {
                        foreach ($userPath in $SoftwarePattern.UserPaths) {
                            $profilePath = $userPath -replace '\$env:APPDATA', "$($profile.LocalPath)\AppData\Roaming" -replace '\$env:LOCALAPPDATA', "$($profile.LocalPath)\AppData\Local"
                            if (Test-Path $profilePath) {
                                Write-LogMessage "Removing user profile data: $profilePath"
                                Remove-Item -Path $profilePath -Recurse -Force -ErrorAction SilentlyContinue
                            }
                        }
                    }
                }
            }
            catch {
                Write-LogMessage "Error during cleanup: $($_.Exception.Message)" "WARNING"
            }
        }
        
    }
    catch {
        Write-LogMessage "Error removing $displayName : $($_.Exception.Message)" "ERROR"
    }
    
    return $removed
}


function Main {
    Initialize-Logging -LogPath $LogPath
    
    Write-LogMessage "Starting unauthorized software scan..."
    Write-LogMessage "Detection Mode: $DetectOnly, Log Only: $LogOnly"
    
    
    $installedPrograms = Get-InstalledPrograms
    Write-LogMessage "Found $($installedPrograms.Count) installed programs"
    
    $detectedSoftware = @()
    $removedSoftware = @()
    
    
    foreach ($program in $installedPrograms) {
        foreach ($unauthorizedPattern in $UnauthorizedSoftware) {
            if (Test-UnauthorizedSoftware -Program $program -UnauthorizedPattern $unauthorizedPattern) {
                $displayName = if ($program.DisplayName) { $program.DisplayName } else { $program.Name }
                
                Write-LogMessage "Detected unauthorized software: $displayName" "WARNING"
                $detectedSoftware += @{
                    Program = $program
                    Pattern = $unauthorizedPattern
                    DisplayName = $displayName
                }
                
                if (!$DetectOnly -and !$LogOnly) {
                    $removed = Remove-UnauthorizedSoftware -Program $program -SoftwarePattern $unauthorizedPattern
                    if ($removed) {
                        $removedSoftware += $displayName
                    }
                }
                
                break 
            }
        }
    }
    
    
    Write-LogMessage "=== SUMMARY ==="
    Write-LogMessage "Detected unauthorized software: $($detectedSoftware.Count)"
    
    if ($DetectOnly) {
        Write-LogMessage "Detection mode - no removal attempted"
        foreach ($item in $detectedSoftware) {
            Write-LogMessage "  - $($item.DisplayName)"
        }
    }
    elseif ($LogOnly) {
        Write-LogMessage "Log only mode - no removal attempted"
    }
    else {
        Write-LogMessage "Removed software: $($removedSoftware.Count)"
        foreach ($software in $removedSoftware) {
            Write-LogMessage "  - $software"
        }
    }
    
    Write-LogMessage "Script completed: $(Get-Date)"
    
   
    if ($DetectOnly) {
        if ($detectedSoftware.Count -gt 0) {
            exit 1  
        } else {
            exit 0  
        }
    }
    
    exit 0
}


Main
