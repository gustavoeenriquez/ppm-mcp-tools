program mcp_homeassistant;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.Credential in '..\_shared\MCPTool.Credential.pas',
  MCPTool.HomeAssistant in 'MCPTool.HomeAssistant.pas';

var
  MCPServer: TAiMCPServer;
  Protocol: string;
  Port: Integer;
  i: Integer;

begin
  Protocol := 'stdio';
  Port     := 8861;

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

    MCPServer.ServerName       := 'mcp-homeassistant';
    MCPServer.ServerVersion    := '1.0.0';
    MCPServer.Port             := Port;
    MCPServer.CorsEnabled      := True;
    MCPServer.CorsAllowedOrigins := '*';

    MCPTool.HomeAssistant.RegisterTools(MCPServer);
    // En red (servidor) la cuenta llega por cabecera en cada peticion
    // (MCPTool.Credential, campos HASS_URL y HASS_TOKEN); en stdio, de las
    // variables de entorno del mismo nombre.
    if not SameText(Protocol, 'stdio') then
      MCPTool.Credential.UseHeaderCredential(MCPServer);
    MCPServer.Start;

    if MCPServer is TAiMCPSSEHttpServer then
      WriteLn(ErrOutput, Format('[mcp-homeassistant] SSE  -> http://localhost:%d/sse', [Port]))
    else if MCPServer is TAiMCPHttpServer then
      WriteLn(ErrOutput, Format('[mcp-homeassistant] HTTP -> http://localhost:%d/mcp', [Port]))
    else
      WriteLn(ErrOutput, '[mcp-homeassistant] Stdio - waiting for JSON-RPC on stdin.');

    while True do
      Sleep(1000);

  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, '[mcp-homeassistant] Fatal: ' + E.Message);
      Halt(1);
    end;
  end;

end.
