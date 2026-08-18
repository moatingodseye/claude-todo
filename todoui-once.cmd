@echo off
REM Start the queue viewer, unless it is already running.
REM
REM Use THIS from the SessionStart hook rather than todoui.exe directly. SessionStart fires on
REM startup, resume, clear and compact alike, so pointing the hook straight at the exe would open a
REM new window every time - four windows into one afternoon.
REM
REM `start ""` returns immediately, so session start is never held up waiting for a GUI to draw.
tasklist /FI "IMAGENAME eq todoui.exe" 2>nul | find /I "todoui.exe" >nul
if errorlevel 1 start "" "%~dp0todoui.exe"
exit /b 0
