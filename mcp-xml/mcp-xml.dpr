program mcp_xml;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.XML in 'MCPTool.XML.pas';

var
  MCPServer: TAiMCPServer;
  Protocol : string;
  Port     : Integer;
  i        : Integer;

begin
  Protocol := 'stdio';
  Port     := 8593;

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

    MCPServer.ServerName         := 'mcp-xml';
    MCPServer.Port               := Port;
    MCPServer.CorsEnabled        := True;
    MCPServer.CorsAllowedOrigins := '*';

    MCPTool.XML.RegisterTools(MCPServer);
    MCPServer.Start;

    if MCPServer is TAiMCPSSEHttpServer then
      WriteLn(ErrOutput, Format('[mcp-xml] SSE  → http://localhost:%d/sse', [Port]))
    else if MCPServer is TAiMCPHttpServer then
      WriteLn(ErrOutput, Format('[mcp-xml] HTTP → http://localhost:%d/mcp', [Port]))
    else
      WriteLn(ErrOutput, '[mcp-xml] Stdio — waiting for JSON-RPC on stdin.');

    while True do
      Sleep(1000);

  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, '[mcp-xml] Fatal: ' + E.Message);
      Halt(1);
    end;
  end;

end.
