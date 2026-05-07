@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
msbuild "E:\copilot\spas\ppm-mcp-tools\mcp-openmeteo\mcp-openmeteo.dproj" /t:Build /p:Config=Release /p:Platform=Linux64 /v:minimal
echo BUILD_EXIT_CODE=%ERRORLEVEL%
