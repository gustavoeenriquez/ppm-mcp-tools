program mcp_excel;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.Excel in 'MCPTool.Excel.pas';

var
  MCPServer: TAiMCPServer;
  Protocol : string;
  Port     : Integer;
  i        : Integer;

begin
  Protocol := 'stdio';
  Port     := 8595;

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

    MCPServer.ServerName         := 'mcp-excel';
    MCPServer.Port               := Port;
    MCPServer.CorsEnabled        := True;
    MCPServer.CorsAllowedOrigins := '*';

    MCPTool.Excel.RegisterTools(MCPServer);
    MCPServer.Start;

    if MCPServer is TAiMCPSSEHttpServer then
      WriteLn(ErrOutput, Format('[mcp-excel] SSE  → http://localhost:%d/sse', [Port]))
    else if MCPServer is TAiMCPHttpServer then
      WriteLn(ErrOutput, Format('[mcp-excel] HTTP → http://localhost:%d/mcp', [Port]))
    else
      WriteLn(ErrOutput, '[mcp-excel] Stdio — waiting for JSON-RPC on stdin.');

    while True do
      Sleep(1000);

  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, '[mcp-excel] Fatal: ' + E.Message);
      Halt(1);
    end;
  end;

end.
