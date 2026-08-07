@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild "E:\Copilot\spas\ppm-mcp-tools\mcp-conta\mcp-conta.dproj" /t:Build /p:Config=Release /p:Platform=Win64 /v:minimal
echo BUILD_CONTA_WIN64=%ERRORLEVEL%
msbuild "E:\Copilot\spas\ppm-mcp-tools\mcp-conta-query\mcp-conta-query.dproj" /t:Build /p:Config=Release /p:Platform=Win64 /v:minimal
echo BUILD_QUERY_WIN64=%ERRORLEVEL%
msbuild "E:\Copilot\spas\ppm-mcp-tools\mcp-conta\mcp-conta.dproj" /t:Build /p:Config=Release /p:Platform=Linux64 /v:minimal
echo BUILD_CONTA_LINUX64=%ERRORLEVEL%
msbuild "E:\Copilot\spas\ppm-mcp-tools\mcp-conta-query\mcp-conta-query.dproj" /t:Build /p:Config=Release /p:Platform=Linux64 /v:minimal
echo BUILD_QUERY_LINUX64=%ERRORLEVEL%
