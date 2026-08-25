@echo off
REM Removes the todo queue hooks from Claude's settings, and nothing else.
REM
REM Run this from the PROJECT folder, from an ORDINARY command prompt, with Claude Code closed. It
REM needs nothing but Windows PowerShell - no Claude, no Dart, and none of our binaries. That is the
REM point: if the hooks have made a session unusable, the way out must not depend on any of them.
REM
REM It scrubs both scopes, whichever exist:
REM     this project   <the folder you run it from>\.claude\settings.json
REM     global         %USERPROFILE%\.claude\settings.json
REM
REM It removes only the individual hook ENTRIES that run our binaries. Hooks of your own in the same
REM events are left exactly where they are.
REM
REM This is the wrapper shipped IN THE DOWNLOAD, where everything sits in one flat folder beside
REM install.cmd. The source repo has `unhookasbroken.cmd` at its root instead, because there the repo
REM root is the project and the script lives under `tool\`. One scrubber, two wrappers.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0unhook.ps1"
exit /b %errorlevel%
