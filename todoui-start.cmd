@echo off
REM Launches the viewer for the SessionStart hook WITHOUT blocking Claude Code.
REM
REM Point the SessionStart hook at this file, not at todoui.exe. Claude Code waits for a
REM SessionStart hook to exit AND for its stdout to reach EOF before the session becomes
REM usable. todoui.exe does neither when it is the first copy to start: it takes the
REM single-instance lock and then runs, as a window should. Wiring the hook straight to it
REM therefore hangs Claude Code outright on the first start after a reboot - no output, no
REM error, and /exit does not work either. From the second start onward the lock is already
REM held, todoui.exe exits at once, and nothing looks wrong; that is why this only bites
REM from cold.
REM
REM `start` is NOT a sufficient fix, and it fails in the worst possible way: the viewer
REM window appears, so it looks like it worked, but the child inherits the stdout pipe, so
REM stdout never reaches EOF and the session still hangs (measured: rc=124 after 15s).
REM Process exit is not enough - the pipe has to close too. Start-Process hands the viewer
REM its own handles, so the launcher exits AND the pipe closes.
REM
REM Measured from cold with no viewer running: rc=0 in 479ms, stdout closed, viewer up.
REM
REM Keep this file in the same folder as todoui.exe - %~dp0 is this file's own folder.

if not exist "%~dp0todoui.exe" (
    echo todoui-start.cmd: todoui.exe not found in "%~dp0" - put this file beside it. 1>&2
    exit /b 0
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~dp0todoui.exe'"
exit /b 0
