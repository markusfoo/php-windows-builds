# Shared helpers for build-imagick.yaml and build-mysql.yaml.
#
# Why this exists: the workflows used a hard-coded QA version (qa_version =
# 8.6.0RC3). downloads.php.net/~windows/qa only keeps the CURRENT release
# candidate, so every new RC (and finally the GA move to /releases) made the
# download 404 and the whole build failed after five pointless retries.
# These helpers pick the newest official build that actually exists.

$script:PhpQaBase       = 'https://downloads.php.net/~windows/qa'
$script:PhpReleasesBase = 'https://downloads.php.net/~windows/releases'

function Get-FileWithRetry {
    param([string]$Url, [string]$OutFile, [int]$Retries = 5)

    for ($i = 1; $i -le $Retries; $i++) {
        $code = $null
        try {
            Write-Host "[$i/$Retries] Downloading: $Url"
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -MaximumRedirection 10

            if (-not (Test-Path $OutFile)) { throw "File was not written." }
            $size = (Get-Item $OutFile).Length
            if ($size -lt 10000) { throw "Downloaded file is suspiciously small ($size bytes) - likely an error page, not a real archive." }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($OutFile)
            $zip.Dispose()

            Write-Host "OK ($size bytes)."
            return
        } catch {
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            Write-Host "Attempt $i failed: $($_.Exception.Message)"
            if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
            # 404/403/410 will not fix themselves - fail now with a clear message.
            if ($code -in 403, 404, 410) { throw "HTTP $code for $Url - the file does not exist (retrying is pointless)." }
            if ($i -lt $Retries) { Start-Sleep -Seconds (5 * $i) }
        }
    }
    throw "Failed to download a valid archive from $Url after $Retries attempts."
}

# 8.6.0RC7 -> sortable key. Stable > RC > beta > alpha. '-dev' builds are not supported.
function ConvertTo-PhpVersionKey {
    param([string]$Version)
    if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)(?:(alpha|beta|RC)(\d+))?$') { return $null }
    $major = [int]$Matches[1]; $minor = [int]$Matches[2]; $patch = [int]$Matches[3]
    $stage = 4; $num = 0
    if ($Matches[4]) {
        $stage = switch ($Matches[4]) { 'alpha' { 1 } 'beta' { 2 } 'RC' { 3 } }
        $num = [int]$Matches[5]
    }
    return ('{0:D3}.{1:D3}.{2:D3}.{3}.{4:D3}' -f $major, $minor, $patch, $stage, $num)
}

function Get-DirectoryFileNames {
    param([string]$BaseUrl)
    $r = Invoke-WebRequest -Uri "$BaseUrl/" -UseBasicParsing -MaximumRedirection 10
    # Apache autoindex: href is either a bare file name or an absolute path - keep the last segment,
    # skip directories (trailing '/') and sort/query links ('?C=N;O=D').
    $names = foreach ($m in [regex]::Matches([string]$r.Content, 'href="([^"?#]+)"')) {
        $h = $m.Groups[1].Value
        if ($h.EndsWith('/')) { continue }
        [uri]::UnescapeDataString(($h -split '/')[-1])
    }
    return @($names | Select-Object -Unique)
}

function Test-RemoteFile {
    param([string]$Url)
    try {
        Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -MaximumRedirection 10 | Out-Null
        return $true
    } catch { return $false }
}

# Returns @{ Version = '8.6.0RC7'; BaseUrl = 'https://.../qa' } for the newest official
# build whose files ALL exist. $Files are templates with a {V} placeholder, e.g.
#   'php-devel-pack-{V}-Win32-vs18-x64.zip'
# -Version 'auto'   : newest build of -Series across php.net QA and /releases
#                     (GA beats RC; on a tie /releases wins).
# -Version '8.6.0RC7': exactly that one, from QA or /releases (whichever has it).
function Resolve-OfficialPhpBuild {
    param(
        [string]$Version = 'auto',
        [string]$Series  = '8.6',
        [Parameter(Mandatory)][string[]]$Files
    )

    $sources = @($script:PhpQaBase, $script:PhpReleasesBase)

    if ($Version -and $Version -ne 'auto') {
        foreach ($base in $sources) {
            $missing = @($Files | Where-Object { -not (Test-RemoteFile "$base/$($_.Replace('{V}', $Version))") })
            if ($missing.Count -eq 0) {
                Write-Host "Using pinned official build $Version from $base"
                return @{ Version = $Version; BaseUrl = $base }
            }
        }
        throw "qa_version '$Version' was not found in $($sources -join ' or '). Use 'auto' to pick the newest available build."
    }

    $firstPattern = '^' + ([regex]::Escape($Files[0])).Replace('\{V}', '(?<v>.+?)') + '$'
    $best = $null; $bestKey = ''
    foreach ($base in $sources) {
        try { $names = Get-DirectoryFileNames -BaseUrl $base }
        catch { Write-Host "WARNING: could not list $base : $($_.Exception.Message)"; continue }

        foreach ($n in $names) {
            if ($n -notmatch $firstPattern) { continue }
            $v = $Matches['v']
            if ($Series -and -not $v.StartsWith("$Series.")) { continue }
            $key = ConvertTo-PhpVersionKey $v
            if (-not $key) { continue }
            $allListed = -not ($Files | Where-Object { $names -notcontains $_.Replace('{V}', $v) })
            if (-not $allListed) { continue }
            # '>=' so that on equal versions the later source (/releases) wins.
            if ($key -ge $bestKey) { $best = @{ Version = $v; BaseUrl = $base }; $bestKey = $key }
        }
    }

    if (-not $best) {
        throw "No official php.net build of series '$Series' with all of [$($Files -join ', ')] found in QA or /releases."
    }
    Write-Host "Auto-selected official build $($best.Version) from $($best.BaseUrl)"
    return $best
}
