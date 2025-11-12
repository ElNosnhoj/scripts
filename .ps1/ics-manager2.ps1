function Set-Ics {
    param (
        [string]$Src,
        [string]$Dst
    )
    #$net=New-Object -ComObject HNetCfg.HNetShare;$net.EnumEveryConnection()|%{$c=$net.INetSharingConfigurationForINetConnection($_);$p=$net.NetConnectionProps($_);if($c.SharingEnabled){$c.DisableSharing()};if($p.Name-eq $Src){$c.EnableSharing(0)}elseif($p.Name-eq $Dst){$c.EnableSharing(1)}}
    $net = New-Object -ComObject HNetCfg.HNetShare

    $net.EnumEveryConnection() | ForEach-Object {
        $c = $net.INetSharingConfigurationForINetConnection($_)
        $p = $net.NetConnectionProps($_)

        # Disable ICS if already enabled
        if ($c.SharingEnabled) {
            $c.DisableSharing()
        }

        # Enable ICS based on source/destination
        if ($p.Name -eq $Src) {
            $c.EnableSharing(0)  # Source network
        }
        elseif ($p.Name -eq $Dst) {
            $c.EnableSharing(1)  # Destination network
        }
    }
}


function Disable-Ics {
    # Create NetSharingManager COM object
    $netShare = New-Object -ComObject HNetCfg.HNetShare

    # Enumerate all network connections
    $connections = $netShare.EnumEveryConnection()

    foreach ($conn in $connections) {
        $config = $netShare.INetSharingConfigurationForINetConnection($conn)
        $props = $netShare.NetConnectionProps($conn)

        # Disable ICS if enabled
        if ($config.SharingEnabled) {
            $config.DisableSharing()
            Write-Host "Disabled Internet Connection Sharing on $($props.Name)"
        }
        else {
            Write-Host "ICS already disabled on $($props.Name)"
        }
    }
}

function Get-Interfaces {
    Get-NetAdapter | Select-Object -ExpandProperty Name
}


function Get-Ics {
    $netShare = New-Object -ComObject HNetCfg.HNetShare
    $connections = $netShare.EnumEveryConnection()
    $statusList = @()

    foreach ($conn in $connections) {
        $config = $netShare.INetSharingConfigurationForINetConnection($conn)
        $props = $netShare.NetConnectionProps($conn)

        $connectionType = ""
        if ($config.SharingEnabled) {
            switch ($config.SharingConnectionType) {
                0 { $connectionType = "Public" }    # Provides Internet
                1 { $connectionType = "Private" }   # Receives shared Internet
            }
        }

        $statusList += [PSCustomObject]@{
            ConnectionName = $props.Name
            IcsEnabled     = $config.SharingEnabled
            ConnectionType = $connectionType
        }
    }

    # Sort ICS-enabled interfaces at the top
    return $statusList | Sort-Object -Property IcsEnabled -Descending | Format-Table -AutoSize
}

# Example usage: Disable-Ics
# Example usage: Set-Ics -Src "Ethernet" -Dst "Wi-Fi"
# Example usage: Get-Ics
