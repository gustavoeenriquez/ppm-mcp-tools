program mcp_pdf;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.PDF in 'MCPTool.PDF.pas';

var
  MCPServer: TAiMCPServer;
  Protocol : string;
  Port     : Integer;
  i        : Integer;

begin
  Protocol := 'stdio';
  Port     := 8590;

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

    MCPServer.ServerName         := 'mcp-pdf';
    MCPServer.Port               := Port;
    MCPServer.CorsEnabled        := True;
    MCPServer.CorsAllowedOrigins := '*';

    MCPTool.PDF.RegisterTools(MCPServer);
    MCPServer.Start;

    if MCPServer is TAiMCPSSEHttpServer then
      WriteLn(ErrOutput, Format('[mcp-pdf] SSE  → http://localhost:%d/sse', [Port]))
    else if MCPServer is TAiMCPHttpServer then
      WriteLn(ErrOutput, Format('[mcp-pdf] HTTP → http://localhost:%d/mcp', [Port]))
    else
      WriteLn(ErrOutput, '[mcp-pdf] Stdio — waiting for JSON-RPC on stdin.');

    while True do
      Sleep(1000);

  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, '[mcp-pdf] Fatal: ' + E.Message);
      Halt(1);
    end;
  end;

end.
