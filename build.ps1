# Builds the GitHub Pages copy in docs/ from index.html.
# index.html is written as page content only (the claude.ai artifact adds the document skeleton),
# so for Pages we wrap it in the same skeleton: doctype, charset, viewport and a small reset.
$root = $PSScriptRoot
$docs = Join-Path $root 'docs'
New-Item -ItemType Directory -Force (Join-Path $docs 'moon') | Out-Null

$head = '<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><style>:root{color-scheme:light;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui,sans-serif}img{max-width:100%}[hidden]{display:none!important}</style></head><body>'
$page = [IO.File]::ReadAllText((Join-Path $root 'index.html'), [Text.Encoding]::UTF8)
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $docs 'index.html'), $head + "`n" + $page + "`n</body></html>`n", $utf8)

Copy-Item -LiteralPath (Join-Path $root 'moon\lroc_color_1k.jpg') -Destination (Join-Path $docs 'moon') -Force
Copy-Item -LiteralPath (Join-Path $root 'moon\ldem_1k.jpg') -Destination (Join-Path $docs 'moon') -Force
# serve files as-is (no Jekyll processing)
[IO.File]::WriteAllText((Join-Path $docs '.nojekyll'), '', $utf8)
Write-Output "docs/ built"
