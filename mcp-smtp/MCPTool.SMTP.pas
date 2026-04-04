unit MCPTool.SMTP;

{
  MCPTool.SMTP  ·  mcp-smtp

  Send email via SMTP using Indy TIdSMTP + TaurusTLS.
  Pattern based on uMailSender.pas (contabilidad server — working reference).
  Supports STARTTLS (port 587, utUseExplicitTLS) and implicit SSL (port 465).
  Handles plain text, HTML body, CC/BCC and file attachments.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  IdSMTP,
  IdMessage,
  IdText,
  IdAttachmentFile,
  TaurusTLS,
  IdExplicitTLSClientServerBase;

type

  TSMTPParams = class
  private
    FHost:        string;
    FPort:        Integer;
    FSSL:         string;
    FUsername:    string;
    FPassword:    string;
    FFrom:        string;
    FFromName:    string;
    FRecipients:  string;
    FCC:          string;
    FBCC:         string;
    FSubject:     string;
    FBody:        string;
    FHtmlBody:    string;
    FAttachments: string;
  public
    [AiMCPSchemaDescription('SMTP server hostname (e.g. smtp.zoho.com, smtp.gmail.com)')]
    property Host:        string  read FHost        write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SMTP port (default: 587)')]
    property Port:        Integer read FPort        write FPort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SSL mode: starttls (default, port 587), ssl (port 465), none')]
    property SSL:         string  read FSSL         write FSSL;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SMTP username (usually the email address)')]
    property Username:    string  read FUsername    write FUsername;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SMTP password or app password')]
    property Password:    string  read FPassword    write FPassword;

    [AiMCPSchemaDescription('Sender email address')]
    property From:        string  read FFrom        write FFrom;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Sender display name')]
    property FromName:    string  read FFromName    write FFromName;

    [AiMCPSchemaDescription('Recipient email address(es), comma-separated')]
    property Recipients:  string  read FRecipients  write FRecipients;

    [AiMCPOptional]
    [AiMCPSchemaDescription('CC address(es), comma-separated')]
    property CC:          string  read FCC          write FCC;

    [AiMCPOptional]
    [AiMCPSchemaDescription('BCC address(es), comma-separated')]
    property BCC:         string  read FBCC         write FBCC;

    [AiMCPSchemaDescription('Email subject line')]
    property Subject:     string  read FSubject     write FSubject;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Plain text body')]
    property Body:        string  read FBody        write FBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('HTML body. Send both body and html_body for best compatibility.')]
    property HtmlBody:    string  read FHtmlBody    write FHtmlBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('File paths to attach, comma-separated')]
    property Attachments: string  read FAttachments write FAttachments;
  end;

  TSMTPTool = class(TAiMCPToolBase<TSMTPParams>)
  protected
    function ExecuteWithParams(const AParams: TSMTPParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

function TSMTPTool.ExecuteWithParams(const AParams: TSMTPParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  SMTP: TIdSMTP;
  Msg:  TIdMessage;
  SSL:  TTaurusTLSIOHandlerSocket;
begin
  try
    if AParams.Host       = '' then raise Exception.Create('"host" is required');
    if AParams.From       = '' then raise Exception.Create('"from" is required');
    if AParams.Recipients = '' then raise Exception.Create('"recipients" is required');
    if AParams.Subject    = '' then raise Exception.Create('"subject" is required');
    if (AParams.Body = '') and (AParams.HtmlBody = '') then
      raise Exception.Create('"body" or "html_body" is required');

    SMTP := TIdSMTP.Create(nil);
    Msg  := TIdMessage.Create(nil);
    SSL  := TTaurusTLSIOHandlerSocket.Create(nil);
    try
      // TaurusTLS — mismo patrón que uMailSender.pas (contabilidad)
      SSL.SSLOptions.Mode := sslmClient;
      SMTP.IOHandler := SSL;

      SMTP.Host     := AParams.Host;
      SMTP.Port     := AParams.Port;
      if SMTP.Port = 0 then SMTP.Port := 587;
      SMTP.Username := AParams.Username;
      SMTP.Password := AParams.Password;

      var SSLMode := LowerCase(Trim(AParams.SSL));
      if SSLMode = '' then SSLMode := 'starttls';

      if SSLMode = 'ssl' then
        SMTP.UseTLS := utUseImplicitTLS
      else if SSLMode = 'none' then
        SMTP.UseTLS := utNoTLSSupport
      else
        SMTP.UseTLS := utUseExplicitTLS;  // starttls — igual que contabilidad

      // Addressing
      Msg.From.Address := AParams.From;
      if AParams.FromName <> '' then Msg.From.Name := AParams.FromName;
      Msg.Recipients.EMailAddresses := AParams.Recipients;
      if AParams.CC  <> '' then Msg.CCList.EMailAddresses  := AParams.CC;
      if AParams.BCC <> '' then Msg.BCCList.EMailAddresses := AParams.BCC;
      Msg.Subject := AParams.Subject;

      var HasHtml   := AParams.HtmlBody    <> '';
      var HasPlain  := AParams.Body        <> '';
      var HasAttach := AParams.Attachments <> '';

      if (not HasHtml) and (not HasAttach) then
      begin
        Msg.Body.Text := AParams.Body;
      end
      else
      begin
        if HasAttach then
          Msg.ContentType := 'multipart/mixed'
        else
          Msg.ContentType := 'multipart/alternative';

        if HasPlain then
        begin
          var P := TIdText.Create(Msg.MessageParts, nil);
          P.ContentType := 'text/plain; charset=UTF-8';
          P.Body.Text   := AParams.Body;
        end;

        if HasHtml then
        begin
          var H := TIdText.Create(Msg.MessageParts, nil);
          H.ContentType := 'text/html; charset=UTF-8';
          H.Body.Text   := AParams.HtmlBody;
        end;

        if HasAttach then
        begin
          var FilePaths := AParams.Attachments.Split([',']);
          for var F in FilePaths do
          begin
            var FPath := Trim(F);
            if FPath <> '' then
              TIdAttachmentFile.Create(Msg.MessageParts, FPath);
          end;
        end;
      end;

      // Connect + Send — sin Authenticate separado (mismo patrón que contabilidad)
      SMTP.Connect;
      try
        SMTP.Send(Msg);
      finally
        SMTP.Disconnect;
      end;

      var R := TJSONObject.Create;
      R.AddPair('ok',         TJSONBool.Create(True));
      R.AddPair('from',       AParams.From);
      R.AddPair('recipients', AParams.Recipients);
      R.AddPair('subject',    AParams.Subject);
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    finally
      Msg.Free;
      SMTP.Free;
      SSL.Free;
    end;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-smtp]: ' + E.Message)
        .Build;
  end;
end;

constructor TSMTPTool.Create;
begin
  inherited;
  FName        := 'mcp-smtp';
  FDescription :=
    'Sends an email via SMTP. ' +
    'REQUIRED params: host, username, password, from, recipients, subject, and body (or html_body). ' +
    'Always set: port=587, ssl="starttls". ' +
    'Example for Zoho: host="smtp.zoho.com" port=587 ssl="starttls" username="user@zoho.com" password="pass" from="user@zoho.com" recipients="dest@example.com" subject="Hello" body="Hi there". ' +
    'Example for Gmail: host="smtp.gmail.com" port=587 ssl="starttls" username="user@gmail.com" password="app-password" from="user@gmail.com" recipients="dest@example.com" subject="Hello" body="Hi". ' +
    'Optional: from_name, cc, bcc, html_body, attachments (comma-separated file paths). ' +
    'Returns: {"ok":true,"from":"...","recipients":"...","subject":"..."}.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-smtp',
    function: IAiMCPTool
    begin
      Result := TSMTPTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-smtp');
end;

end.
