<#
.SYNOPSIS
  Parse Android uiautomator dump XML into a readable indented control tree.
  Shows text / content-desc / resource-id / clickable / focused / bounds per node.
  This is your "eyes" when FLAG_SECURE blocks screenshots on TV devices.
.EXAMPLE
  adb -s <serial> shell uiautomator dump /sdcard/uidump.xml
  adb -s <serial> pull /sdcard/uidump.xml .\uidump.xml
  pwsh -File .\uidump-tree.ps1 -Path .\uidump.xml
  pwsh -File .\uidump-tree.ps1 -Path .\uidump.xml -OnlyText   # rows with text/desc only
#>
param(
    [Parameter(Mandatory)] [string]$Path,
    [switch]$OnlyText
)

[xml]$doc = Get-Content $Path -Raw

function Walk($node, [int]$depth) {
    if ($node -isnot [System.Xml.XmlElement]) { return }
    $text = $node.GetAttribute('text')
    $desc = $node.GetAttribute('content-desc')
    $rid  = $node.GetAttribute('resource-id')
    if (-not $OnlyText -or $text -or $desc) {
        $line = '{0}{1} | t="{2}" cd="{3}" rid={4} click={5} focused={6} {7}' -f (
            '  ' * $depth), ($node.GetAttribute('class') -replace '^android\.(widget|view)\.', ''),
            $text, $desc, $rid,
            $node.GetAttribute('clickable'), $node.GetAttribute('focused'),
            $node.GetAttribute('bounds')
        Write-Output $line
    }
    foreach ($child in $node.ChildNodes) { Walk $child ($depth + 1) }
}

Walk $doc.hierarchy.node 0
