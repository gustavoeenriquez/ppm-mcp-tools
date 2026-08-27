program mcp_conta;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMakerAi.MCPServer.Core,
  UMakerAi.MCPServer.Stdio,
  UMakerAi.MCPServer.Http,
  UMakerAi.MCPServer.SSE,
  MCPTool.ContaClient in '..\_shared\MCPTool.ContaClient.pas',
  MCPTool.Conta.Catalog in 'MCPTool.Conta.Catalog.pas',
  MCPTool.Conta in 'MCPTool.Conta.pas';

var
  MCPServer: TAiMCPServer;
  Protocol: string;
  Port: Integer;
  i: Integer;

begin
  Protocol := 'stdio';
  Port     := 8780;

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

    MCPServer.ServerName         := 'mcp-conta';
    MCPServer.ServerVersion := '1.0.2';
    MCPServer.Port               := Port;
    MCPServer.CorsEnabled        := True;
    MCPServer.CorsAllowedOrigins := '*';

    MCPTool.Conta.RegisterTools(MCPServer, { AReadOnly } False);

    // En red, la credencial la pone el llamante en el header y este proceso
    // solo la reenvia. En stdio se usan las CONTA_* del entorno.
    if not SameText(Protocol, 'stdio') then
      MCPTool.Conta.UsarCredencialDelHeader(MCPServer);

    MCPServer.Start;

    if MCPServer is TAiMCPSSEHttpServer then
      WriteLn(ErrOutput, Format('[mcp-conta] SSE  -> http://localhost:%d/sse', [Port]))
    else if MCPServer is TAiMCPHttpServer then
      WriteLn(ErrOutput, Format('[mcp-conta] HTTP -> http://localhost:%d/mcp', [Port]))
    else
      WriteLn(ErrOutput, '[mcp-conta] Stdio -- waiting for JSON-RPC on stdin.');

    while True do
      Sleep(1000);

  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, '[mcp-conta] Fatal: ' + E.Message);
      Halt(1);
    end;
  end;

end.
