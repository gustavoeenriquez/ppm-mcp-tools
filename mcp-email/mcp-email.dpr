program mcp_email;

// mcp-email: correo completo en un solo server MCP — lectura/gestión IMAP
// (MCPTool.IMAP) + envío SMTP (MCPTool.SMTP). Pensado como CONECTOR de
// MakerCLI: las credenciales llegan por variables de entorno MAIL_*
// (inyectadas por el gateway desde el panel /conectores) y el LLM nunca
// necesita conocerlas. Los paquetes mcp-imap / mcp-smtp independientes
// siguen existiendo; este los combina para ofrecer UNA configuración.

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.IMAP in '..\mcp-imap\MCPTool.IMAP.pas',
  MCPTool.SMTP in '..\mcp-smtp\MCPTool.SMTP.pas';

var
  MCPServer: TAiMCPServer;
  Protocol:  string;
  Port:      Integer;
  i:         Integer;

begin
  Protocol := 'stdio';
  Port     := 8651;

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

    MCPServer.ServerName         := 'mcp-email';
    MCPServer.ServerVersion      := '1.1.1';
    MCPServer.Port               := Port;
    MCPServer.CorsEnabled        := True;
    MCPServer.CorsAllowedOrigins := '*';

    MCPTool.IMAP.RegisterTools(MCPServer);
    MCPTool.SMTP.RegisterTools(MCPServer);
    MCPServer.Start;

    if MCPServer is TAiMCPSSEHttpServer then
      WriteLn(ErrOutput, Format('[mcp-email] SSE  -> http://localhost:%d/sse', [Port]))
    else if MCPServer is TAiMCPHttpServer then
      WriteLn(ErrOutput, Format('[mcp-email] HTTP -> http://localhost:%d/mcp', [Port]))
    else
      WriteLn(ErrOutput, '[mcp-email] Stdio -- waiting for JSON-RPC on stdin.');

    while True do
      Sleep(1000);

  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, '[mcp-email] Fatal: ' + E.Message);
      Halt(1);
    end;
  end;

end.
