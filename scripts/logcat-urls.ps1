<#
.SYNOPSIS
  Extract every URL a given app process has touched from a logcat dump.
.EXAMPLE
  adb -s <serial> logcat -d -v time > .\logcat.txt
  $pid = adb -s <serial> shell pidof com.apple.atve.androidtv.appletv
  pwsh -File .\logcat-urls.ps1 -Log .\logcat.txt -PidFilter $pid
#>
param(
    [Parameter(Mandatory)] [string]$Log,
    [string]$PidFilter = ''
)

$lines = if ($PidFilter) {
    Select-String -Path $Log -Pattern " $PidFilter "
} else {
    Get-Content $Log
}

$urls = @()
foreach ($l in $lines) {
    foreach ($m in [regex]::Matches($l.Line, 'https?://[a-zA-Z0-9._:-]+')) {
        $urls += $m.Value
    }
}
"pid lines scanned: $(@($lines).Count)"
"url hits: $($urls.Count)"
$urls | Sort-Object -Unique
