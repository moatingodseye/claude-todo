@echo off
REM The escape hatch. Removes the todo hooks from Claude Code's settings.
REM
REM Run this from an ORDINARY command prompt, with Claude Code CLOSED, FROM THE FOLDER OF THE PROJECT
REM you want unhooked:
REM
REM     cd C:\your\project
REM     D:\tool\unhook.cmd
REM
REM It needs nothing but Windows PowerShell - no Claude Code, no todo.exe, no toolchain. That is the
REM point: if the hooks have made a session unusable, the way out must not depend on any of them.
REM
REM It removes only the individual hook entries that run todo.exe or the viewer. Hooks of your own in
REM the same sections are left exactly as they are.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0unhook.ps1"
exit /b %errorlevel%
