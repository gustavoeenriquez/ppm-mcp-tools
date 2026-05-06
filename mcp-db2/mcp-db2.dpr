program mcp_db2;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.FDBase in 'MCPTool.FDBase.pas',
  MCPTool.DB2 in 'MCPTool.DB2.pas';

var
  MCPServer: TAiMCPServer;
  Protocol: string;
  Port: Integer;
  i: Integer;

begin
  Protocol := 'stdio';
  Port     := 8753;
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
    MCPServer.ServerName := 'mcp-db2';
    MCPServer.Port := Port;
    MCPServer.CorsEnabled := True;
    MCPServer.CorsAllowedOrigins := '*';
    MCPTool.DB2.RegisterTools(MCPServer);
    MCPServer.Start;
    WriteLn(ErrOutput, '[mcp-db2] ready.');
    while True do Sleep(1000);
  except
    on E: Exception do begin WriteLn(ErrOutput, '[mcp-db2] Fatal: ' + E.Message); Halt(1); end;
  end;
end.
