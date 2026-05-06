program mcp_azure_blob;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.AzureBlob in 'MCPTool.AzureBlob.pas';

var
  MCPServer: TAiMCPServer;
  Protocol: string;
  Port: Integer;
  i: Integer;

begin
  Protocol := 'stdio';
  Port     := 8724;
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
    MCPServer.ServerName := 'mcp-azure-blob';
    MCPServer.Port := Port;
    MCPServer.CorsEnabled := True;
    MCPServer.CorsAllowedOrigins := '*';
    MCPTool.AzureBlob.RegisterTools(MCPServer);
    MCPServer.Start;
    WriteLn(ErrOutput, '[mcp-azure-blob] ready.');
    while True do Sleep(1000);
  except
    on E: Exception do begin WriteLn(ErrOutput, '[mcp-azure-blob] Fatal: ' + E.Message); Halt(1); end;
  end;
end.