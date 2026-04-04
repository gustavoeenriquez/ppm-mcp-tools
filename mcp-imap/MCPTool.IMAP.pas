// Nombre: Gustavo Enríquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit MCPTool.IMAP;

{
  MCPTool.IMAP  ·  mcp-imap

  Read and manage email via IMAP4 using Indy TIdIMAP4.
  Uses UID-based operations for stable message references.

  Operations:
    folders  - list all mailboxes/folders
    list     - list messages in a folder (headers, most recent first)
    get      - retrieve full message by UID
    search   - search by from/subject criteria
    move     - copy message to dest_folder then delete from source
    delete   - mark deleted and expunge
    mark     - read / unread / flagged / unflagged

  Gmail:   host=imap.gmail.com   port=993  ssl=ssl  + App Password
  Outlook: host=outlook.office365.com  port=993  ssl=ssl
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.StrUtils,
  IdIMAP4,
  IdMailBox,
  IdMessage,
  IdText,
  TaurusTLS,  // reemplaza IdSSLOpenSSL — soporta OpenSSL 1.1.x y 3.x
  IdExplicitTLSClientServerBase;

type

  TIMAPParams = class
  private
    FHost:       string;
    FPort:       Integer;
    FSSL:        string;
    FUsername:   string;
    FPassword:   string;
    FOperation:  string;
    FFolder:     string;
    FUID:        string;
    FFilter:     string;
    FFromStr:    string;
    FSubjectStr: string;
    FLimit:      Integer;
    FDestFolder: string;
    FMarkAs:     string;
  public
    [AiMCPSchemaDescription('IMAP server hostname (e.g. imap.gmail.com, outlook.office365.com)')]
    property Host:       string  read FHost       write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('IMAP port (default: 993)')]
    property Port:       Integer read FPort       write FPort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SSL mode: ssl (default, port 993), starttls (port 143), none')]
    property SSL:        string  read FSSL        write FSSL;

    [AiMCPSchemaDescription('IMAP username (usually the email address)')]
    property Username:   string  read FUsername   write FUsername;

    [AiMCPSchemaDescription('IMAP password or app password')]
    property Password:   string  read FPassword   write FPassword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Operation: folders (default), list, get, search, move, delete, mark')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Folder/mailbox name (default: INBOX)')]
    property Folder:     string  read FFolder     write FFolder;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Message UID string — required for get, move, delete, mark')]
    property UID:        string  read FUID        write FUID;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Filter for list: all (default), unseen, seen, flagged')]
    property Filter:     string  read FFilter     write FFilter;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search in FROM header (for list and search operations)')]
    property FromStr:    string  read FFromStr    write FFromStr;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search in SUBJECT header (for list and search operations)')]
    property SubjectStr: string  read FSubjectStr write FSubjectStr;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max messages to return for list/search (default: 20)')]
    property Limit:      Integer read FLimit      write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Destination folder for move operation')]
    property DestFolder: string  read FDestFolder write FDestFolder;

    [AiMCPOptional]
    [AiMCPSchemaDescription('For mark operation: read, unread, flagged, unflagged')]
    property MarkAs:     string  read FMarkAs     write FMarkAs;
  end;

  TIMAPTool = class(TAiMCPToolBase<TIMAPParams>)
  private
    procedure SetupIMAP(const AParams: TIMAPParams;
      AIMAP: TIdIMAP4; ASSL: TTaurusTLSIOHandlerSocket);
    function BuildSearchRec(const AParams: TIMAPParams): TArray<TIdIMAP4SearchRec>;
    function HeaderToJSON(const AMsg: TIdMessage; const AUID: string): TJSONObject;
    function MessageToJSON(const AMsg: TIdMessage; const AUID: string): TJSONObject;
    function FetchHeaders(AIMAP: TIdIMAP4;
      const AUIDs: TUInt32Array; ALimit: Integer): TJSONArray;
  protected
    function ExecuteWithParams(const AParams: TIMAPParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

procedure TIMAPTool.SetupIMAP(const AParams: TIMAPParams;
  AIMAP: TIdIMAP4; ASSL: TTaurusTLSIOHandlerSocket);
begin
  ASSL.SSLOptions.Mode := sslmClient;  // TaurusTLS auto-negocia TLS 1.2/1.3
  AIMAP.IOHandler := ASSL;
  AIMAP.Host     := AParams.Host;
  AIMAP.Port     := AParams.Port;
  if AIMAP.Port  = 0 then AIMAP.Port := 993;
  AIMAP.Username := AParams.Username;
  AIMAP.Password := AParams.Password;

  // Force plain LOGIN — skips SASL/AUTHENTICATE negotiation that Zoho
  // and some other servers reject with [CLIENTBUG] invalid state errors.
  AIMAP.AuthType := iatUserPass;

  var SSLMode := LowerCase(Trim(AParams.SSL));
  if SSLMode = '' then SSLMode := 'ssl';
  if      SSLMode = 'starttls' then AIMAP.UseTLS := utUseExplicitTLS
  else if SSLMode = 'none'     then AIMAP.UseTLS := utNoTLSSupport
  else                              AIMAP.UseTLS := utUseImplicitTLS;
end;

function TIMAPTool.BuildSearchRec(
  const AParams: TIMAPParams): TArray<TIdIMAP4SearchRec>;
var
  SRs: TArray<TIdIMAP4SearchRec>;
  Idx: Integer;
begin
  SetLength(SRs, 0);
  Idx := 0;

  // Base filter
  SetLength(SRs, Length(SRs) + 1);
  var FilterStr := LowerCase(Trim(AParams.Filter));
  if FilterStr = '' then FilterStr := 'all';
  if      FilterStr = 'unseen'  then SRs[Idx].SearchKey := skUnseen
  else if FilterStr = 'seen'    then SRs[Idx].SearchKey := skSeen
  else if FilterStr = 'flagged' then SRs[Idx].SearchKey := skFlagged
  else                               SRs[Idx].SearchKey := skAll;
  Inc(Idx);

  if AParams.FromStr <> '' then
  begin
    SetLength(SRs, Length(SRs) + 1);
    SRs[Idx].SearchKey := skFrom;
    SRs[Idx].Text      := AParams.FromStr;
    Inc(Idx);
  end;

  if AParams.SubjectStr <> '' then
  begin
    SetLength(SRs, Length(SRs) + 1);
    SRs[Idx].SearchKey := skSubject;
    SRs[Idx].Text      := AParams.SubjectStr;
  end;

  Result := SRs;
end;

function TIMAPTool.HeaderToJSON(const AMsg: TIdMessage;
  const AUID: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uid',       AUID);
  Result.AddPair('from',      AMsg.From.Address);
  Result.AddPair('from_name', AMsg.From.Name);
  Result.AddPair('subject',   AMsg.Subject);
  Result.AddPair('date',      DateTimeToStr(AMsg.Date));
end;

function TIMAPTool.MessageToJSON(const AMsg: TIdMessage;
  const AUID: string): TJSONObject;
var
  Body:     string;
  HtmlBody: string;
begin
  Result := HeaderToJSON(AMsg, AUID);
  Result.AddPair('to', AMsg.Recipients.EMailAddresses);

  if AMsg.MessageParts.Count > 0 then
  begin
    for var i := 0 to AMsg.MessageParts.Count - 1 do
    begin
      var Part := AMsg.MessageParts.Items[i];
      if Part is TIdText then
      begin
        var TP := TIdText(Part);
        if ContainsText(TP.ContentType, 'text/plain') and (Body = '') then
          Body := TP.Body.Text
        else if ContainsText(TP.ContentType, 'text/html') and (HtmlBody = '') then
          HtmlBody := TP.Body.Text;
      end;
    end;
  end
  else
    Body := AMsg.Body.Text;

  Result.AddPair('body',      Body);
  Result.AddPair('html_body', HtmlBody);
end;

function TIMAPTool.FetchHeaders(AIMAP: TIdIMAP4;
  const AUIDs: TUInt32Array; ALimit: Integer): TJSONArray;
var
  Msg: TIdMessage;
begin
  Result := TJSONArray.Create;
  Msg    := TIdMessage.Create(nil);
  try
    var Count := 0;
    var i     := High(AUIDs);   // most recent first
    while (i >= Low(AUIDs)) and (Count < ALimit) do
    begin
      var UIDStr := AUIDs[i].ToString;
      Msg.Clear;
      if AIMAP.UIDRetrieveHeader(UIDStr, Msg) then
        Result.AddElement(HeaderToJSON(Msg, UIDStr));
      Inc(Count);
      Dec(i);
    end;
  finally
    Msg.Free;
  end;
end;

function TIMAPTool.ExecuteWithParams(const AParams: TIMAPParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  IMAP: TIdIMAP4;
  SSL:  TTaurusTLSIOHandlerSocket;
begin
  try
    if AParams.Host     = '' then raise Exception.Create('"host" is required');
    if AParams.Username = '' then raise Exception.Create('"username" is required');
    if AParams.Password = '' then raise Exception.Create('"password" is required');

    var Op     := LowerCase(Trim(AParams.Operation));
    if Op = '' then Op := 'folders';
    var Folder := AParams.Folder;
    if Folder = '' then Folder := 'INBOX';
    var Limit  := AParams.Limit;
    if Limit <= 0 then Limit := 20;

    SSL  := TTaurusTLSIOHandlerSocket.Create(nil);
    IMAP := TIdIMAP4.Create(nil);
    try
      SetupIMAP(AParams, IMAP, SSL);
      // Connect(AAutoLogin=True) already calls Login internally — do NOT call
      // Login again or the server gets a LOGIN in csAuthenticated state → [CLIENTBUG].
      IMAP.Connect;

      try
        // ── folders ──────────────────────────────────────────────────────────
        if Op = 'folders' then
        begin
          var Names := TStringList.Create;
          try
            IMAP.ListMailBoxes(Names);
            var Arr := TJSONArray.Create;
            for var i := 0 to Names.Count - 1 do
              Arr.Add(Names[i]);
            var R := TJSONObject.Create;
            R.AddPair('folders', Arr);
            Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
            R.Free;
          finally
            Names.Free;
          end;
        end

        // ── list ─────────────────────────────────────────────────────────────
        else if Op = 'list' then
        begin
          IMAP.SelectMailBox(Folder);
          var SR := BuildSearchRec(AParams);
          IMAP.UIDSearchMailBox(SR);
          var UIDs := IMAP.MailBox.SearchResult;  // TUInt32Array = array of Cardinal
          var Arr  := FetchHeaders(IMAP, UIDs, Limit);
          var R    := TJSONObject.Create;
          R.AddPair('folder',   Folder);
          R.AddPair('total',    TJSONNumber.Create(Length(UIDs)));
          R.AddPair('returned', TJSONNumber.Create(Arr.Count));
          R.AddPair('messages', Arr);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        end

        // ── get ──────────────────────────────────────────────────────────────
        else if Op = 'get' then
        begin
          if AParams.UID = '' then raise Exception.Create('"uid" is required for get');
          IMAP.SelectMailBox(Folder);
          var Msg := TIdMessage.Create(nil);
          try
            if not IMAP.UIDRetrieve(AParams.UID, Msg) then
              raise Exception.Create('Message UID ' + AParams.UID + ' not found');
            var R := MessageToJSON(Msg, AParams.UID);
            Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
            R.Free;
          finally
            Msg.Free;
          end;
        end

        // ── search ───────────────────────────────────────────────────────────
        else if Op = 'search' then
        begin
          if (AParams.FromStr = '') and (AParams.SubjectStr = '') then
            raise Exception.Create('Provide from_str or subject_str for search');
          IMAP.SelectMailBox(Folder);
          var SR   := BuildSearchRec(AParams);
          IMAP.UIDSearchMailBox(SR);
          var UIDs := IMAP.MailBox.SearchResult;
          var Arr  := FetchHeaders(IMAP, UIDs, Limit);
          var R    := TJSONObject.Create;
          R.AddPair('total',    TJSONNumber.Create(Length(UIDs)));
          R.AddPair('returned', TJSONNumber.Create(Arr.Count));
          R.AddPair('messages', Arr);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        end

        // ── move ─────────────────────────────────────────────────────────────
        else if Op = 'move' then
        begin
          if AParams.UID        = '' then raise Exception.Create('"uid" is required for move');
          if AParams.DestFolder = '' then raise Exception.Create('"dest_folder" is required');
          IMAP.SelectMailBox(Folder);
          if not IMAP.UIDCopyMsg(AParams.UID, AParams.DestFolder) then
            raise Exception.Create('Copy to ' + AParams.DestFolder + ' failed');
          IMAP.UIDDeleteMsg(AParams.UID);
          IMAP.ExpungeMailBox;
          var R := TJSONObject.Create;
          R.AddPair('ok',          TJSONBool.Create(True));
          R.AddPair('uid',         AParams.UID);
          R.AddPair('dest_folder', AParams.DestFolder);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        end

        // ── delete ───────────────────────────────────────────────────────────
        else if Op = 'delete' then
        begin
          if AParams.UID = '' then raise Exception.Create('"uid" is required for delete');
          IMAP.SelectMailBox(Folder);
          IMAP.UIDDeleteMsg(AParams.UID);
          IMAP.ExpungeMailBox;
          var R := TJSONObject.Create;
          R.AddPair('ok',  TJSONBool.Create(True));
          R.AddPair('uid', AParams.UID);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        end

        // ── mark ─────────────────────────────────────────────────────────────
        else if Op = 'mark' then
        begin
          if AParams.UID    = '' then raise Exception.Create('"uid" is required for mark');
          if AParams.MarkAs = '' then raise Exception.Create('"mark_as" is required');
          IMAP.SelectMailBox(Folder);

          var MarkStr := LowerCase(Trim(AParams.MarkAs));
          var Flags:  TIdMessageFlagsSet;
          var Method: TIdIMAP4StoreDataItem;

          if      MarkStr = 'read'      then begin Flags := [mfSeen];    Method := sdAdd;    end
          else if MarkStr = 'unread'    then begin Flags := [mfSeen];    Method := sdRemove; end
          else if MarkStr = 'flagged'   then begin Flags := [mfFlagged]; Method := sdAdd;    end
          else if MarkStr = 'unflagged' then begin Flags := [mfFlagged]; Method := sdRemove; end
          else raise Exception.Create('"mark_as" must be read, unread, flagged, or unflagged');

          IMAP.UIDStoreFlags(AParams.UID, Method, Flags);
          var R := TJSONObject.Create;
          R.AddPair('ok',      TJSONBool.Create(True));
          R.AddPair('uid',     AParams.UID);
          R.AddPair('mark_as', AParams.MarkAs);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        end

        else
          raise Exception.Create('Unknown operation: ' + AParams.Operation);

      finally
        IMAP.Disconnect;
      end;
    finally
      IMAP.Free;
      SSL.Free;
    end;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-imap]: ' + E.Message)
        .Build;
  end;
end;

constructor TIMAPTool.Create;
begin
  inherited;
  FName        := 'mcp-imap';
  FDescription :=
    'Read and manage email via IMAP4. ' +
    'Operations: folders (list mailboxes), list (message headers, most recent first), ' +
    'get (full message by uid), search (by from_str/subject_str), ' +
    'move (uid + dest_folder), delete (uid), mark (uid + mark_as: read/unread/flagged/unflagged). ' +
    'Params: host, port (993), ssl (ssl/starttls/none), username, password, ' +
    'operation, folder (INBOX), uid (string), filter (all/unseen/seen/flagged), ' +
    'from_str, subject_str, limit (20), dest_folder, mark_as. ' +
    'Gmail: imap.gmail.com:993 ssl + App Password. Outlook: outlook.office365.com:993.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-imap',
    function: IAiMCPTool
    begin
      Result := TIMAPTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-imap');
end;

end.
