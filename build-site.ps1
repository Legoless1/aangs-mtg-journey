param(
  [string]$BlogRoot = $PSScriptRoot,
  [string]$OutputDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $BlogRoot 'docs'
}

function Convert-JsSingleQuoted([string]$Value) {
  if ($null -eq $Value) { return '' }
  return ($Value -replace "\\'", "'" -replace '\\\\', '\')
}

function Get-ConfigString([string]$Source, [string]$Name, [string]$Default = '') {
  $match = [regex]::Match($Source, ("{0}\s*:\s*'((?:\\.|[^'])*)'" -f [regex]::Escape($Name)))
  if ($match.Success) { return Convert-JsSingleQuoted $match.Groups[1].Value }
  return $Default
}

function Get-ConfigNumber([string]$Source, [string]$Name, [int]$Default) {
  $match = [regex]::Match($Source, ("{0}\s*:\s*(\d+)" -f [regex]::Escape($Name)))
  if ($match.Success) { return [int]$match.Groups[1].Value }
  return $Default
}

function Get-StyleBlock([string]$Source) {
  $match = [regex]::Match($Source, '<style>([\s\S]*?)</style>')
  if (-not $match.Success) { throw 'Could not extract inline CSS from index.html.' }
  return $match.Groups[1].Value.Trim()
}

function HtmlEscape([string]$Value) {
  if ($null -eq $Value) { return '' }
  return ([System.Net.WebUtility]::HtmlEncode($Value) -replace "'", '&#39;')
}

function AttrEscape([string]$Value) {
  if ($null -eq $Value) { return '' }
  return ((HtmlEscape $Value) -replace '`', '&#96;')
}

function XmlEscape([string]$Value) {
  if ($null -eq $Value) { return '' }
  return [System.Security.SecurityElement]::Escape($Value)
}

function Normalize-LineEndings([string]$Text) {
  if ($null -eq $Text) { return '' }
  return ($Text -replace "`r`n?", "`n")
}

function Ensure-Directory([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Utf8File([string]$Path, [string]$Content) {
  $parent = Split-Path -Parent $Path
  if ($parent) { Ensure-Directory $parent }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Normalize-Tags($Value) {
  if ($null -eq $Value) { return @() }
  if ($Value -is [string]) {
    $text = $Value.Trim()
    if ($text.StartsWith('[') -and $text.EndsWith(']')) {
      $text = $text.Substring(1, $text.Length - 2)
    }
    if (-not $text) { return @() }
    return @($text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    return @($Value | ForEach-Object { [string]$_ } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  }
  return @()
}

function Parse-Date([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  try {
    return [datetime]::ParseExact($Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
  } catch {
    return $null
  }
}

function Format-Date([datetime]$Value) {
  return $Value.ToString('MMMM d, yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-Month([string]$Month) {
  $monthNumber = [int]$Month
  return ([datetime]::new(2000, $monthNumber, 1)).ToString('MMMM', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-Excerpt([string]$Text, [int]$Length) {
  $value = [string]$Text
  $value = $value.Trim()
  if (-not $value) { return '' }
  if ($value.Length -le $Length) { return $value }
  $slice = $value.Substring(0, $Length)
  $slice = $slice -replace '\s+\S*$', ''
  return ($slice.Trim() + '...')
}

function Slugify([string]$Value) {
  $text = [string]$Value
  $text = $text.Trim().ToLowerInvariant()
  $text = [regex]::Replace($text, '[^a-z0-9_-]+', '-')
  $text = [regex]::Replace($text, '-{2,}', '-')
  return $text.Trim('-')
}

function Parse-FrontMatter([string]$Raw) {
  $text = Normalize-LineEndings $Raw
  $parse = {
    param([string[]]$Lines)
    $meta = @{}
    foreach ($line in $Lines) {
      $match = [regex]::Match($line, '^([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.*)$')
      if ($match.Success) {
        $key = $match.Groups[1].Value.ToLowerInvariant()
        $value = $match.Groups[2].Value.Trim()
        if ($key -eq 'tags') {
          $meta[$key] = Normalize-Tags $value
        } else {
          $meta[$key] = $value
        }
      }
    }
    return $meta
  }

  if ($text.StartsWith("---`n")) {
    $end = $text.IndexOf("`n---`n", 4)
    if ($end -ge 0) {
      return [pscustomobject]@{
        Meta = & $parse ($text.Substring(4, $end - 4).Split("`n"))
        Body = $text.Substring($end + 5)
      }
    }
  }

  $lines = $text.Split("`n")
  $frontMatter = New-Object System.Collections.Generic.List[string]
  $index = 0
  while ($index -lt $lines.Count) {
    if ([string]::IsNullOrWhiteSpace($lines[$index])) {
      $index++
      break
    }
    if ($lines[$index] -match '^[A-Za-z][A-Za-z0-9_-]*\s*:') {
      $frontMatter.Add($lines[$index])
      $index++
      continue
    }
    break
  }

  if ($frontMatter.Count -ge 2 -and $index -lt $lines.Count) {
    return [pscustomobject]@{
      Meta = & $parse $frontMatter.ToArray()
      Body = (($lines[$index..($lines.Count - 1)]) -join "`n")
    }
  }

  return [pscustomobject]@{ Meta = @{}; Body = $text }
}

function Parse-CommentMeta([hashtable]$Meta) {
  $get = {
    param([string[]]$Keys)
    foreach ($key in $Keys) {
      if ($Meta.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$Meta[$key])) {
        return [string]$Meta[$key]
      }
    }
    return ''
  }
  $enabled = $false
  if ($Meta.ContainsKey('comments')) {
    $enabled = [regex]::IsMatch([string]$Meta['comments'], '^(1|true|yes|on|cusdis)$', 'IgnoreCase')
  }
  return [pscustomobject]@{
    Enabled = $enabled
    Id = (& $get @('comment-id', 'comment_id', 'commentid'))
    Url = (& $get @('comment-url', 'comment_url', 'commenturl'))
    Title = (& $get @('comment-title', 'comment_title', 'commenttitle'))
  }
}

function Normalize-PathKey([string]$Value) {
  if ($null -eq $Value) { return '' }
  $text = $Value -replace '\\', '/'
  $text = $text -replace '^\.?/', ''
  $text = $text.TrimStart('/')
  return $text.ToLowerInvariant()
}

function Decode-UrlSegment([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  try { return [uri]::UnescapeDataString($Value) } catch { return $Value }
}

function Get-RootPrefix([string]$RelativeFilePath) {
  $dir = Split-Path -Parent $RelativeFilePath
  if ([string]::IsNullOrWhiteSpace($dir) -or $dir -eq '.') { return '' }
  $parts = @($dir -split '[\\/]' | Where-Object { $_ })
  if (-not $parts.Count) { return '' }
  return (($parts | ForEach-Object { '../' }) -join '')
}

function Apply-RootPrefix([string]$Path, [string]$RootPrefix) {
  $clean = [string]$Path
  $clean = $clean -replace '^\./', ''
  $clean = $clean.TrimStart('/')
  if (-not $clean) {
    return ($RootPrefix + 'index.html')
  }
  if ($clean.EndsWith('/')) {
    return ($RootPrefix + $clean + 'index.html')
  }
  return ($RootPrefix + $clean)
}

function Is-ExternalUrl([string]$Url) {
  return [regex]::IsMatch([string]$Url, '^(https?:)?//', 'IgnoreCase') -or [regex]::IsMatch([string]$Url, '^(mailto:|tel:|data:)', 'IgnoreCase')
}

$script:PagePathBySlug = @{}
$script:TagSlugByKey = @{}
$script:AuthorSlugByKey = @{}

function Convert-HashRouteToPath([string]$Hash) {
  $value = [string]$Hash
  $value = $value.Trim()
  if (-not $value) { return '' }
  if ($value.StartsWith('/#/')) { $value = $value.Substring(1) }
  if ($value.StartsWith('#/')) {
    $value = $value.Substring(2)
  } elseif ($value.StartsWith('#')) {
    return $value
  }

  $pathPart = $value
  $query = ''
  if ($value.Contains('?')) {
    $parts = $value.Split('?', 2)
    $pathPart = $parts[0]
    $query = $parts[1]
  }

  $segments = @($pathPart.Trim('/').Split('/') | Where-Object { $_ })
  if (-not $segments.Count) { return '' }

  switch ($segments[0].ToLowerInvariant()) {
    'post' {
      if ($segments.Count -ge 2) { return ('post/{0}/' -f (Slugify (Decode-UrlSegment $segments[1]))) }
      return 'post/'
    }
    'page' {
      if ($segments.Count -ge 2) {
        $slug = Slugify (Decode-UrlSegment $segments[1])
        if ($script:PagePathBySlug.ContainsKey($slug)) { return $script:PagePathBySlug[$slug] }
        return ('{0}/' -f $slug)
      }
      return 'pages/'
    }
    'pages' { return 'pages/' }
    'archive' {
      if ($segments.Count -eq 1) { return 'archive/' }
      if ($segments.Count -eq 2) { return ('archive/{0}/' -f $segments[1]) }
      return ('archive/{0}/{1}/' -f $segments[1], $segments[2])
    }
    'tags' { return 'tags/' }
    'tag' {
      if ($segments.Count -ge 2) {
        $key = (Decode-UrlSegment $segments[1]).ToLowerInvariant()
        $slug = if ($script:TagSlugByKey.ContainsKey($key)) { $script:TagSlugByKey[$key] } else { Slugify $key }
        return ('tag/{0}/' -f $slug)
      }
      return 'tags/'
    }
    'authors' { return 'authors/' }
    'author' {
      if ($segments.Count -ge 2) {
        $key = (Decode-UrlSegment $segments[1]).ToLowerInvariant()
        $slug = if ($script:AuthorSlugByKey.ContainsKey($key)) { $script:AuthorSlugByKey[$key] } else { Slugify $key }
        return ('author/{0}/' -f $slug)
      }
      return 'authors/'
    }
    'search' {
      $path = 'search/'
      if ($query) { return ($path + '?' + $query) }
      return $path
    }
    'feed' { return 'feed.xml' }
    'feed.xml' { return 'feed.xml' }
    default {
      if ($pathPart.EndsWith('.xml')) { return $pathPart.TrimStart('/') }
      return ($pathPart.TrimStart('/') + '/')
    }
  }
}

function Resolve-GeneratedUrl([string]$Url, [string]$RootPrefix) {
  $value = [string]$Url
  $value = $value.Trim()
  if (-not $value) { return '#' }
  if ($value -match '^(?i)javascript:') { return '#' }
  if ($value -match '^#(?!/)') { return $value }
  if (Is-ExternalUrl $value) { return $value }
  if ($value -eq 'feed.xml') { return Apply-RootPrefix 'feed.xml' $RootPrefix }
  if ($value.StartsWith('#/') -or $value.StartsWith('/#/')) {
    return Apply-RootPrefix (Convert-HashRouteToPath $value) $RootPrefix
  }
  if ($value.StartsWith('/')) {
    return Apply-RootPrefix $value $RootPrefix
  }
  if ($value -match '^(assets/|feed\.xml$|post/|archive/|tag/|tags/|author/|authors/|pages/|search/)') {
    return Apply-RootPrefix $value $RootPrefix
  }
  return $value
}

function Clean-Dimension([string]$Value) {
  $text = [string]$Value
  $text = $text.Trim().ToLowerInvariant()
  if (-not $text -or $text -eq 'auto') { return 'auto' }
  if ($text -match '^\d+$') { return ('{0}px' -f [Math]::Min([int]$text, 4096)) }
  if ($text -match '^\d+(\.\d+)?(px|%|vw|vh|rem|em)$') { return $text }
  return ''
}

function Parse-SizeToken([string]$Token) {
  $tokenValue = [string]$Token
  $tokenValue = $tokenValue.Trim()
  if (-not $tokenValue) { return [pscustomobject]@{ Width = ''; Height = '' } }
  if ($tokenValue.StartsWith('=')) { $tokenValue = $tokenValue.Substring(1) }
  $match = [regex]::Match($tokenValue, '^([0-9.]+(?:px|%|vw|vh|rem|em)?)?x([0-9.]+(?:px|%|vw|vh|rem|em)?)?$')
  if ($match.Success) {
    return [pscustomobject]@{
      Width = Clean-Dimension $match.Groups[1].Value
      Height = Clean-Dimension $match.Groups[2].Value
    }
  }
  return [pscustomobject]@{ Width = Clean-Dimension $tokenValue; Height = '' }
}

function Unescape-AttrValue([string]$Value) {
  return ([string]$Value -replace '\\(["''\\])', '$1')
}

function Parse-AttrBlock([string]$Raw) {
  $result = @{}
  if ([string]::IsNullOrWhiteSpace($Raw)) { return $result }
  $pattern = '([a-zA-Z][\w-]*)\s*=\s*("(?:\\.|[^"])*"|''(?:\\.|[^''])*''|[^\s}]+)'
  foreach ($match in [regex]::Matches($Raw, $pattern)) {
    $value = $match.Groups[2].Value.Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $result[$match.Groups[1].Value.ToLowerInvariant()] = Unescape-AttrValue $value
  }
  if ($Raw -match '\bthumb\b' -and -not $result.ContainsKey('thumb')) {
    $result['thumb'] = 'true'
  }
  return $result
}

function Parse-MarkdownImageInner([string]$Inner) {
  $value = [string]$Inner
  $value = $value.Trim()
  $title = ''
  $match = [regex]::Match($value, '\s+"([^"]*)"\s*$')
  if ($match.Success) {
    $title = $match.Groups[1].Value
    $value = $value.Substring(0, $match.Index).Trim()
  } else {
    $match = [regex]::Match($value, "\s+'([^']*)'\s*$")
    if ($match.Success) {
      $title = $match.Groups[1].Value
      $value = $value.Substring(0, $match.Index).Trim()
    }
  }
  $size = ''
  $sizeMatch = [regex]::Match($value, '\s*=\s*([^\s]+)\s*$')
  if ($sizeMatch.Success) {
    $size = $sizeMatch.Groups[1].Value
    $value = $value.Substring(0, $sizeMatch.Index).Trim()
  }
  $src = ($value -split '\s+')[0]
  $dims = Parse-SizeToken $size
  return [pscustomobject]@{ Src = $src; Title = $title; Width = $dims.Width; Height = $dims.Height }
}
function Parse-WikiImage([string]$Src, [string]$OptionRaw) {
  $options = @()
  if (-not [string]::IsNullOrWhiteSpace($OptionRaw)) {
    $options = @($OptionRaw.Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  }
  $result = [ordered]@{
    Src = $Src
    Alt = ''
    Title = ''
    Width = ''
    Height = ''
    Thumb = $false
    Caption = ''
    Link = ''
    Class = ''
  }
  foreach ($part in $options) {
    $lower = $part.ToLowerInvariant()
    if ($lower -match '^(thumb|thumbnail|frame)$') {
      $result['Thumb'] = $true
      continue
    }
    if ($lower.StartsWith('alt=')) {
      $result['Alt'] = $part.Substring(4).Trim()
      continue
    }
    if ($lower.StartsWith('class=')) {
      $result['Class'] = $part.Substring(6).Trim()
      continue
    }
    if ($lower.StartsWith('link=')) {
      $result['Link'] = $part.Substring(5).Trim()
      continue
    }
    if ($lower.StartsWith('caption=')) {
      $result['Caption'] = $part.Substring(8).Trim()
      continue
    }
    $match = [regex]::Match($part, '^(\d+)(?:x(\d+))?px$', 'IgnoreCase')
    if ($match.Success) {
      $result['Width'] = ('{0}px' -f $match.Groups[1].Value)
      if ($match.Groups[2].Success) { $result['Height'] = ('{0}px' -f $match.Groups[2].Value) }
      continue
    }
    $match = [regex]::Match($part, '^x(\d+)px$', 'IgnoreCase')
    if ($match.Success) {
      $result['Height'] = ('{0}px' -f $match.Groups[1].Value)
      continue
    }
    if (-not $result['Caption']) {
      $result['Caption'] = $part
    }
  }
  if (-not $result['Alt']) { $result['Alt'] = if ($result['Caption']) { $result['Caption'] } else { '' } }
  return [pscustomobject]$result
}

function Safe-Class([string]$Value) {
  return (([string]$Value).Split(' ') | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[a-zA-Z0-9_-]{1,40}$' }) -join ' '
}

function Render-Image([pscustomobject]$Options, [string]$RootPrefix) {
  $src = AttrEscape (Resolve-GeneratedUrl $Options.Src $RootPrefix)
  $alt = AttrEscape $Options.Alt
  $titleAttr = if ([string]::IsNullOrWhiteSpace($Options.Title)) { '' } else { ' title="{0}"' -f (AttrEscape $Options.Title) }
  $width = Clean-Dimension $Options.Width
  $height = Clean-Dimension $Options.Height
  $className = Safe-Class $Options.Class
  $thumb = [bool]$Options.Thumb
  $figureClasses = @('img-wrap')
  if ($thumb) { $figureClasses += 'img-thumb' }
  if ($className) { $figureClasses += $className }
  $vars = New-Object System.Collections.Generic.List[string]
  if ($width -and $width -ne 'auto') { $vars.Add('--img-w:{0}' -f $width) }
  if ($height -and $height -ne 'auto') { $vars.Add('--img-h:{0}' -f $height) }
  $styleAttr = if ($vars.Count) { ' style="{0}"' -f (AttrEscape ($vars -join ';')) } else { '' }
  $img = '<img src="{0}" alt="{1}"{2} loading="lazy" decoding="async">' -f $src, $alt, $titleAttr
  $body = $img
  if (-not [string]::IsNullOrWhiteSpace($Options.Link)) {
    $href = Resolve-GeneratedUrl $Options.Link $RootPrefix
    $target = if (Is-ExternalUrl $Options.Link) { ' target="_blank" rel="noopener noreferrer"' } else { '' }
    $body = '<a href="{0}"{1}>{2}</a>' -f (AttrEscape $href), $target, $img
  }
  $caption = ''
  if (-not [string]::IsNullOrWhiteSpace($Options.Caption)) {
    $caption = '<figcaption>{0}</figcaption>' -f (Convert-InlineMarkdown $Options.Caption $RootPrefix)
  }
  return '<figure class="{0}"{1}>{2}{3}</figure>' -f (($figureClasses | Where-Object { $_ }) -join ' '), $styleAttr, $body, $caption
}

function Convert-InlineMarkdown([string]$Text, [string]$RootPrefix) {
  $value = [string]$Text
  $codeSpans = New-Object System.Collections.Generic.List[string]
  $imageSpans = New-Object System.Collections.Generic.List[string]
  $breakSpans = New-Object System.Collections.Generic.List[string]

  $value = [regex]::Replace($value, '`([^`]+)`', {
    param($match)
    $index = $codeSpans.Count
    $codeSpans.Add($match.Groups[1].Value)
    return ('@@CODE{0}@@' -f $index)
  })

  $value = [regex]::Replace($value, '\[\[(?:File|Image):([^\]|]+)(?:\|([^\]]+))?\]\]', {
    param($match)
    $index = $imageSpans.Count
    $imageSpans.Add((Render-Image (Parse-WikiImage $match.Groups[1].Value $match.Groups[2].Value) $RootPrefix))
    return ('@@IMG{0}@@' -f $index)
  }, 'IgnoreCase')

  $value = [regex]::Replace($value, '!\[([^\]]*)\]\(([^)]+)\)(\{[^}]+\})?', {
    param($match)
    $parsed = Parse-MarkdownImageInner $match.Groups[2].Value
    $attrs = Parse-AttrBlock $match.Groups[3].Value
    $dims = Parse-SizeToken $(if ($attrs.ContainsKey('size')) { $attrs['size'] } else { '' })
    $image = [pscustomobject]@{
      Src = $parsed.Src
      Alt = if ($attrs.ContainsKey('alt')) { $attrs['alt'] } else { $match.Groups[1].Value }
      Title = $parsed.Title
      Width = if ($attrs.ContainsKey('width')) { $attrs['width'] } elseif ($dims.Width) { $dims.Width } else { $parsed.Width }
      Height = if ($attrs.ContainsKey('height')) { $attrs['height'] } elseif ($dims.Height) { $dims.Height } else { $parsed.Height }
      Thumb = ($attrs.ContainsKey('thumb') -and [regex]::IsMatch([string]$attrs['thumb'], '^(1|true|yes)$', 'IgnoreCase'))
      Caption = if ($attrs.ContainsKey('caption')) { $attrs['caption'] } else { '' }
      Link = if ($attrs.ContainsKey('link')) { $attrs['link'] } else { '' }
      Class = if ($attrs.ContainsKey('class')) { $attrs['class'] } else { '' }
    }
    $index = $imageSpans.Count
    $imageSpans.Add((Render-Image $image $RootPrefix))
    return ('@@IMG{0}@@' -f $index)
  })

  $value = [regex]::Replace($value, '<br\s*/?>', {
    param($match)
    $index = $breakSpans.Count
    $breakSpans.Add('<br>')
    return ('@@BR{0}@@' -f $index)
  }, 'IgnoreCase')

  $value = [regex]::Replace($value, ' {2,}\n', {
    param($match)
    $index = $breakSpans.Count
    $breakSpans.Add('<br>')
    return ('@@BR{0}@@' -f $index)
  })

  $value = [regex]::Replace($value, '\\\n', {
    param($match)
    $index = $breakSpans.Count
    $breakSpans.Add('<br>')
    return ('@@BR{0}@@' -f $index)
  })

  $value = HtmlEscape $value

  $value = [regex]::Replace($value, '\[([^\]]+)\]\(([^)\s]+)(?:\s+&quot;([^&]*)&quot;)?\)', {
    param($match)
    $label = $match.Groups[1].Value
    $href = Resolve-GeneratedUrl $match.Groups[2].Value $RootPrefix
    $titleAttr = if ($match.Groups[3].Success -and $match.Groups[3].Value) { ' title="{0}"' -f (AttrEscape $match.Groups[3].Value) } else { '' }
    $target = if (Is-ExternalUrl $match.Groups[2].Value) { ' target="_blank" rel="noopener noreferrer"' } else { '' }
    return '<a href="{0}"{1}{2}>{3}</a>' -f (AttrEscape $href), $target, $titleAttr, $label
  })

  $value = [regex]::Replace($value, '\*\*(.+?)\*\*', '<strong>$1</strong>')
  $value = [regex]::Replace($value, '\*(.+?)\*', '<em>$1</em>')
  $value = [regex]::Replace($value, '~~(.+?)~~', '<del>$1</del>')
  $value = $value -replace "`n", ' '

  $value = [regex]::Replace($value, '@@IMG(\d+)@@', { param($match) $imageSpans[[int]$match.Groups[1].Value] })
  $value = [regex]::Replace($value, '@@BR(\d+)@@', { param($match) $breakSpans[[int]$match.Groups[1].Value] })
  $value = [regex]::Replace($value, '@@CODE(\d+)@@', { param($match) '<code>{0}</code>' -f (HtmlEscape $codeSpans[[int]$match.Groups[1].Value]) })
  return $value
}

function Is-BlockLine([string]$Line) {
  return [regex]::IsMatch([string]$Line, '^\s*(```|#{1,6}\s+|>\s?|[-*+]\s+|\d+\.\s+|([-*_])\2{2,}\s*$)')
}

function Convert-MarkdownToHtml([string]$Markdown, [string]$RootPrefix) {
  $lines = (Normalize-LineEndings $Markdown).Split("`n")
  $output = New-Object System.Collections.Generic.List[string]
  $index = 0
  $listType = ''

  while ($index -lt $lines.Count) {
    $line = $lines[$index]
    $trimmed = $line.Trim()

    if (-not $trimmed) {
      if ($listType) {
        $output.Add("</$listType>")
        $listType = ''
      }
      $index++
      continue
    }

    if ($trimmed.StartsWith('```')) {
      if ($listType) {
        $output.Add("</$listType>")
        $listType = ''
      }
      $lang = $trimmed.Substring(3).Trim()
      $index++
      $codeLines = New-Object System.Collections.Generic.List[string]
      while ($index -lt $lines.Count -and -not $lines[$index].Trim().StartsWith('```')) {
        $codeLines.Add($lines[$index])
        $index++
      }
      if ($index -lt $lines.Count) { $index++ }
      $classAttr = if ($lang) { ' class="language-{0}"' -f (AttrEscape $lang) } else { '' }
      $output.Add('<pre><code{0}>{1}</code></pre>' -f $classAttr, (HtmlEscape ($codeLines -join "`n")))
      continue
    }

    $heading = [regex]::Match($line, '^\s*(#{1,6})\s+(.*)$')
    if ($heading.Success) {
      if ($listType) {
        $output.Add("</$listType>")
        $listType = ''
      }
      $level = $heading.Groups[1].Value.Length
      $headingHtml = Convert-InlineMarkdown $heading.Groups[2].Value $RootPrefix
      $output.Add(('<h' + $level + '>' + $headingHtml + '</h' + $level + '>'))
      $index++
      continue
    }

    if ($line -match '^\s*([-*_])\1{2,}\s*$') {
      if ($listType) {
        $output.Add("</$listType>")
        $listType = ''
      }
      $output.Add('<hr>')
      $index++
      continue
    }

    if ($line -match '^\s*>\s?') {
      if ($listType) {
        $output.Add("</$listType>")
        $listType = ''
      }
      $quoteLines = New-Object System.Collections.Generic.List[string]
      while ($index -lt $lines.Count -and $lines[$index] -match '^\s*>\s?') {
        $quoteLines.Add(($lines[$index] -replace '^\s*>\s?', ''))
        $index++
      }
      $output.Add('<blockquote>{0}</blockquote>' -f (Convert-MarkdownToHtml ($quoteLines -join "`n") $RootPrefix))
      continue
    }

    $unordered = [regex]::Match($line, '^\s*[-*+]\s+(.*)$')
    $ordered = [regex]::Match($line, '^\s*\d+\.\s+(.*)$')
    if ($unordered.Success -or $ordered.Success) {
      $nextListType = if ($unordered.Success) { 'ul' } else { 'ol' }
      if ($listType -and $listType -ne $nextListType) {
        $output.Add("</$listType>")
        $listType = ''
      }
      if (-not $listType) {
        $listType = $nextListType
        $output.Add("<$listType>")
      }
      $itemLines = New-Object System.Collections.Generic.List[string]
      $itemText = if ($unordered.Success) { $unordered.Groups[1].Value } else { $ordered.Groups[1].Value }
      $itemLines.Add(($itemText -replace '^\s+', ''))
      $index++
      while ($index -lt $lines.Count -and $lines[$index] -match '^\s{2,}\S' -and $lines[$index] -notmatch '^\s*[-*+]\s+' -and $lines[$index] -notmatch '^\s*\d+\.\s+') {
        $itemLines.Add(($lines[$index] -replace '^\s+', ''))
        $index++
      }
      $output.Add('<li>{0}</li>' -f (Convert-InlineMarkdown ($itemLines -join "`n") $RootPrefix))
      continue
    }

    if ($listType) {
      $output.Add("</$listType>")
      $listType = ''
    }

    $paragraphLines = New-Object System.Collections.Generic.List[string]
    $paragraphLines.Add(($line -replace '^\s+', ''))
    $index++
    while ($index -lt $lines.Count -and $lines[$index].Trim() -and -not (Is-BlockLine $lines[$index])) {
      $paragraphLines.Add(($lines[$index] -replace '^\s+', ''))
      $index++
    }
    $paragraphHtml = Convert-InlineMarkdown ($paragraphLines -join "`n") $RootPrefix
    if ($paragraphHtml -match '^\s*(<figure[\s\S]*?</figure>\s*)+$') {
      $output.Add($paragraphHtml)
    } else {
      $output.Add('<p>{0}</p>' -f $paragraphHtml)
    }
  }

  if ($listType) {
    $output.Add("</$listType>")
  }

  return ($output -join "`n")
}

function Convert-MarkdownToText([string]$Markdown) {
  $text = Normalize-LineEndings $Markdown
  $text = $text -replace '(?s)```.*?```', ' '
  $text = $text -replace '`[^`]*`', ' '
  $text = [regex]::Replace($text, '\[\[(?:File|Image):([^\]|]+)(?:\|([^\]]+))?\]\]', {
    param($match)
    $image = Parse-WikiImage $match.Groups[1].Value $match.Groups[2].Value
    return (' {0} ' -f ((@($image.Alt, $image.Caption, $image.Title) | Where-Object { $_ }) -join ' '))
  }, 'IgnoreCase')
  $text = [regex]::Replace($text, '!\[([^\]]*)\]\(([^)]+)\)(\{[^}]+\})?', {
    param($match)
    $parsed = Parse-MarkdownImageInner $match.Groups[2].Value
    $attrs = Parse-AttrBlock $match.Groups[3].Value
    $parts = @($match.Groups[1].Value)
    foreach ($key in @('alt', 'caption')) {
      if ($attrs.ContainsKey($key)) { $parts += $attrs[$key] }
    }
    if ($parsed.Title) { $parts += $parsed.Title }
    return (' {0} ' -f (($parts | Where-Object { $_ }) -join ' '))
  })
  $text = $text -replace '<br\s*/?>', ' '
  $text = $text -replace '\\\n', ' '
  $text = $text -replace '\[([^\]]+)\]\([^)]+\)', '$1'
  $text = $text -replace '^#{1,6}\s+', ''
  $text = $text -replace '^>\s?', ''
  $text = $text -replace '[*_~`>-]', ' '
  $text = $text -replace '\s+', ' '
  return $text.Trim()
}

function Get-PrimaryImageSource([string]$Markdown) {
  $match = [regex]::Match($Markdown, '!\[[^\]]*\]\(([^)]+)\)')
  if ($match.Success) {
    return (Parse-MarkdownImageInner $match.Groups[1].Value).Src
  }
  $match = [regex]::Match($Markdown, '\[\[(?:File|Image):([^\]|]+)', 'IgnoreCase')
  if ($match.Success) {
    return $match.Groups[1].Value
  }
  return ''
}

function Join-SiteUrl([string]$Base, [string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Base)) { return $Path }
  $siteBase = $Base.TrimEnd('/')
  if (-not $Path) { return $siteBase }
  return ($siteBase + '/' + $Path.TrimStart('/'))
}
function Get-CanonicalUrl([string]$SiteUrl, [string]$WebPath) {
  if ([string]::IsNullOrWhiteSpace($SiteUrl)) { return $WebPath }
  return (Join-SiteUrl $SiteUrl $WebPath)
}

function Get-AbsoluteAssetUrl([string]$SiteUrl, [string]$AssetPath) {
  if ([string]::IsNullOrWhiteSpace($AssetPath)) { return '' }
  if (Is-ExternalUrl $AssetPath) { return $AssetPath }
  return (Join-SiteUrl $SiteUrl $AssetPath)
}

function Render-TagHtml($Tags, [string]$RootPrefix) {
  $tagList = @($Tags)
  if (-not $tagList.Count) { return '' }
  $links = foreach ($tag in $tagList) {
    $key = $tag.ToLowerInvariant()
    $slug = if ($script:TagSlugByKey.ContainsKey($key)) { $script:TagSlugByKey[$key] } else { Slugify $tag }
    '<a class="pill" href="{0}">#{1}</a>' -f (AttrEscape (Apply-RootPrefix ('tag/{0}/' -f $slug) $RootPrefix)), (HtmlEscape $tag)
  }
  return '<div class="tags">{0}</div>' -f ($links -join '')
}

function Render-AuthorHtml([string]$Author, [string]$RootPrefix) {
  $key = $Author.ToLowerInvariant()
  $slug = if ($script:AuthorSlugByKey.ContainsKey($key)) { $script:AuthorSlugByKey[$key] } else { Slugify $Author }
  return '<a href="{0}">{1}</a>' -f (AttrEscape (Apply-RootPrefix ('author/{0}/' -f $slug) $RootPrefix)), (HtmlEscape $Author)
}

function Render-HomeJump([string]$RootPrefix) {
  if ($script:PostsBySlug.ContainsKey('the-journey-begins')) {
    return '<div class="home-jump"><a href="{0}">Jump to first post</a></div>' -f (AttrEscape (Apply-RootPrefix 'post/the-journey-begins/' $RootPrefix))
  }
  return ''
}

function Get-CommentConfig([string]$Kind, $Entry, [string]$Title, $CommentMeta, [string]$SiteUrl) {
  if ($null -eq $CommentMeta -or -not $CommentMeta.Enabled -or [string]::IsNullOrWhiteSpace($script:CommentAppId)) { return $null }
  $pageId = if ($CommentMeta.Id) { $CommentMeta.Id } else { '{0}:{1}' -f $Kind, $Entry.Slug }
  $pageTitle = if ($CommentMeta.Title) { $CommentMeta.Title } else { $Title }
  $fallbackPath = if ($Kind -eq 'post') { 'post/{0}/' -f $Entry.Slug } else { '{0}/' -f $Entry.Slug }
  $customUrlPath = if ($CommentMeta.Url) { Convert-HashRouteToPath $CommentMeta.Url } else { $fallbackPath }
  $pageUrl = Get-CanonicalUrl $SiteUrl $customUrlPath
  $variant = if ($Kind -eq 'page' -and $Entry.Slug -eq 'guestbook') { 'guestbook' } else { 'default' }
  return [pscustomobject]@{
    PageId = $pageId
    PageTitle = $pageTitle
    PageUrl = $pageUrl
    Variant = $variant
  }
}

function Render-CommentBox($CommentConfig) {
  if ($null -eq $CommentConfig) { return '' }
  $classes = 'comments'
  $heading = 'Comments'
  $intro = ''
  if ($CommentConfig.Variant -eq 'guestbook') {
    $classes += ' comments-page'
    $heading = 'Sign the Guestbook'
    if (-not [string]::IsNullOrWhiteSpace($script:GuestbookIntro)) {
      $intro = '<p class="meta">{0}</p>' -f (HtmlEscape $script:GuestbookIntro)
    }
  }
  $moderation = ''
  if (-not [string]::IsNullOrWhiteSpace($script:CommentModerationNote)) {
    $moderation = '<p class="meta">{0}</p>' -f (HtmlEscape $script:CommentModerationNote)
  }
  return '<section class="{0}"><h2>{1}</h2>{2}{3}<div id="cusdis_thread" data-host="{4}" data-app-id="{5}" data-script-src="{6}" data-page-id="{7}" data-page-url="{8}" data-page-title="{9}"></div></section>' -f `
    $classes,
    (HtmlEscape $heading),
    $intro,
    $moderation,
    (AttrEscape $script:CommentHost),
    (AttrEscape $script:CommentAppId),
    (AttrEscape $script:CommentScript),
    (AttrEscape $CommentConfig.PageId),
    (AttrEscape $CommentConfig.PageUrl),
    (AttrEscape $CommentConfig.PageTitle)
}

function Render-PostArticle($Post, [string]$RootPrefix, [bool]$FullPost) {
  $headingTag = if ($FullPost) { 'h1' } else { 'h2' }
  $bodyHtml = Convert-MarkdownToHtml $Post.Body $RootPrefix
  return '<article><{0}>{1}</{0}><div class="meta"><time datetime="{2}">{3}</time> by {4} <a class="permalink" href="{5}" aria-label="Permalink to {6}">Permalink</a></div>{7}<div>{8}</div></article>' -f `
    $headingTag,
    (HtmlEscape $Post.Title),
    (AttrEscape $Post.DateText),
    (HtmlEscape (Format-Date $Post.DateObj)),
    (Render-AuthorHtml $Post.Author $RootPrefix),
    (AttrEscape (Apply-RootPrefix ('post/{0}/' -f $Post.Slug) $RootPrefix)),
    (AttrEscape $Post.Title),
    (Render-TagHtml $Post.Tags $RootPrefix),
    $bodyHtml
}

function Render-Pager([int]$PageNumber, [int]$TotalPages, [string]$RootPrefix) {
  if ($TotalPages -le 1) { return '' }
  $newer = if ($PageNumber -gt 1) {
    $target = if ($PageNumber -eq 2) { Apply-RootPrefix '' $RootPrefix } else { Apply-RootPrefix ('page/{0}/' -f ($PageNumber - 1)) $RootPrefix }
    '<a href="{0}">Newer entries</a>' -f (AttrEscape $target)
  } else {
    '<span></span>'
  }
  $older = if ($PageNumber -lt $TotalPages) {
    '<a href="{0}">Older entries</a>' -f (AttrEscape (Apply-RootPrefix ('page/{0}/' -f ($PageNumber + 1)) $RootPrefix))
  } else {
    '<span></span>'
  }
  return '<nav class="pager" aria-label="Pagination">{0}<span>Page {1} of {2}</span>{3}</nav>' -f $newer, $PageNumber, $TotalPages, $older
}

function Render-Nav([string]$Active, [string]$RootPrefix) {
  $items = @(
    [pscustomobject]@{ Label = 'Home'; Url = (Apply-RootPrefix '' $RootPrefix); Active = ($Active -eq 'home'); Feed = $false },
    [pscustomobject]@{ Label = 'About'; Url = (Apply-RootPrefix 'about/' $RootPrefix); Active = ($Active -eq 'about'); Feed = $false },
    [pscustomobject]@{ Label = 'Guestbook'; Url = (Apply-RootPrefix 'guestbook/' $RootPrefix); Active = ($Active -eq 'guestbook'); Feed = $false },
    [pscustomobject]@{ Label = 'Pages'; Url = (Apply-RootPrefix 'pages/' $RootPrefix); Active = ($Active -eq 'pages'); Feed = $false },
    [pscustomobject]@{ Label = 'Archive'; Url = (Apply-RootPrefix 'archive/' $RootPrefix); Active = ($Active -eq 'archive'); Feed = $false },
    [pscustomobject]@{ Label = 'Tags'; Url = (Apply-RootPrefix 'tags/' $RootPrefix); Active = ($Active -eq 'tags'); Feed = $false },
    [pscustomobject]@{ Label = 'Feed'; Url = (Apply-RootPrefix 'feed.xml' $RootPrefix); Active = $false; Feed = $true }
  )

  $rendered = foreach ($item in $items) {
    $classes = New-Object System.Collections.Generic.List[string]
    if ($item.Active) { $classes.Add('active') }
    if ($item.Feed) { $classes.Add('nav-feed') }
    $classAttr = if ($classes.Count) { ' class="{0}"' -f (($classes -join ' ')) } else { '' }
    $labelHtml = if ($item.Feed) {
      '<img class="inline-icon nav-feed-icon" src="{0}" alt="" aria-hidden="true"><span>{1}</span>' -f (AttrEscape (Apply-RootPrefix 'assets/images/RSS.svg' $RootPrefix)), (HtmlEscape $item.Label)
    } else {
      (HtmlEscape $item.Label)
    }
    '<a href="{0}"{1}>{2}</a>' -f (AttrEscape $item.Url), $classAttr, $labelHtml
  }
  return ($rendered -join '')
}

function Render-Layout([string]$RelativeFilePath, [string]$WebPath, [string]$Title, [string]$Description, [string]$ActiveNav, [string]$BodyHtml, [string]$SearchValue, [string]$ExtraHead, [string]$ExtraScript, [string]$OgType, [string]$OgImage) {
  $rootPrefix = Get-RootPrefix $RelativeFilePath
  $canonical = Get-CanonicalUrl $script:SiteUrl $WebPath
  $pageTitle = if ([string]::IsNullOrWhiteSpace($Title)) { $script:SiteTitle } else { '{0} - {1}' -f $Title, $script:SiteTitle }
  if ($WebPath -eq '') { $pageTitle = $script:SiteTitle }
  $pageDescription = if ([string]::IsNullOrWhiteSpace($Description)) { $script:SiteDescription } else { $Description }
  $ogTypeValue = if ($OgType) { $OgType } else { 'website' }
  $ogImageTag = ''
  if (-not [string]::IsNullOrWhiteSpace($OgImage)) {
    $ogImageTag = '<meta property="og:image" content="{0}"><meta name="twitter:card" content="summary_large_image">' -f (AttrEscape (Get-AbsoluteAssetUrl $script:SiteUrl $OgImage))
  } else {
    $ogImageTag = '<meta name="twitter:card" content="summary">'
  }
  $fullExtraHead = if ($ExtraHead) { "`n$ExtraHead" } else { '' }
  $fullExtraScript = if ($ExtraScript) { "`n$ExtraScript" } else { '' }
  return @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(HtmlEscape $pageTitle)</title>
<meta name="description" content="$(AttrEscape $pageDescription)">
<link rel="canonical" href="$(AttrEscape $canonical)">
<link rel="icon" href="$(AttrEscape (Apply-RootPrefix 'assets/favicons/avatar-minimal.svg' $rootPrefix))" type="image/svg+xml">
<link rel="icon" href="$(AttrEscape (Apply-RootPrefix 'assets/favicons/favicon-32x32.png' $rootPrefix))" sizes="32x32" type="image/png">
<link rel="icon" href="$(AttrEscape (Apply-RootPrefix 'assets/favicons/favicon-16x16.png' $rootPrefix))" sizes="16x16" type="image/png">
<link rel="shortcut icon" href="$(AttrEscape (Apply-RootPrefix 'assets/favicons/favicon.ico' $rootPrefix))">
<link rel="apple-touch-icon" href="$(AttrEscape (Apply-RootPrefix 'assets/favicons/apple-touch-icon.png' $rootPrefix))" sizes="180x180">
<link rel="manifest" href="$(AttrEscape (Apply-RootPrefix 'assets/favicons/site.webmanifest' $rootPrefix))">
<link rel="alternate" type="application/rss+xml" title="$(AttrEscape $script:SiteTitle) RSS Feed" href="$(AttrEscape (Apply-RootPrefix 'feed.xml' $rootPrefix))">
<meta name="theme-color" content="#1f5679">
<meta property="og:site_name" content="$(AttrEscape $script:SiteTitle)">
<meta property="og:title" content="$(AttrEscape $(if ($Title) { $Title } else { $script:SiteTitle }))">
<meta property="og:description" content="$(AttrEscape $pageDescription)">
<meta property="og:type" content="$(AttrEscape $ogTypeValue)">
<meta property="og:url" content="$(AttrEscape $canonical)">$ogImageTag$fullExtraHead
<link rel="stylesheet" href="$(AttrEscape (Apply-RootPrefix 'assets/site.css' $rootPrefix))">
<script defer src="$(AttrEscape (Apply-RootPrefix 'assets/site.js' $rootPrefix))"></script>
</head>
<body>
<div class="wrap">
<header>
  <div class="top">
    <div class="identity">
      <div class="brand">
        <img id="siteLogo" class="inline-icon" src="$(AttrEscape (Apply-RootPrefix 'assets/images/site-logo.svg' $rootPrefix))" alt="$(AttrEscape $script:SiteTitle) logo">
        <h1><a id="homeLink" href="$(AttrEscape (Apply-RootPrefix '' $rootPrefix))">$(HtmlEscape $script:SiteTitle)</a></h1>
      </div>
      <p id="desc">$(HtmlEscape $script:SiteDescription)</p>
    </div>
    <button id="theme" type="button">Theme: Auto</button>
  </div>
  <nav id="nav">$(Render-Nav $ActiveNav $rootPrefix)</nav>
  <div id="pageLinks"></div>
</header>
<div class="search">
  <form id="searchForm" role="search" action="$(AttrEscape (Apply-RootPrefix 'search/' $rootPrefix))" method="get">
    <input id="q" type="search" name="q" placeholder="Search title, tags, author, body" value="$(AttrEscape $SearchValue)">
    <button type="submit">Search</button>
  </form>
</div>
<main id="app" tabindex="-1">
$BodyHtml
</main>
<footer id="foot">All trademarks and copyrighted material belong to their respective owners.</footer>
</div>$fullExtraScript
</body>
</html>
"@
}

function Render-SearchPageScript([string]$RootPrefix) {
  $script = @'
<script>
(() => {
  'use strict';
  const ROOT_PREFIX = '__ROOT__';
  const params = new URLSearchParams(location.search);
  const query = (params.get('q') || '').trim();
  const tag = (params.get('tag') || '').trim();
  const input = document.getElementById('q');
  const resultsRoot = document.getElementById('searchResults');
  const dataNode = document.getElementById('searchIndexData');
  if (input) input.value = query;

  const esc = (value) => String(value).replace(/[&<>"']/g, (m) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
  const tagHtml = (tags) => !tags || !tags.length ? '' : `<div class="tags">${tags.map((t) => `<a class="pill" href="${esc(ROOT_PREFIX)}tag/${encodeURIComponent(String(t).toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, ''))}/index.html">#${esc(t)}</a>`).join('')}</div>`;
  const ere = (value) => String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const parseQuery = (value) => {
    const tokens = [];
    String(value || '').replace(/"([^"]+)"|(\S+)/g, (_, phrase, word) => {
      const raw = String(phrase || word || '').trim();
      if (!raw) return '';
      tokens.push({ raw, value: raw.toLowerCase(), phrase: !!phrase });
      return '';
    });
    return tokens;
  };
  const highlight = (text, terms) => {
    let output = esc(text || '');
    [...new Set(terms.filter(Boolean))].sort((a, b) => b.length - a.length).forEach((term) => {
      output = output.replace(new RegExp(`(${ere(term)})`, 'ig'), '<mark>$1</mark>');
    });
    return output;
  };
  const snippet = (text, terms) => {
    const source = String(text || '');
    if (!source) return '';
    if (!terms.length) return source.length <= 160 ? source : `${source.slice(0, 160).replace(/\s+\S*$/, '').trim()}...`;
    const lower = source.toLowerCase();
    let index = -1;
    terms.forEach((term) => {
      const pos = lower.indexOf(term);
      if (pos !== -1 && (index === -1 || pos < index)) index = pos;
    });
    if (index === -1) return source.length <= 160 ? source : `${source.slice(0, 160).replace(/\s+\S*$/, '').trim()}...`;
    const start = Math.max(0, index - 70);
    const end = Math.min(source.length, index + 100);
    return `${start ? '...' : ''}${source.slice(start, end).trim()}${end < source.length ? '...' : ''}`;
  };
  const search = (items) => {
    const tokens = parseQuery(query);
    const tagFilter = tag.toLowerCase();
    return items.map((item) => {
      if (tagFilter && !String(item.tags || []).join(' ').toLowerCase().includes(tagFilter)) return false;
      if (!tokens.length && !tagFilter) return null;
      let score = 0;
      const matched = tokens.every((token) => {
        const inTitle = item.titleLower.includes(token.value);
        const inTags = item.tagsLower.includes(token.value);
        const inAuthor = item.authorLower.includes(token.value);
        const inBody = item.bodyLower.includes(token.value);
        if (!(inTitle || inTags || inAuthor || inBody)) return false;
        if (token.phrase) {
          score += inTitle ? 12 : 0;
          score += inTags ? 8 : 0;
          score += inAuthor ? 7 : 0;
          score += inBody ? 2 : 0;
        } else {
          score += inTitle ? 6 : 0;
          score += inTags ? 4 : 0;
          score += inAuthor ? 3 : 0;
          score += inBody ? 1 : 0;
        }
        return true;
      });
      if (!matched) return null;
      return { item, score };
    }).filter(Boolean).sort((a, b) => b.score - a.score || b.item.timestamp - a.item.timestamp || a.item.title.localeCompare(b.item.title));
  };

  if (!query && !tag) {
    resultsRoot.innerHTML = '<p>Use the search box to filter posts by title, tags, author, or body text. Wrap text in double quotes to search for an exact phrase.</p>';
    return;
  }

  let items = [];
  try {
    items = JSON.parse(dataNode ? (dataNode.textContent || '[]') : '[]');
  } catch (error) {
    resultsRoot.innerHTML = `<p class="box err">${esc(error.message)}</p>`;
    return;
  }

  const results = search(items);
  const terms = parseQuery(query).map((token) => token.value);
  const headingBits = [];
  if (query) headingBits.push(`query "${esc(query)}"`);
  if (tag) headingBits.push(`tag "${esc(tag)}"`);
  const intro = headingBits.length ? `<p>${headingBits.join(' and ')}</p>` : '';
  if (!results.length) {
    resultsRoot.innerHTML = `${intro}<p>No matches found.</p>`;
    return;
  }
  resultsRoot.innerHTML = intro + results.map(({ item }) => `<article><h2><a href="${esc(item.url)}">${highlight(item.title, terms)}</a></h2><div class="meta">${esc(item.kind === 'post' ? 'Post' : 'Page')}${item.kind === 'post' && item.author ? ` by ${esc(item.author)}` : ''}</div>${item.body ? `<p>${highlight(snippet(item.body, terms), terms)}</p>` : ''}${tagHtml(item.tags || [])}</article>`).join('');
})();
</script>
'@
  return $script.Replace('__ROOT__', $RootPrefix)
}
function Write-GeneratedPage([string]$RelativeFilePath, [string]$WebPath, [string]$Title, [string]$Description, [string]$ActiveNav, [string]$BodyHtml, [string]$SearchValue, [string]$ExtraHead, [string]$ExtraScript, [string]$OgType, [string]$OgImage, [Nullable[datetime]]$LastModified) {
  $html = Render-Layout $RelativeFilePath $WebPath $Title $Description $ActiveNav $BodyHtml $SearchValue $ExtraHead $ExtraScript $OgType $OgImage
  Write-Utf8File (Join-Path $OutputDir ($RelativeFilePath -replace '/', '\')) $html
  if ($null -ne $script:SitemapEntries) {
    $script:SitemapEntries.Add([pscustomobject]@{ Path = $WebPath; LastModified = $LastModified })
  }
}

$indexPath = Join-Path $BlogRoot 'index.html'
$postsManifestPath = Join-Path $BlogRoot 'posts\posts.json'
$pagesManifestPath = Join-Path $BlogRoot 'pages\pages.json'
$assetsPath = Join-Path $BlogRoot 'assets'
$siteRootPath = Join-Path $BlogRoot 'site-root'

if (-not (Test-Path $indexPath)) { throw "index.html not found at $indexPath" }
if (-not (Test-Path $postsManifestPath)) { throw "posts/posts.json not found at $postsManifestPath" }
if (-not (Test-Path $pagesManifestPath)) { throw "pages/pages.json not found at $pagesManifestPath" }

$indexSource = Get-Content -Path $indexPath -Raw -Encoding UTF8
$script:SiteTitle = Get-ConfigString $indexSource 'siteTitle' "Aang's MTG Journey"
$script:SiteDescription = Get-ConfigString $indexSource 'siteDescription' ''
$script:SiteUrl = (Get-ConfigString $indexSource 'siteUrl' '').TrimEnd('/')
$script:PerPage = Get-ConfigNumber $indexSource 'perPage' 10
$script:ExcerptLength = Get-ConfigNumber $indexSource 'excerptLen' 220
$script:RssItems = Get-ConfigNumber $indexSource 'rssItems' 25
$script:CommentHost = Get-ConfigString $indexSource 'commentHost' 'https://cusdis.com'
$script:CommentAppId = Get-ConfigString $indexSource 'commentAppId' ''
$script:CommentScript = Get-ConfigString $indexSource 'commentScript' 'https://cusdis.com/js/cusdis.es.js'
$script:CommentNote = Get-ConfigString $indexSource 'commentNote' ''
$script:CommentModerationNote = Get-ConfigString $indexSource 'commentModerationNote' ''
$script:GuestbookIntro = Get-ConfigString $indexSource 'guestbookIntro' ''
$styleBlock = Get-StyleBlock $indexSource

$markerPath = Join-Path $OutputDir '.portable-blog-generated'
if (Test-Path $OutputDir) {
  if (-not (Test-Path $markerPath)) {
    throw "Refusing to clear $OutputDir because it does not contain the generator marker. Move or remove that folder first."
  }
  Get-ChildItem -Path $OutputDir -Force | Remove-Item -Recurse -Force
}
Ensure-Directory $OutputDir
Write-Utf8File $markerPath ("Generated by build-site.ps1 on {0}`n" -f [DateTime]::UtcNow.ToString('u'))
Write-Utf8File (Join-Path $OutputDir '.nojekyll') ''
Copy-Item -Path $assetsPath -Destination (Join-Path $OutputDir 'assets') -Recurse -Force
if (Test-Path $siteRootPath) {
  Get-ChildItem -Path $siteRootPath -Force | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination (Join-Path $OutputDir $_.Name) -Recurse -Force
  }
}
Write-Utf8File (Join-Path $OutputDir 'assets\site.css') $styleBlock

$siteScript = @'
(() => {
  'use strict';
  const button = document.getElementById('theme');
  const prefersDark = () => window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  const nextTheme = (value) => value === 'light' ? 'dark' : value === 'dark' ? 'auto' : 'light';
  const applyTheme = (value) => {
    const pref = ['light', 'dark', 'auto'].includes(value) ? value : 'auto';
    localStorage.setItem('portable-blog-theme', pref);
    const effective = pref === 'auto' ? (prefersDark() ? 'dark' : 'light') : pref;
    document.documentElement.setAttribute('data-theme', effective);
    if (button) {
      button.textContent = `Theme: ${pref.charAt(0).toUpperCase()}${pref.slice(1)}`;
      button.dataset.next = nextTheme(pref);
    }
  };
  document.addEventListener('DOMContentLoaded', () => {
    applyTheme(localStorage.getItem('portable-blog-theme') || 'auto');
    if (button) {
      button.addEventListener('click', () => applyTheme(button.dataset.next || 'auto'));
    }
    if (window.matchMedia) {
      window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
        if ((localStorage.getItem('portable-blog-theme') || 'auto') === 'auto') {
          applyTheme('auto');
        }
      });
    }
    const root = document.getElementById('cusdis_thread');
    if (!root) return;
    const mount = () => {
      if (window.CUSDIS && typeof window.CUSDIS.initial === 'function') {
        root.innerHTML = '';
        window.CUSDIS.initial();
      }
    };
    const existing = document.querySelector('script[data-cusdis-script="1"]');
    if (existing) {
      if (existing.dataset.loaded === '1') {
        mount();
        return;
      }
      existing.addEventListener('load', mount, { once: true });
      return;
    }
    const script = document.createElement('script');
    script.async = true;
    script.defer = true;
    script.src = root.dataset.scriptSrc;
    script.dataset.cusdisScript = '1';
    script.addEventListener('load', () => {
      script.dataset.loaded = '1';
      mount();
    }, { once: true });
    root.closest('.comments')?.insertAdjacentHTML('beforeend', '');
    document.body.appendChild(script);
  });
})();
'@
Write-Utf8File (Join-Path $OutputDir 'assets\site.js') $siteScript

$postManifest = Get-Content -Path $postsManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pageManifest = Get-Content -Path $pagesManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not ($postManifest -is [System.Collections.IEnumerable])) { throw 'posts/posts.json must be an array.' }
if (-not ($pageManifest -is [System.Collections.IEnumerable])) { throw 'pages/pages.json must be an array.' }

$posts = New-Object System.Collections.Generic.List[object]
$pages = New-Object System.Collections.Generic.List[object]
$seenPostSlugs = @{}
$seenPageSlugs = @{}

foreach ($entry in $postManifest) {
  $slug = Slugify ([string]$entry.slug)
  $file = [string]$entry.file
  $dateText = [string]$entry.date
  $dateObj = Parse-Date $dateText
  if (-not $slug -or -not $file -or $null -eq $dateObj) { continue }
  if ($seenPostSlugs.ContainsKey($slug)) { continue }
  $seenPostSlugs[$slug] = $true
  $raw = Get-Content -Path (Join-Path $BlogRoot (Join-Path 'posts' $file)) -Raw -Encoding UTF8
  $frontMatter = Parse-FrontMatter $raw
  $body = $frontMatter.Body
  $text = Convert-MarkdownToText $body
  $excerpt = if ($entry.PSObject.Properties.Name -contains 'excerpt' -and -not [string]::IsNullOrWhiteSpace([string]$entry.excerpt)) { [string]$entry.excerpt } else { Get-Excerpt $text $script:ExcerptLength }
  $comments = Parse-CommentMeta $frontMatter.Meta
  $posts.Add([pscustomobject]@{
    Slug = $slug
    File = $file
    Title = [string]$entry.title
    DateText = $dateText
    DateObj = $dateObj
    Year = $dateObj.ToString('yyyy')
    Month = $dateObj.ToString('MM')
    Tags = Normalize-Tags $entry.tags
    Author = if ([string]::IsNullOrWhiteSpace([string]$entry.author)) { 'Legoless' } else { [string]$entry.author }
    Excerpt = $excerpt
    Body = $body
    Text = $text
    Comments = $comments
    PrimaryImage = Get-PrimaryImageSource $body
  })
}

foreach ($entry in $pageManifest) {
  $slug = Slugify ([string]$entry.slug)
  $file = [string]$entry.file
  if (-not $slug -or -not $file) { continue }
  if ($seenPageSlugs.ContainsKey($slug)) { continue }
  $seenPageSlugs[$slug] = $true
  $raw = Get-Content -Path (Join-Path $BlogRoot (Join-Path 'pages' $file)) -Raw -Encoding UTF8
  $frontMatter = Parse-FrontMatter $raw
  $body = $frontMatter.Body
  $text = Convert-MarkdownToText $body
  $pages.Add([pscustomobject]@{
    Slug = $slug
    File = $file
    Title = [string]$entry.title
    Body = $body
    Text = $text
    Excerpt = Get-Excerpt $text $script:ExcerptLength
    Comments = Parse-CommentMeta $frontMatter.Meta
    PrimaryImage = Get-PrimaryImageSource $body
  })
  $script:PagePathBySlug[$slug] = ('{0}/' -f $slug)
}

$posts = @($posts | Sort-Object @{ Expression = { $_.DateObj }; Descending = $true }, @{ Expression = { $_.Slug }; Descending = $false })
$pages = @($pages | Sort-Object Title)
$script:PostsBySlug = @{}
foreach ($post in $posts) { $script:PostsBySlug[$post.Slug] = $post }

$archives = @{}
$tagsByKey = @{}
$authorsByKey = @{}
foreach ($post in $posts) {
  if (-not $archives.ContainsKey($post.Year)) {
    $archives[$post.Year] = [pscustomobject]@{ Year = $post.Year; Posts = New-Object System.Collections.Generic.List[object]; Months = @{} }
  }
  $archives[$post.Year].Posts.Add($post)
  if (-not $archives[$post.Year].Months.ContainsKey($post.Month)) {
    $archives[$post.Year].Months[$post.Month] = New-Object System.Collections.Generic.List[object]
  }
  $archives[$post.Year].Months[$post.Month].Add($post)

  foreach ($tag in $post.Tags) {
    $key = $tag.ToLowerInvariant()
    if (-not $tagsByKey.ContainsKey($key)) {
      $tagsByKey[$key] = [pscustomobject]@{ Key = $key; Label = $tag; Posts = New-Object System.Collections.Generic.List[object] }
    }
    $tagsByKey[$key].Posts.Add($post)
  }

  $authorKey = $post.Author.ToLowerInvariant()
  if (-not $authorsByKey.ContainsKey($authorKey)) {
    $authorsByKey[$authorKey] = [pscustomobject]@{ Key = $authorKey; Label = $post.Author; Posts = New-Object System.Collections.Generic.List[object] }
  }
  $authorsByKey[$authorKey].Posts.Add($post)
}

$usedTagSlugs = @{}
foreach ($tagEntry in @($tagsByKey.Values | Sort-Object Label)) {
  $baseSlug = Slugify $tagEntry.Label
  if (-not $baseSlug) { $baseSlug = 'tag' }
  $slug = $baseSlug
  $counter = 2
  while ($usedTagSlugs.ContainsKey($slug)) {
    $slug = '{0}-{1}' -f $baseSlug, $counter
    $counter++
  }
  $usedTagSlugs[$slug] = $true
  Add-Member -InputObject $tagEntry -NotePropertyName Slug -NotePropertyValue $slug -Force
  $script:TagSlugByKey[$tagEntry.Key] = $slug
}

$usedAuthorSlugs = @{}
foreach ($authorEntry in @($authorsByKey.Values | Sort-Object Label)) {
  $baseSlug = Slugify $authorEntry.Label
  if (-not $baseSlug) { $baseSlug = 'author' }
  $slug = $baseSlug
  $counter = 2
  while ($usedAuthorSlugs.ContainsKey($slug)) {
    $slug = '{0}-{1}' -f $baseSlug, $counter
    $counter++
  }
  $usedAuthorSlugs[$slug] = $true
  Add-Member -InputObject $authorEntry -NotePropertyName Slug -NotePropertyValue $slug -Force
  $script:AuthorSlugByKey[$authorEntry.Key] = $slug
}

$script:SitemapEntries = New-Object System.Collections.Generic.List[object]
$defaultOgImage = 'assets/favicons/android-chrome-512x512.png'

$totalPages = [Math]::Max(1, [Math]::Ceiling($posts.Count / [double]$script:PerPage))
for ($pageNumber = 1; $pageNumber -le $totalPages; $pageNumber++) {
  $sliceStart = ($pageNumber - 1) * $script:PerPage
  $slice = @($posts | Select-Object -Skip $sliceStart -First $script:PerPage)
  $articles = foreach ($post in $slice) { Render-PostArticle $post (Get-RootPrefix $(if ($pageNumber -eq 1) { 'index.html' } else { 'page/{0}/index.html' -f $pageNumber })) $false }
  $body = "<section>$(Render-HomeJump (Get-RootPrefix $(if ($pageNumber -eq 1) { 'index.html' } else { 'page/{0}/index.html' -f $pageNumber })))$($articles -join '')$(Render-Pager $pageNumber $totalPages (Get-RootPrefix $(if ($pageNumber -eq 1) { 'index.html' } else { 'page/{0}/index.html' -f $pageNumber })))</section>"
  $relativeFile = if ($pageNumber -eq 1) { 'index.html' } else { 'page/{0}/index.html' -f $pageNumber }
  $webPath = if ($pageNumber -eq 1) { '' } else { 'page/{0}/' -f $pageNumber }
  $pageTitle = if ($pageNumber -eq 1) { '' } else { 'Page {0}' -f $pageNumber }
  $lastModified = if ($slice.Count) { [Nullable[datetime]]$slice[0].DateObj } else { $null }
  Write-GeneratedPage $relativeFile $webPath $pageTitle $script:SiteDescription 'home' $body '' '' '' 'website' $defaultOgImage $lastModified
}

for ($index = 0; $index -lt $posts.Count; $index++) {
  $post = $posts[$index]
  $older = if ($index -lt ($posts.Count - 1)) { $posts[$index + 1] } else { $null }
  $newer = if ($index -gt 0) { $posts[$index - 1] } else { $null }
  $commentConfig = Get-CommentConfig 'post' $post $post.Title $post.Comments $script:SiteUrl
  $commentHtml = ''
  if ($null -ne $commentConfig) {
    $commentHtml = Render-CommentBox $commentConfig
  } elseif ($script:CommentNote) {
    $commentHtml = '<p class="meta">{0}</p>' -f (HtmlEscape $script:CommentNote)
  }
  $adjacent = '<nav class="adj" aria-label="Adjacent posts">{0}{1}</nav>' -f `
    $(if ($older) { '<a href="{0}"><small>Older post</small>{1}</a>' -f (AttrEscape (Apply-RootPrefix ('post/{0}/' -f $older.Slug) '../../')), (HtmlEscape $older.Title) } else { '<div class="none"><small>Older post</small>None</div>' }),
    $(if ($newer) { '<a href="{0}"><small>Newer post</small>{1}</a>' -f (AttrEscape (Apply-RootPrefix ('post/{0}/' -f $newer.Slug) '../../')), (HtmlEscape $newer.Title) } else { '<div class="none"><small>Newer post</small>None</div>' })
  $body = (Render-PostArticle $post '../../' $true) + $adjacent + $commentHtml
  $extraHead = '<meta property="article:published_time" content="{0}">' -f $post.DateObj.ToString('yyyy-MM-dd')
  Write-GeneratedPage ('post/{0}/index.html' -f $post.Slug) ('post/{0}/' -f $post.Slug) $post.Title $post.Excerpt '' $body '' $extraHead '' 'article' $(if ($post.PrimaryImage) { $post.PrimaryImage.TrimStart('/') } else { $defaultOgImage }) ([Nullable[datetime]]$post.DateObj)
}

foreach ($page in $pages) {
  $commentConfig = Get-CommentConfig 'page' $page $page.Title $page.Comments $script:SiteUrl
  $jump = if ($page.Slug -eq 'about') { Render-HomeJump '../' } else { '' }
  if ($commentConfig -and $commentConfig.Variant -eq 'guestbook') {
    $body = '<section class="guestbook-page"><article><h1>{0}</h1><div>{1}</div>{2}</article>{3}</section>' -f (HtmlEscape $page.Title), (Convert-MarkdownToHtml $page.Body '../'), $jump, (Render-CommentBox $commentConfig)
  } else {
    $body = '<article><h1>{0}</h1><div>{1}</div>{2}</article>{3}' -f (HtmlEscape $page.Title), (Convert-MarkdownToHtml $page.Body '../'), $jump, (Render-CommentBox $commentConfig)
  }
  $active = if ($page.Slug -eq 'about') { 'about' } elseif ($page.Slug -eq 'guestbook') { 'guestbook' } else { 'pages' }
  Write-GeneratedPage ('{0}/index.html' -f $page.Slug) ('{0}/' -f $page.Slug) $page.Title $page.Excerpt $active $body '' '' '' 'website' $(if ($page.PrimaryImage) { $page.PrimaryImage.TrimStart('/') } else { $defaultOgImage }) $null
}

$pagesList = if ($pages.Count) {
  '<ul class="list">{0}</ul>' -f ((@($pages | ForEach-Object { '<li><a href="{0}">{1}</a></li>' -f (AttrEscape (Apply-RootPrefix ('{0}/' -f $_.Slug) '../')), (HtmlEscape $_.Title) }) -join ''))
} else {
  '<p>No static pages listed.</p>'
}
Write-GeneratedPage 'pages/index.html' 'pages/' 'Pages' 'Standalone pages on the site.' 'pages' ("<section><h1>Pages</h1>$pagesList</section>") '' '' '' 'website' $defaultOgImage $null

$archiveYears = @($archives.Keys | Sort-Object -Descending)
$archiveSections = foreach ($year in $archiveYears) {
  $yearNode = $archives[$year]
  $monthLinks = @($yearNode.Months.Keys | Sort-Object -Descending | ForEach-Object { '<li><a href="{0}">{1}</a> ({2})</li>' -f (AttrEscape (Apply-RootPrefix ('archive/{0}/{1}/' -f $year, $_) '../')), (HtmlEscape (Format-Month $_)), $yearNode.Months[$_].Count })
  '<section><h2><a href="{0}">{1}</a> ({2})</h2><ul>{3}</ul></section>' -f (AttrEscape (Apply-RootPrefix ('archive/{0}/' -f $year) '../')), $year, $yearNode.Posts.Count, ($monthLinks -join '')
}
Write-GeneratedPage 'archive/index.html' 'archive/' 'Archive' 'Browse the archive by year and month.' 'archive' ("<section><h1>Archive</h1>$($archiveSections -join '')</section>") '' '' '' 'website' $defaultOgImage $(if ($posts.Count) { [Nullable[datetime]]$posts[0].DateObj } else { $null })

foreach ($year in $archiveYears) {
  $yearNode = $archives[$year]
  $months = @($yearNode.Months.Keys | Sort-Object -Descending)
  $sections = foreach ($month in $months) {
    $listItems = @($yearNode.Months[$month] | ForEach-Object { '<li><a href="{0}">{1}</a> <time class="meta" datetime="{2}">{3}</time></li>' -f (AttrEscape (Apply-RootPrefix ('post/{0}/' -f $_.Slug) '../../')), (HtmlEscape $_.Title), (AttrEscape $_.DateText), (HtmlEscape (Format-Date $_.DateObj)) })
    '<section><h3><a href="{0}">{1}</a></h3><ul class="list">{2}</ul></section>' -f (AttrEscape (Apply-RootPrefix ('archive/{0}/{1}/' -f $year, $month) '../../')), (HtmlEscape (Format-Month $month)), ($listItems -join '')
  }
  Write-GeneratedPage ('archive/{0}/index.html' -f $year) ('archive/{0}/' -f $year) ('Archive: {0}' -f $year) ('Posts from {0}.' -f $year) 'archive' ("<section><h1>Archive: $year</h1>$($sections -join '')</section>") '' '' '' 'website' $defaultOgImage ([Nullable[datetime]]$yearNode.Posts[0].DateObj)
  foreach ($month in $months) {
    $postLinks = @($yearNode.Months[$month] | ForEach-Object { '<li><a href="{0}">{1}</a> <time class="meta" datetime="{2}">{3}</time></li>' -f (AttrEscape (Apply-RootPrefix ('post/{0}/' -f $_.Slug) '../../../')), (HtmlEscape $_.Title), (AttrEscape $_.DateText), (HtmlEscape (Format-Date $_.DateObj)) })
    Write-GeneratedPage ('archive/{0}/{1}/index.html' -f $year, $month) ('archive/{0}/{1}/' -f $year, $month) ('Archive: {0} {1}' -f (Format-Month $month), $year) ('Posts from {0} {1}.' -f (Format-Month $month), $year) 'archive' ("<section><h1>Archive: $(Format-Month $month) $year</h1><ul class='list'>$($postLinks -join '')</ul></section>") '' '' '' 'website' $defaultOgImage ([Nullable[datetime]]$yearNode.Months[$month][0].DateObj)
  }
}

$tagItems = @($tagsByKey.Values | Sort-Object Label)
$tagsIndexList = if ($tagItems.Count) {
  '<ul class="list">{0}</ul>' -f ((@($tagItems | ForEach-Object { '<li><a href="{0}">#{1}</a> ({2})</li>' -f (AttrEscape (Apply-RootPrefix ('tag/{0}/' -f $_.Slug) '../')), (HtmlEscape $_.Label), $_.Posts.Count }) -join ''))
} else { '<p>No tags found.</p>' }
Write-GeneratedPage 'tags/index.html' 'tags/' 'Tags' 'Browse posts by tag.' 'tags' ("<section><h1>Tags</h1>$tagsIndexList</section>") '' '' '' 'website' $defaultOgImage $(if ($posts.Count) { [Nullable[datetime]]$posts[0].DateObj } else { $null })

foreach ($tagEntry in $tagItems) {
  $postList = @($tagEntry.Posts | ForEach-Object { '<li><a href="{0}">{1}</a> <time class="meta" datetime="{2}">{3}</time></li>' -f (AttrEscape (Apply-RootPrefix ('post/{0}/' -f $_.Slug) '../../')), (HtmlEscape $_.Title), (AttrEscape $_.DateText), (HtmlEscape (Format-Date $_.DateObj)) })
  Write-GeneratedPage ('tag/{0}/index.html' -f $tagEntry.Slug) ('tag/{0}/' -f $tagEntry.Slug) ('Tag: #{0}' -f $tagEntry.Label) ('Posts tagged {0}.' -f $tagEntry.Label) 'tags' ("<section><h1>Tag: #$(HtmlEscape $tagEntry.Label)</h1><ul class='list'>$($postList -join '')</ul></section>") '' '' '' 'website' $defaultOgImage ([Nullable[datetime]]$tagEntry.Posts[0].DateObj)
}

$authorItems = @($authorsByKey.Values | Sort-Object Label)
$authorsIndexList = if ($authorItems.Count) {
  '<ul class="list">{0}</ul>' -f ((@($authorItems | ForEach-Object { '<li><a href="{0}">{1}</a> ({2})</li>' -f (AttrEscape (Apply-RootPrefix ('author/{0}/' -f $_.Slug) '../')), (HtmlEscape $_.Label), $_.Posts.Count }) -join ''))
} else { '<p>No authors found.</p>' }
Write-GeneratedPage 'authors/index.html' 'authors/' 'Authors' 'Browse posts by author.' '' ("<section><h1>Authors</h1>$authorsIndexList</section>") '' '' '' 'website' $defaultOgImage $(if ($posts.Count) { [Nullable[datetime]]$posts[0].DateObj } else { $null })

foreach ($authorEntry in $authorItems) {
  $postList = @($authorEntry.Posts | ForEach-Object { '<li><a href="{0}">{1}</a> <time class="meta" datetime="{2}">{3}</time></li>' -f (AttrEscape (Apply-RootPrefix ('post/{0}/' -f $_.Slug) '../../')), (HtmlEscape $_.Title), (AttrEscape $_.DateText), (HtmlEscape (Format-Date $_.DateObj)) })
  Write-GeneratedPage ('author/{0}/index.html' -f $authorEntry.Slug) ('author/{0}/' -f $authorEntry.Slug) ('Author: {0}' -f $authorEntry.Label) ('Posts by {0}.' -f $authorEntry.Label) '' ("<section><h1>Author: $(HtmlEscape $authorEntry.Label)</h1><ul class='list'>$($postList -join '')</ul></section>") '' '' '' 'website' $defaultOgImage ([Nullable[datetime]]$authorEntry.Posts[0].DateObj)
}

$searchIndex = New-Object System.Collections.Generic.List[object]
foreach ($post in $posts) {
  $searchIndex.Add([ordered]@{
    kind = 'post'
    title = $post.Title
    titleLower = $post.Title.ToLowerInvariant()
    url = ('../post/{0}/index.html' -f $post.Slug)
    date = $post.DateText
    timestamp = [int64]([DateTimeOffset]$post.DateObj).ToUnixTimeSeconds()
    tags = @($post.Tags)
    tagsLower = (($post.Tags | ForEach-Object { $_.ToLowerInvariant() }) -join ' ')
    author = $post.Author
    authorLower = $post.Author.ToLowerInvariant()
    body = $post.Text
    bodyLower = $post.Text.ToLowerInvariant()
    excerpt = $post.Excerpt
  })
}
foreach ($page in $pages) {
  $searchIndex.Add([ordered]@{
    kind = 'page'
    title = $page.Title
    titleLower = $page.Title.ToLowerInvariant()
    url = ('../{0}/index.html' -f $page.Slug)
    date = ''
    timestamp = 0
    tags = @()
    tagsLower = ''
    author = ''
    authorLower = ''
    body = $page.Text
    bodyLower = $page.Text.ToLowerInvariant()
    excerpt = $page.Excerpt
  })
}
$searchIndexJson = (($searchIndex | ConvertTo-Json -Depth 6) + "`n")
$searchIndexJsonForHtml = $searchIndexJson.Replace('</', '<\/')

$searchBody = @"
<section>
  <h1>Search</h1>
  <noscript><p class="box warn">Search requires JavaScript in the browser.</p></noscript>
  <div id="searchResults"><p>Use the search box to filter posts by title, tags, author, or body text. Wrap text in double quotes to search for an exact phrase.</p></div>
  <script id="searchIndexData" type="application/json">
$searchIndexJsonForHtml  </script>
</section>
"@
Write-GeneratedPage 'search/index.html' 'search/' 'Search' 'Search the site.' '' $searchBody '' '<meta name="robots" content="noindex,follow">' (Render-SearchPageScript '../') 'website' $defaultOgImage $(if ($posts.Count) { [Nullable[datetime]]$posts[0].DateObj } else { $null })

Write-Utf8File (Join-Path $OutputDir 'search-index.json') $searchIndexJson

$rssPosts = @($posts | Select-Object -First $script:RssItems)
$rssItems = foreach ($post in $rssPosts) {
  $link = Get-CanonicalUrl $script:SiteUrl ('post/{0}/' -f $post.Slug)
  $guid = if ($script:SiteUrl) { '{0}#post:{1}' -f (Get-CanonicalUrl $script:SiteUrl ''), $post.Slug } else { 'post:{0}' -f $post.Slug }
  '<item><title>{0}</title><link>{1}</link><guid isPermaLink="false">{2}</guid><pubDate>{3}</pubDate><description>{4}</description></item>' -f `
    (XmlEscape $post.Title),
    (XmlEscape $link),
    (XmlEscape $guid),
    (XmlEscape $post.DateObj.ToUniversalTime().ToString('r')),
    (XmlEscape $post.Excerpt)
}
$feedXml = @(
  '<?xml version="1.0" encoding="UTF-8"?>',
  '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">',
  '<channel>',
  ('<title>{0}</title>' -f (XmlEscape $script:SiteTitle)),
  ('<link>{0}</link>' -f (XmlEscape (Get-CanonicalUrl $script:SiteUrl ''))),
  ('<atom:link href="{0}" rel="self" type="application/rss+xml" />' -f (XmlEscape (Get-CanonicalUrl $script:SiteUrl 'feed.xml'))),
  ('<description>{0}</description>' -f (XmlEscape $script:SiteDescription)),
  ('<lastBuildDate>{0}</lastBuildDate>' -f (XmlEscape ([DateTime]::UtcNow.ToString('r')))),
  ($rssItems -join ''),
  '</channel>',
  '</rss>'
) -join ''
Write-Utf8File (Join-Path $OutputDir 'feed.xml') $feedXml
Write-Utf8File (Join-Path $BlogRoot 'feed.xml') $feedXml

$sitemapEntries = @($script:SitemapEntries | Where-Object { $_.Path -ne 'search/' })
$sitemapXml = @('<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
foreach ($entry in $sitemapEntries) {
  $loc = Get-CanonicalUrl $script:SiteUrl $entry.Path
  $xml = '<url><loc>{0}</loc>' -f (XmlEscape $loc)
  if ($entry.LastModified) {
    $xml += '<lastmod>{0}</lastmod>' -f (XmlEscape ([datetime]$entry.LastModified).ToString('yyyy-MM-dd'))
  }
  $xml += '</url>'
  $sitemapXml += $xml
}
$sitemapXml += '</urlset>'
Write-Utf8File (Join-Path $OutputDir 'sitemap.xml') ($sitemapXml -join '')

$robots = @('User-agent: *', 'Allow: /')
if ($script:SiteUrl) {
  $robots += ('Sitemap: {0}' -f (Join-SiteUrl $script:SiteUrl 'sitemap.xml'))
}
Write-Utf8File (Join-Path $OutputDir 'robots.txt') (($robots -join "`n") + "`n")

Write-Host "Built static site into $OutputDir"
Write-Host 'Switch GitHub Pages to publish from /docs on the main branch once you are ready.'
