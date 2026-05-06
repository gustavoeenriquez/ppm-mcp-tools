program mcp_diffeditor;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.Editor in 'MCPTool.Editor.pas';
var MCPServer: TAiMCPServer; Protocol: string; Port: Integer; i: Integer;
begin
  Protocol := 'stdio'; Port := 8769; i := 1;
  while i <= ParamCount do begin
    if SameText(ParamStr(i),'--protocol') and (i<ParamCount) then begin Inc(i); Protocol:=LowerCase(ParamStr(i)); end
    else if SameText(ParamStr(i),'--port') and (i<ParamCount) then begin Inc(i); Port:=StrToIntDef(ParamStr(i),Port); end;
    Inc(i);
  end;
  try
    if SameText(Protocol,'sse') then MCPServer:=TAiMCPSSEHttpServer.Create(nil)
    else if SameText(Protocol,'http') then MCPServer:=TAiMCPHttpServer.Create(nil)
    else MCPServer:=TAiMCPStdioServer.Create(nil);
    MCPServer.ServerName:='mcp-diffeditor'; MCPServer.Port:=Port;
    MCPServer.CorsEnabled:=True; MCPServer.CorsAllowedOrigins:='*';
    MCPTool.Editor.RegisterTools(MCPServer);
    MCPServer.Start;
    WriteLn(ErrOutput,'[mcp-diffeditor] ready.');
    while True do Sleep(1000);
  except on E: Exception do begin WriteLn(ErrOutput,'[mcp-diffeditor] Fatal: '+E.Message); Halt(1); end; end;
end.
