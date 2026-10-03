<#
.SYNOPSIS
  Appends a timestamped, hash-chained entry to submission/THOUGHTS.md (PowerShell equivalent of thought.sh).
.EXAMPLE
  ./benchmark/scripts/thought.ps1 decision "Use System.CommandLine for parsing"
  "line 1`nline 2" | ./benchmark/scripts/thought.ps1 failure -
  ./benchmark/scripts/thought.ps1 -Verify
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Category,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)] [string[]] $Message,
    [Parameter(ValueFromPipeline = $true)] [string] $InputLine,
    [switch] $Verify
)
begin {
    $ErrorActionPreference = 'Stop'
    $categories = 'start', 'plan', 'decision', 'attempt', 'failure', 'fix', 'pivot', 'ci', 'note', 'end'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $piped = New-Object System.Collections.Generic.List[string]

    function Get-Chain([byte[]] $bytes) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })).Substring(0, 16) }
        finally { $sha.Dispose() }
    }

    $root = (& git rev-parse --show-toplevel 2>$null)
    if (-not $root) { Write-Error 'Run this inside your submission worktree.'; exit 1 }
    $file = Join-Path $root 'submission/THOUGHTS.md'
}
process { if ($null -ne $InputLine) { $piped.Add($InputLine) } }
end {
    if ($Verify) {
        if (-not (Test-Path $file)) { Write-Error "$file not found"; exit 1 }
        $text = $utf8.GetString([System.IO.File]::ReadAllBytes($file))
        $lines = $text.Split("`n")
        if ($lines[-1] -eq '') { $lines = $lines[0..($lines.Length - 2)] }
        $prefix = New-Object System.Text.StringBuilder
        $n = 0; $bad = $false
        foreach ($line in $lines) {
            if ($line -match '^## [0-9TZ:-]+ \| [a-z]+ \| HEAD [0-9a-z]+ \| chain ([0-9a-f]{16})$') {
                $n++
                if ((Get-Chain $utf8.GetBytes($prefix.ToString())) -ne $Matches[1]) {
                    Write-Host "BROKEN chain at entry ${n}: $line"; $bad = $true
                }
            }
            [void]$prefix.Append($line).Append("`n")
        }
        if ($bad) { exit 1 }
        Write-Host "OK: $n entries, chain intact"; exit 0
    }

    if (-not $Category -or $categories -notcontains $Category) {
        Write-Host "Usage: thought.ps1 <category> <message...> | thought.ps1 -Verify`nCategories: $($categories -join ' ')"
        exit 2
    }
    if ($Message.Count -eq 1 -and $Message[0] -eq '-') { $text = $piped -join "`n" } else { $text = $Message -join ' ' }
    $text = (($text -replace "`r", '') -split "`n" | ForEach-Object { $_ -replace '^#', '\#' }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($text)) { Write-Error 'Empty message.'; exit 2 }

    New-Item -ItemType Directory -Force -Path (Split-Path $file) | Out-Null
    if (-not (Test-Path $file)) {
        [System.IO.File]::WriteAllText($file, "# THOUGHTS`n`nAppend-only log written by ``benchmark/scripts/thought.sh``. Do not edit by hand.`n`n", $utf8)
    }
    $existing = [System.IO.File]::ReadAllBytes($file)
    if ($Category -eq 'start' -and ($utf8.GetString($existing) -match '(?m)^## .* \| start \| ')) {
        Write-Error "A 'start' entry already exists."; exit 2
    }
    $chain = Get-Chain $existing
    $ts = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $head = (& git -C $root rev-parse --short HEAD 2>$null); if (-not $head) { $head = 'none' }
    [System.IO.File]::AppendAllText($file, "## $ts | $Category | HEAD $head | chain $chain`n`n$text`n`n", $utf8)
    Write-Host "logged [$ts] $Category"
}
