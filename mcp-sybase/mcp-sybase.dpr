program mcp_sybase;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.FDBase in 'MCPTool.FDBase.pas',
  MCPTool.Sybase in 'MCPTool.Sybase.pas';

var
  MCPServer: TAiMCPServer;
  Protocol: string;
  Port: Integer;
  i: Integer;

begin
  Protocol := 'stdio';
  Port     := 8754;
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
    MCPServer.ServerName := 'mcp-sybase';
    MCPServer.Port := Port;
    MCPServer.CorsEnabled := True;
    MCPServer.CorsAllowedOrigins := '*';
    MCPTool.Sybase.RegisterTools(MCPServer);
    MCPServer.Start;
    WriteLn(ErrOutput, '[mcp-sybase] ready.');
    while True do Sleep(1000);
  except
    on E: Exception do begin WriteLn(ErrOutput, '[mcp-sybase] Fatal: ' + E.Message); Halt(1); end;
  end;
end.
