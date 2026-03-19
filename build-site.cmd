@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-site.ps1"
if errorlevel 1 (
  echo.
  echo Static site build failed.
  pause
  exit /b %errorlevel%
)
echo docs, feed.xml, and sitemap.xml rebuilt.
