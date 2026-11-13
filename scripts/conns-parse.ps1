<#
.SYNOPSIS
  Parse /connections API snapshots (see conns-api-snapshot.sh) and attribute
  download traffic per client and per chain/route. Answers questions like
  "is the video riding the proxy or going direct?"
.EXAMPLE
  pwsh -File .\conns-parse.ps1 -File .\snapshots.txt -SourceIP 192.168.1.50
#>
param(
    [Parameter(Mandatory)] [string]$File,
    [Parameter(Mandatory)] [string]$SourceIP
)

$raw = Get-Content $File -Raw
$snaps = $raw -split '---SNAP---' | Where-Object { $_.Trim() -match '^\{' }
"snapshots: $($snaps.Count)"

$first = @{}; $last = @{}; $meta = @{}
$idx = 0
foreach ($s in $snaps) {
    $j = $s.Trim() | ConvertFrom-Json
    foreach ($c in $j.connections) {
        if ($c.metadata.sourceIP -ne $SourceIP) { continue }
        $meta[$c.id] = $c
        if ($idx -eq 0) { $first[$c.id] = [double]$c.download }
        $last[$c.id] = [double]$c.download
    }
    $idx++
}

$rows = @()
foreach ($id in $last.Keys) {
    $c = $meta[$id]
    $startDl = if ($first.ContainsKey($id)) { $first[$id] } else { 0 }
    $hname = $c.metadata.sniffHost; if (-not $hname) { $hname = $c.metadata.host }
    if (-not $hname) { $hname = $c.metadata.destinationIP }
    $rows += [pscustomobject]@{
        DeltaKB = [math]::Round(([double]$last[$id] - $startDl) / 1KB, 1)
        TotalKB = [math]::Round([double]$last[$id] / 1KB, 1)
        Chain   = ($c.chains -join '->')
        HName   = $hname
        DestIP  = $c.metadata.destinationIP
        Rule    = "$($c.rule) $($c.rulePayload)"
    }
}

"=== client $SourceIP connections: $($rows.Count) ==="
"=== download delta between first/last snapshot, by chain ==="
$rows | Group-Object Chain | ForEach-Object {
    [pscustomobject]@{
        Chain     = $_.Name
        ConnCount = $_.Count
        DeltaKB   = [math]::Round(($_.Group | Measure-Object DeltaKB -Sum).Sum, 1)
        TotalKB   = [math]::Round(($_.Group | Measure-Object TotalKB -Sum).Sum, 1)
    }
} | Sort-Object DeltaKB -Descending | Format-Table -AutoSize

"=== top connections by delta ==="
$rows | Sort-Object DeltaKB -Descending | Select-Object -First 15 |
    Format-Table DeltaKB, TotalKB, Chain, HName, DestIP, Rule -AutoSize |
    Out-String -Width 260
