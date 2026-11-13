<#
.SYNOPSIS
  Sample /proc/net/tcp{,6} on an Android device every N seconds, recording the
  remote endpoints of all ESTABLISHED connections belonging to one app uid.
  Remote addresses arrive as little-endian hex; this script decodes them.
.EXAMPLE
  $uid = 10134
  pwsh -File .\tcp-uid-sampler.ps1 -Serial 192.168.1.50:5555 -Uid $uid -Minutes 4 |
    Out-File .\endpoints.txt
#>
param(
    [Parameter(Mandatory)] [string]$Serial,
    [Parameter(Mandatory)] [int]$Uid,
    [int]$Minutes = 4,
    [int]$IntervalSeconds = 2
)

function Decode-HexEndpoint([string]$hex) {
    $ipHex, $portHex = $hex.Split(':')
    $port = [Convert]::ToInt32($portHex, 16)
    if ($ipHex.Length -eq 8) {
        # IPv4: four little-endian bytes
        $b = for ($i = 0; $i -lt 8; $i += 2) { [Convert]::ToInt32($ipHex.Substring($i, 2), 16) }
        '{0}.{1}.{2}.{3}:{4}' -f $b[3], $b[2], $b[1], $b[0], $port
    }
    elseif ($ipHex.Length -eq 32) {
        # IPv6: four little-endian 32-bit words (v4-mapped handled too)
        $bytes = New-Object byte[] 16
        for ($w = 0; $w -lt 4; $w++) {
            $word = $ipHex.Substring($w * 8, 8)
            for ($b2 = 0; $b2 -lt 4; $b2++) {
                $bytes[$w * 4 + $b2] = [Convert]::ToByte($word.Substring((3 - $b2) * 2, 2), 16)
            }
        }
        if (($bytes[0..9] | ForEach-Object { $_ -eq 0 }) -notcontains $false -and $bytes[10] -eq 255 -and $bytes[11] -eq 255) {
            '{0}.{1}.{2}.{3}:{4}' -f $bytes[15], $bytes[14], $bytes[13], $bytes[12], $port
        }
        else {
            ($bytes | ForEach-Object { $_.ToString('x2') }) -join '' | ForEach-Object {
                $h = for ($i2 = 0; $i2 -lt 32; $i2 += 4) { $_.Substring($i2, 4) }
                ($h -join ':') + ':' + $port
            }
        }
    }
    else { "<unparsed:$hex>" }
}

$found = @{}
$deadline = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $deadline) {
    try {
        $t  = adb -s $Serial shell 'cat /proc/net/tcp 2>/dev/null'
        $t6 = adb -s $Serial shell 'cat /proc/net/tcp6 2>/dev/null'
        foreach ($line in (@($t) + @($t6))) {
            $cols = ($line -replace '^\s+', '') -split '\s+'
            # state 01 = ESTABLISHED; column 7 = uid
            if ($cols.Count -gt 7 -and [int]$cols[7] -eq $Uid -and $cols[3] -eq '01') {
                $found[(Decode-HexEndpoint $cols[2])] = $true
            }
        }
    } catch { }
    Start-Sleep $IntervalSeconds
}
$found.Keys | Sort-Object
"unique endpoints: $($found.Count)"
