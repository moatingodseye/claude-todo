@echo off
REM Installs todo from a downloaded release, and wires this project's hooks.
REM
REM Run this from an ORDINARY command prompt, in the project you want the queue in. It needs nothing
REM but Windows PowerShell - no Claude, no Dart, no toolchain of any kind.
REM
REM ONE QUESTION: which folder the tool goes into. The binaries, `configuration.json`, the queue
REM registry and the two runtime state files all live there, and the four hook entries are generated
REM from that same answer. Nothing is put on PATH.
REM
REM The suggestion offered is the folder you unzipped into, because the tool is portable - everything
REM it writes sits beside the exe. There is no default install location: where the binaries belong is
REM your decision, not this script's.
REM
REM   install.cmd                      ask, and wire the project you are standing in
REM   install.cmd -To C:\todo          no question; wire the project you are standing in
REM   install.cmd -To C:\todo -NoHooks binaries only, wire nothing
REM   install.cmd -To C:\todo -Global  wire %USERPROFILE%\.claude instead, so EVERY project is queued
REM
REM The two scopes ADD UP: a project wired both ways runs all four hooks twice. After going global,
REM run `unhook.cmd -Scope project` in each project you had wired individually.
REM
REM This wrapper sits beside install.ps1 in the download, so %~dp0 is the tool folder. To undo the
REM hooks afterwards: unhook.cmd, from the project folder.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
exit /b %errorlevel%
