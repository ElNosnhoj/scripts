
function ElevatedPs {
    $commands = $args -join ' '
    # exit if no command was provided
    if ([string]::IsNullOrWhiteSpace($commands)) {
        Write-Host "No command provided. Exiting."
        return
    }

    # temp files
    $tempPipe = "$env:TEMP\elevated-ps-pipe"
    $tempCopy = "$env:TEMP\elevated-ps-copy"

    # clear temp files
    Remove-Item -Path $tempPipe -ErrorAction SilentlyContinue
    Remove-Item -Path $tempCopy -ErrorAction SilentlyContinue

    # parse commands, ignore empty or whitespace-only
    $processed = $Commands -split "`r?`n|;" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" } |
        ForEach-Object { "$_ | Out-File -FilePath '$tempPipe' -Encoding UTF8 -Append" }

    # join commands into a single string for Start-Process
    $cmdString = $processed -join "`n"
    $cmdString += "`nCopy-Item -Path '$tempPipe' -Destination '$tempCopy' -Force"

    $wrappedCmd = @"
try {
$cmdString
} catch {
'ERROR: ' + `$_.Exception.Message | Out-File -FilePath '$tempPipe' -Append
}
Copy-Item -Path '$tempPipe' -Destination '$tempCopy' -Force
"@

    # start the process elevated and hidden
    Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-Command', $wrappedCmd
    )

    # wait until file exists
    while (-not (Test-Path $tempCopy)) { Start-Sleep 0.1 }

    # wait until file is free
    $locked = $true
    while ($locked) {
        try {
            $stream = [System.IO.File]::Open($tempCopy, 'Open', 'ReadWrite', 'None')
            $stream.Close()
            $locked = $false
            Start-Sleep 0.1
        } catch {
            Start-Sleep 0.1
        }
    }

    # show output and cleanup
    Get-Content $tempCopy
    Remove-Item -Path $tempCopy -ErrorAction SilentlyContinue
    Remove-Item -Path $tempPipe -ErrorAction SilentlyContinue
}


# ===============================================
# examples
# ===============================================
ElevatedPs "echo hello; echo world" 

