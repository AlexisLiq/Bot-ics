function Normalize-UiText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

    $formD = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($char in $formD.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($char)
        if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($char)
        }
    }

    return ([regex]::Replace($sb.ToString().ToLowerInvariant(), "\s+", " ")).Trim()
}

function Get-ProcessNameSafe {
    param([int]$ProcId)
    try { return (Get-Process -Id $ProcId -ErrorAction Stop).ProcessName } catch { return "" }
}

function Parse-Handle {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return [int64]0 }
    $parsed = [int64]0
    if ([int64]::TryParse($Value, [ref]$parsed)) { return $parsed }
    return [int64]0
}

function Contains-AnyToken {
    param(
        [string]$Haystack,
        [string[]]$Tokens
    )

    if (-not $Haystack) { return $false }
    foreach ($token in $Tokens) {
        $norm = Normalize-UiText $token
        if ($norm -and $Haystack.Contains($norm)) { return $true }
    }
    return $false
}
