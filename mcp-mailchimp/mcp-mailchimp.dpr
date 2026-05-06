program mcp_mailchimp;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.Mailchimp in 'MCPTool.Mailchimp.pas';

var
  MCPServer: TAiMCPServer;
  Protocol: string;
  Port: Integer;
  i: Integer;

begin
  Protocol := 'stdio';
  Port     := 8735;
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
    MCPServer.ServerName := 'mcp-mailchimp';
    MCPServer.Port := Port;
    MCPServer.CorsEnabled := True;
    MCPServer.CorsAllowedOrigins := '*';
    MCPTool.Mailchimp.RegisterTools(MCPServer);
    MCPServer.Start;
    WriteLn(ErrOutput, '[mcp-mailchimp] ready.');
    while True do Sleep(1000);
  except
    on E: Exception do begin WriteLn(ErrOutput, '[mcp-mailchimp] Fatal: ' + E.Message); Halt(1); end;
  end;
end.