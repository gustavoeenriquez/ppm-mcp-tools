program mcp_ini;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.Ini in 'MCPTool.Ini.pas';

var
  MCPServer: TAiMCPServer;
  Protocol: string;
  Port: Integer;
  i: Integer;

begin
  Protocol := 'stdio';
  Port     := 8597;

  i := 1;
  while i <= ParamCount do
  begin
    if SameText(ParamStr(i), '--protocol') and (i < ParamCount) then
    begin
      Inc(i);
      Protocol := LowerCase(ParamStr(i));
    end
    else if SameText(ParamStr(i), '--port') and (i < ParamCount) then
    begin
      Inc(i);
      Port := StrToIntDef(ParamStr(i), Port);
    end;
    Inc(i);
  end;

  try
    if SameText(Protocol, 'sse') then
      MCPServer := TAiMCPSSEHttpServer.Create(nil)
    else if SameText(Protocol, 'http') then
      MCPServer := TAiMCPHttpServer.Create(nil)
    else
      MCPServer := TAiMCPStdioServer.Create(nil);

    MCPServer.ServerName       := 'mcp-Ini';
    MCPServer.Port             := Port;
    MCPServer.CorsEnabled      := True;
    MCPServer.CorsAllowedOrigins := '*';

    MCPTool.Ini.RegisterTools(MCPServer);
    MCPServer.Start;

    if MCPServer is TAiMCPSSEHttpServer then
      WriteLn(ErrOutput, Format('[mcp-Ini] SSE  -> http://localhost:%d/sse', [Port]))
    else if MCPServer is TAiMCPHttpServer then
      WriteLn(ErrOutput, Format('[mcp-Ini] HTTP -> http://localhost:%d/mcp', [Port]))
    else
      WriteLn(ErrOutput, '[mcp-Ini] Stdio -- waiting for JSON-RPC on stdin.');

    while True do
      Sleep(1000);

  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, '[mcp-Ini] Fatal: ' + E.Message);
      Halt(1);
    end;
  end;

end.
