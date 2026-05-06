program mcp_zendesk;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.Zendesk in 'MCPTool.Zendesk.pas';

var
  MCPServer: TAiMCPServer;
  Protocol: string;
  Port: Integer;
  i: Integer;

begin
  Protocol := 'stdio';
  Port     := 8731;
  i := 1;
  while i <= ParamCount do
  begin
    if SameText(ParamStr(i), '--protocol') and (i < ParamCount) then begin Inc(i); Protocol := LowerCase(ParamStr(i)); end
    else if SameText(ParamStr(i), '--port') and (i < ParamCount) then begin Inc(i); Port := StrToIntDef(ParamStr(i), Port); end;
    Inc(i);
  end;
  try
    if SameText(Protocol, 'sse') then MCPServer := TAiMCPSSEHttpServer.Create(nil)
    else if SameText(Protocol, 'http') then MCPServer := TAiMCPHttpServer.Create(nil)
    else MCPServer := TAiMCPStdioServer.Create(nil);
    MCPServer.ServerName := 'mcp-zendesk';
    MCPServer.Port := Port;
    MCPServer.CorsEnabled := True;
    MCPServer.CorsAllowedOrigins := '*';
    MCPTool.Zendesk.RegisterTools(MCPServer);
    MCPServer.Start;
    WriteLn(ErrOutput, '[mcp-zendesk] ready.');
    while True do Sleep(1000);
  except
    on E: Exception do begin WriteLn(ErrOutput, '[mcp-zendesk] Fatal: ' + E.Message); Halt(1); end;
  end;
end.