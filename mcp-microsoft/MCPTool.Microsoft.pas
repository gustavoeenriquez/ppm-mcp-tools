unit MCPTool.Microsoft;

{
  MCPTool.Microsoft  ·  mcp-microsoft

  Outlook (correo), calendario y OneDrive de una cuenta Microsoft 365 por
  Microsoft Graph (https://graph.microsoft.com/v1.0, fijo: el modelo no elige
  a donde se conecta).

  Credencial: un access_token OAuth de la cuenta.
    - En un servidor (MKAIServer, Conexiones fase 3) llega en la cabecera
      Authorization de cada peticion ("Bearer <token>"): el broker lo obtiene y
      lo renueva; este proceso no guarda nada.
    - En stdio, de la variable MS_ACCESS_TOKEN (pruebas).

  Tools:
    outlook  - folders, list, search, get, send, reply, move, delete, mark
    calendar - list, get, create, update, delete
    onedrive - list, search, get, read (solo texto, hasta 200 KB)
  Las respuestas se recortan a lo util para no gastar tokens del modelo.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON;

type
  TOutlookParams = class
  private
    FOperation, FFolder, FQuery, FFilter, FId, FTo, FCc, FBcc, FSubject,
    FBody, FHtml, FComment, FDest, FMark: string;
    FLimit: Integer;
  public
    [AiMCPSchemaDescription('folders | list (default) | search | get | send | reply | move | delete | mark')]
    property Operation: string read FOperation write FOperation;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Folder for list: inbox (default), sentitems, drafts, archive, deleteditems, junkemail, or a folder id from folders')]
    property Folder: string read FFolder write FFolder;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Text to search for (search): words, sender or subject')]
    property Query: string read FQuery write FQuery;
    [AiMCPOptional]
    [AiMCPSchemaDescription('For list: all (default) or unread')]
    property Filter: string read FFilter write FFilter;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Max messages for list/search (default 15, max 50)')]
    property Limit: Integer read FLimit write FLimit;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Message id (get, reply, move, delete, mark) as returned by list/search')]
    property Id: string read FId write FId;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Recipients for send, comma-separated')]
    property To_: string read FTo write FTo;
    [AiMCPOptional]
    [AiMCPSchemaDescription('CC for send, comma-separated')]
    property Cc: string read FCc write FCc;
    [AiMCPOptional]
    [AiMCPSchemaDescription('BCC for send, comma-separated')]
    property Bcc: string read FBcc write FBcc;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Subject for send')]
    property Subject: string read FSubject write FSubject;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Body for send')]
    property Body: string read FBody write FBody;
    [AiMCPOptional]
    [AiMCPSchemaDescription('"true" if body is HTML (default plain text)')]
    property Html: string read FHtml write FHtml;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Reply text (reply)')]
    property Comment: string read FComment write FComment;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Destination folder for move (well-known name or id)')]
    property Dest: string read FDest write FDest;
    [AiMCPOptional]
    [AiMCPSchemaDescription('For mark: read, unread, flagged, unflagged')]
    property Mark: string read FMark write FMark;
  end;

  TCalendarParams = class
  private
    FOperation, FStartTime, FEndTime, FTimezone, FId, FSubject, FBody,
    FLocation, FAttendees, FOnline: string;
  public
    [AiMCPSchemaDescription('list (default) | get | create | update | delete')]
    property Operation: string read FOperation write FOperation;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Start, ISO local date-time e.g. 2026-10-06T09:00:00 (list: range start, default now; create/update: event start)')]
    property StartTime: string read FStartTime write FStartTime;
    [AiMCPOptional]
    [AiMCPSchemaDescription('End, ISO local date-time (list: range end, default start+7 days; create/update: event end)')]
    property EndTime: string read FEndTime write FEndTime;
    [AiMCPOptional]
    [AiMCPSchemaDescription('IANA time zone of the times (default America/Bogota)')]
    property Timezone: string read FTimezone write FTimezone;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Event id (get, update, delete)')]
    property Id: string read FId write FId;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Event title (create/update)')]
    property Subject: string read FSubject write FSubject;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Event description (create/update)')]
    property Body: string read FBody write FBody;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Place (create/update)')]
    property Location: string read FLocation write FLocation;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Attendee emails, comma-separated (create/update; they get an invitation)')]
    property Attendees: string read FAttendees write FAttendees;
    [AiMCPOptional]
    [AiMCPSchemaDescription('"true" to add an online meeting (work/school accounts)')]
    property Online: string read FOnline write FOnline;
  end;

  TOneDriveParams = class
  private
    FOperation, FPath, FQuery, FId: string;
    FLimit: Integer;
  public
    [AiMCPSchemaDescription('list (default) | search | get | read')]
    property Operation: string read FOperation write FOperation;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Folder path for list, e.g. Documentos/Contratos (default: root)')]
    property Path: string read FPath write FPath;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Text to search for (search)')]
    property Query: string read FQuery write FQuery;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Item id (get, read) as returned by list/search')]
    property Id: string read FId write FId;
    [AiMCPOptional]
    [AiMCPSchemaDescription('Max items for list/search (default 25, max 100)')]
    property Limit: Integer read FLimit write FLimit;
  end;

  TOutlookTool = class(TAiMCPToolBase<TOutlookParams>)
  protected
    function ExecuteWithParams(const AParams: TOutlookParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  TCalendarTool = class(TAiMCPToolBase<TCalendarParams>)
  protected
    function ExecuteWithParams(const AParams: TCalendarParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  TOneDriveTool = class(TAiMCPToolBase<TOneDriveParams>)
  protected
    function ExecuteWithParams(const AParams: TOneDriveParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.Classes, System.StrUtils, System.DateUtils, System.NetEncoding,
  System.Net.HttpClient, System.Net.URLClient,
  MCPTool.Credential;

const
  GRAPH_URL = 'https://graph.microsoft.com/v1.0';
  MAX_BODY = 20000;

type
  EGraph = class(Exception);

// ── Graph ────────────────────────────────────────────────────────────────────

function AuthHeader(const AuthContext: TAiAuthContext): string;
begin
  if ServerMode then
    Result := Trim(AuthContext.UserID)
  else
    Result := Trim(GetEnvironmentVariable('MS_ACCESS_TOKEN'));
  if Result = '' then
    raise EGraph.Create('No hay una cuenta de Microsoft conectada (Conexiones).');
  if not Result.StartsWith('Bearer ', True) then
    Result := 'Bearer ' + Result;
end;

function Enc(const S: string): string;
begin
  Result := TNetEncoding.URL.Encode(S).Replace('+', '%20', [rfReplaceAll]);
end;

// Llamada a Graph. Devuelve el JSON (o nil si no hay cuerpo). Error de Graph
// -> EGraph con un mensaje entendible.
function Graph(const AuthContext: TAiAuthContext; const AMethod, APath: string;
  ABody: TJSONObject = nil; const APrefer: string = ''): TJSONValue;
var
  C: THTTPClient;
  R: IHTTPResponse;
  Src: TStringStream;
  Hdrs: TNetHeaders;
  Txt, Msg: string;
  V: TJSONValue;
begin
  Result := nil;
  Hdrs := [TNameValuePair.Create('Authorization', AuthHeader(AuthContext)),
           TNameValuePair.Create('Accept', 'application/json')];
  if APrefer <> '' then
    Hdrs := Hdrs + [TNameValuePair.Create('Prefer', APrefer)];
  C := THTTPClient.Create;
  Src := nil;
  try
    C.ConnectionTimeout := 10000;
    C.ResponseTimeout   := 60000;
    if Assigned(ABody) then
    begin
      Src := TStringStream.Create(ABody.ToJSON, TEncoding.UTF8);
      Hdrs := Hdrs + [TNameValuePair.Create('Content-Type', 'application/json')];
    end;
    if AMethod = 'GET' then R := C.Get(GRAPH_URL + APath, nil, Hdrs)
    else if AMethod = 'DELETE' then R := C.Delete(GRAPH_URL + APath, nil, Hdrs)
    else if AMethod = 'PATCH' then R := C.Patch(GRAPH_URL + APath, Src, nil, Hdrs)
    else R := C.Post(GRAPH_URL + APath, Src, nil, Hdrs);
    Txt := R.ContentAsString(TEncoding.UTF8);
    if R.StatusCode >= 400 then
    begin
      Msg := '';
      V := TJSONObject.ParseJSONValue(Txt);
      try
        if V is TJSONObject then
          Msg := TJSONObject(V).GetValue<string>('error.message', '');
      finally
        V.Free;
      end;
      if R.StatusCode = 401 then
        raise EGraph.Create('Microsoft rechazo el acceso: vuelve a conectar la cuenta en Conexiones.');
      if R.StatusCode = 403 then
        raise EGraph.Create('La cuenta no tiene permiso para esto (' + Msg + ').');
      if R.StatusCode = 404 then
        raise EGraph.Create('No existe (id o ruta equivocados).');
      raise EGraph.CreateFmt('Microsoft respondio %d: %s', [R.StatusCode, Copy(Msg, 1, 300)]);
    end;
    if Trim(Txt) <> '' then
      Result := TJSONObject.ParseJSONValue(Txt);
  finally
    Src.Free;
    C.Free;
  end;
end;

function Ok(AObj: TJSONValue): TJSONObject;
begin
  try
    Result := TAiMCPResponseBuilder.New.AddText(AObj.ToJSON).Build;
  finally
    AObj.Free;
  end;
end;

function Fail(const ATool, AMsg: string): TJSONObject;
begin
  Result := TAiMCPResponseBuilder.New.AddText('Error [' + ATool + ']: ' + AMsg).Build;
end;

function Recipients(const AList: string): TJSONArray;
begin
  Result := TJSONArray.Create;
  for var A in AList.Split([',', ';']) do
    if Trim(A) <> '' then
      Result.Add(TJSONObject.Create(TJSONPair.Create('emailAddress',
        TJSONObject.Create(TJSONPair.Create('address', Trim(A))))));
end;

function Addr(V: TJSONValue): string;
begin
  Result := '';
  if V is TJSONObject then
  begin
    Result := TJSONObject(V).GetValue<string>('emailAddress.address', '');
    var N := TJSONObject(V).GetValue<string>('emailAddress.name', '');
    if (N <> '') and (N <> Result) then Result := N + ' <' + Result + '>';
  end;
end;

function AddrList(V: TJSONValue): string;
begin
  Result := '';
  if V is TJSONArray then
    for var E in TJSONArray(V) do
      Result := Result + IfThen(Result <> '', ', ', '') + Addr(E);
end;

function ClampLimit(ALimit, ADefault, AMax: Integer): Integer;
begin
  Result := ALimit;
  if Result <= 0 then Result := ADefault;
  if Result > AMax then Result := AMax;
end;

// ── Outlook ──────────────────────────────────────────────────────────────────

function MsgSummary(M: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', M.GetValue<string>('id', ''));
  Result.AddPair('from', Addr(M.GetValue('from')));
  Result.AddPair('subject', M.GetValue<string>('subject', ''));
  Result.AddPair('date', M.GetValue<string>('receivedDateTime', ''));
  Result.AddPair('read', TJSONBool.Create(M.GetValue<Boolean>('isRead', True)));
  if M.GetValue<Boolean>('hasAttachments', False) then
    Result.AddPair('attachments', TJSONBool.Create(True));
  Result.AddPair('preview', Copy(M.GetValue<string>('bodyPreview', ''), 1, 200));
end;

function MsgList(V: TJSONValue): TJSONObject;
var
  Arr: TJSONArray;
begin
  Arr := TJSONArray.Create;
  Result := TJSONObject.Create;
  Result.AddPair('messages', Arr);
  if V is TJSONObject then
    if TJSONObject(V).GetValue('value') is TJSONArray then
      for var M in TJSONArray(TJSONObject(V).GetValue('value')) do
        if M is TJSONObject then Arr.Add(MsgSummary(TJSONObject(M)));
end;

constructor TOutlookTool.Create;
begin
  inherited;
  FName := 'outlook';
  FDescription :=
    'Outlook email of the connected Microsoft account. ' +
    'Operations: folders; list (folder, filter all|unread, limit); search (query, limit); ' +
    'get (id: full message as plain text + attachment names); ' +
    'send (to_, cc?, bcc?, subject, body, html?); reply (id, comment); ' +
    'move (id, dest); delete (id, goes to Deleted Items); mark (id, mark: read|unread|flagged|unflagged). ' +
    'Ids come from list/search. Never ask the user for credentials.';
end;

function TOutlookTool.ExecuteWithParams(const AParams: TOutlookParams;
  const AuthContext: TAiAuthContext): TJSONObject;
const
  SEL = 'id,subject,from,receivedDateTime,isRead,bodyPreview,hasAttachments';
var
  Op, Id: string;
  V: TJSONValue;
  B, Msg: TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then Op := 'list';
    Id := Enc(Trim(AParams.Id));

    if Op = 'folders' then
    begin
      V := Graph(AuthContext, 'GET', '/me/mailFolders?$top=50&$select=id,displayName,unreadItemCount,totalItemCount');
      try
        var Arr := TJSONArray.Create;
        var R := TJSONObject.Create(TJSONPair.Create('folders', Arr));
        if (V is TJSONObject) and (TJSONObject(V).GetValue('value') is TJSONArray) then
          for var F in TJSONArray(TJSONObject(V).GetValue('value')) do
          begin
            var O := TJSONObject.Create;
            O.AddPair('id', F.GetValue<string>('id', ''));
            O.AddPair('name', F.GetValue<string>('displayName', ''));
            O.AddPair('unread', TJSONNumber.Create(F.GetValue<Integer>('unreadItemCount', 0)));
            O.AddPair('total', TJSONNumber.Create(F.GetValue<Integer>('totalItemCount', 0)));
            Arr.Add(O);
          end;
        Exit(Ok(R));
      finally
        V.Free;
      end;
    end

    else if Op = 'list' then
    begin
      var Folder := Trim(AParams.Folder);
      if Folder = '' then Folder := 'inbox';
      var Path := '/me/mailFolders/' + Enc(Folder) + '/messages?$top=' +
        IntToStr(ClampLimit(AParams.Limit, 15, 50)) + '&$select=' + SEL;
      if SameText(Trim(AParams.Filter), 'unread') then
        Path := Path + '&$filter=' + Enc('isRead eq false');
      V := Graph(AuthContext, 'GET', Path);
      try
        Exit(Ok(MsgList(V)));
      finally
        V.Free;
      end;
    end

    else if Op = 'search' then
    begin
      if Trim(AParams.Query) = '' then raise EGraph.Create('"query" is required for search');
      V := Graph(AuthContext, 'GET', '/me/messages?$search=' +
        Enc('"' + Trim(AParams.Query).Replace('"', '') + '"') + '&$top=' +
        IntToStr(ClampLimit(AParams.Limit, 15, 50)) + '&$select=' + SEL);
      try
        Exit(Ok(MsgList(V)));
      finally
        V.Free;
      end;
    end

    else if Op = 'get' then
    begin
      if Id = '' then raise EGraph.Create('"id" is required for get');
      V := Graph(AuthContext, 'GET', '/me/messages/' + Id +
        '?$select=id,subject,from,toRecipients,ccRecipients,receivedDateTime,body,hasAttachments',
        nil, 'outlook.body-content-type="text"');
      try
        if not (V is TJSONObject) then raise EGraph.Create('respuesta vacia');
        var M := TJSONObject(V);
        var R := TJSONObject.Create;
        R.AddPair('id', M.GetValue<string>('id', ''));
        R.AddPair('from', Addr(M.GetValue('from')));
        R.AddPair('to', AddrList(M.GetValue('toRecipients')));
        R.AddPair('cc', AddrList(M.GetValue('ccRecipients')));
        R.AddPair('subject', M.GetValue<string>('subject', ''));
        R.AddPair('date', M.GetValue<string>('receivedDateTime', ''));
        R.AddPair('body', Copy(M.GetValue<string>('body.content', ''), 1, MAX_BODY));
        if M.GetValue<Boolean>('hasAttachments', False) then
        begin
          var AV := Graph(AuthContext, 'GET', '/me/messages/' + Id +
            '/attachments?$select=name,contentType,size');
          try
            var Arr := TJSONArray.Create;
            R.AddPair('attachments', Arr);
            if (AV is TJSONObject) and (TJSONObject(AV).GetValue('value') is TJSONArray) then
              for var A in TJSONArray(TJSONObject(AV).GetValue('value')) do
                Arr.Add(A.GetValue<string>('name', '') + ' (' +
                  IntToStr(A.GetValue<Integer>('size', 0) div 1024) + ' KB)');
          finally
            AV.Free;
          end;
        end;
        Exit(Ok(R));
      finally
        V.Free;
      end;
    end

    else if Op = 'send' then
    begin
      if Trim(AParams.To_) = '' then raise EGraph.Create('"to_" is required for send');
      if Trim(AParams.Subject) = '' then raise EGraph.Create('"subject" is required for send');
      var NR := Length(AParams.To_.Split([',', ';'])) + Length(AParams.Cc.Split([',', ';'])) +
                Length(AParams.Bcc.Split([',', ';']));
      if NR > 20 then raise EGraph.Create('Demasiados destinatarios (maximo 20).');
      Msg := TJSONObject.Create;
      Msg.AddPair('subject', AParams.Subject);
      Msg.AddPair('body', TJSONObject.Create
        .AddPair('contentType', IfThen(SameText(AParams.Html, 'true'), 'HTML', 'Text'))
        .AddPair('content', AParams.Body));
      Msg.AddPair('toRecipients', Recipients(AParams.To_));
      if Trim(AParams.Cc) <> '' then Msg.AddPair('ccRecipients', Recipients(AParams.Cc));
      if Trim(AParams.Bcc) <> '' then Msg.AddPair('bccRecipients', Recipients(AParams.Bcc));
      B := TJSONObject.Create;
      try
        B.AddPair('message', Msg);
        B.AddPair('saveToSentItems', TJSONBool.Create(True));
        Graph(AuthContext, 'POST', '/me/sendMail', B).Free;
      finally
        B.Free;
      end;
      Exit(Ok(TJSONObject.Create.AddPair('sent', TJSONBool.Create(True))
        .AddPair('to', AParams.To_).AddPair('subject', AParams.Subject)));
    end

    else if Op = 'reply' then
    begin
      if Id = '' then raise EGraph.Create('"id" is required for reply');
      B := TJSONObject.Create(TJSONPair.Create('comment', AParams.Comment));
      try
        Graph(AuthContext, 'POST', '/me/messages/' + Id + '/reply', B).Free;
      finally
        B.Free;
      end;
      Exit(Ok(TJSONObject.Create.AddPair('replied', TJSONBool.Create(True))));
    end

    else if Op = 'move' then
    begin
      if (Id = '') or (Trim(AParams.Dest) = '') then
        raise EGraph.Create('"id" and "dest" are required for move');
      B := TJSONObject.Create(TJSONPair.Create('destinationId', Trim(AParams.Dest)));
      try
        Graph(AuthContext, 'POST', '/me/messages/' + Id + '/move', B).Free;
      finally
        B.Free;
      end;
      Exit(Ok(TJSONObject.Create.AddPair('moved', TJSONBool.Create(True))
        .AddPair('dest', AParams.Dest)));
    end

    else if Op = 'delete' then
    begin
      if Id = '' then raise EGraph.Create('"id" is required for delete');
      Graph(AuthContext, 'DELETE', '/me/messages/' + Id).Free;
      Exit(Ok(TJSONObject.Create.AddPair('deleted', TJSONBool.Create(True))));
    end

    else if Op = 'mark' then
    begin
      if Id = '' then raise EGraph.Create('"id" is required for mark');
      var MK := LowerCase(Trim(AParams.Mark));
      if MK = 'read' then B := TJSONObject.Create(TJSONPair.Create('isRead', TJSONBool.Create(True)))
      else if MK = 'unread' then B := TJSONObject.Create(TJSONPair.Create('isRead', TJSONBool.Create(False)))
      else if (MK = 'flagged') or (MK = 'unflagged') then
        B := TJSONObject.Create(TJSONPair.Create('flag', TJSONObject.Create(
          TJSONPair.Create('flagStatus', IfThen(MK = 'flagged', 'flagged', 'notFlagged')))))
      else raise EGraph.Create('"mark" must be read, unread, flagged or unflagged');
      try
        Graph(AuthContext, 'PATCH', '/me/messages/' + Id, B).Free;
      finally
        B.Free;
      end;
      Exit(Ok(TJSONObject.Create.AddPair('marked', MK)));
    end

    else
      raise EGraph.Create('Unknown operation: ' + Op);
  except
    on E: Exception do
      Result := Fail('outlook', E.Message);
  end;
end;

// ── Calendario ───────────────────────────────────────────────────────────────

function TZ(const AParams: TCalendarParams): string;
begin
  Result := Trim(AParams.Timezone);
  if Result = '' then Result := 'America/Bogota';
end;

function EventSummary(E: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', E.GetValue<string>('id', ''));
  Result.AddPair('subject', E.GetValue<string>('subject', ''));
  Result.AddPair('start', E.GetValue<string>('start.dateTime', ''));
  Result.AddPair('end', E.GetValue<string>('end.dateTime', ''));
  var Loc := E.GetValue<string>('location.displayName', '');
  if Loc <> '' then Result.AddPair('location', Loc);
  var Org := E.GetValue<string>('organizer.emailAddress.address', '');
  if Org <> '' then Result.AddPair('organizer', Org);
  var Att := AddrList(E.GetValue('attendees'));
  if Att <> '' then Result.AddPair('attendees', Att);
  var Url := E.GetValue<string>('onlineMeeting.joinUrl', '');
  if Url <> '' then Result.AddPair('meeting_url', Url);
end;

function EventBody(const AParams: TCalendarParams; ACreate: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  if AParams.Subject <> '' then Result.AddPair('subject', AParams.Subject);
  if AParams.Body <> '' then
    Result.AddPair('body', TJSONObject.Create.AddPair('contentType', 'Text')
      .AddPair('content', AParams.Body));
  if AParams.StartTime <> '' then
    Result.AddPair('start', TJSONObject.Create.AddPair('dateTime', AParams.StartTime)
      .AddPair('timeZone', TZ(AParams)));
  if AParams.EndTime <> '' then
    Result.AddPair('end', TJSONObject.Create.AddPair('dateTime', AParams.EndTime)
      .AddPair('timeZone', TZ(AParams)));
  if AParams.Location <> '' then
    Result.AddPair('location', TJSONObject.Create(TJSONPair.Create('displayName', AParams.Location)));
  if AParams.Attendees <> '' then
  begin
    var Arr := TJSONArray.Create;
    for var A in AParams.Attendees.Split([',', ';']) do
      if Trim(A) <> '' then
        Arr.Add(TJSONObject.Create.AddPair('emailAddress',
          TJSONObject.Create(TJSONPair.Create('address', Trim(A)))).AddPair('type', 'required'));
    Result.AddPair('attendees', Arr);
  end;
  if SameText(AParams.Online, 'true') then
    Result.AddPair('isOnlineMeeting', TJSONBool.Create(True));
end;

constructor TCalendarTool.Create;
begin
  inherited;
  FName := 'calendar';
  FDescription :=
    'Calendar of the connected Microsoft account. ' +
    'Operations: list (startTime?, endTime?, timezone?: events in the range, default next 7 days); ' +
    'get (id); create (subject, startTime, endTime, timezone?, body?, location?, attendees?, online?); ' +
    'update (id + fields to change); delete (id). Times are local ISO date-times in "timezone" ' +
    '(default America/Bogota). Attendees receive an invitation.';
end;

function TCalendarTool.ExecuteWithParams(const AParams: TCalendarParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op, Id, S, E: string;
  V: TJSONValue;
  B: TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then Op := 'list';
    Id := TNetEncoding.URL.Encode(Trim(AParams.Id));

    if Op = 'list' then
    begin
      S := Trim(AParams.StartTime);
      E := Trim(AParams.EndTime);
      if S = '' then S := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
      if E = '' then
        E := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', IncDay(ISO8601ToDate(S, False), 7));
      V := Graph(AuthContext, 'GET', '/me/calendarView?startDateTime=' + Enc(S) +
        '&endDateTime=' + Enc(E) + '&$top=50&$orderby=start/dateTime' +
        '&$select=id,subject,start,end,location,organizer,attendees,onlineMeeting',
        nil, 'outlook.timezone="' + TZ(AParams) + '"');
      try
        var Arr := TJSONArray.Create;
        var R := TJSONObject.Create;
        R.AddPair('timezone', TZ(AParams));
        R.AddPair('events', Arr);
        if (V is TJSONObject) and (TJSONObject(V).GetValue('value') is TJSONArray) then
          for var Ev in TJSONArray(TJSONObject(V).GetValue('value')) do
            if Ev is TJSONObject then Arr.Add(EventSummary(TJSONObject(Ev)));
        Exit(Ok(R));
      finally
        V.Free;
      end;
    end

    else if Op = 'get' then
    begin
      if Id = '' then raise EGraph.Create('"id" is required for get');
      V := Graph(AuthContext, 'GET', '/me/events/' + Id, nil,
        'outlook.timezone="' + TZ(AParams) + '"');
      try
        if not (V is TJSONObject) then raise EGraph.Create('respuesta vacia');
        var R := EventSummary(TJSONObject(V));
        R.AddPair('body', Copy(TJSONObject(V).GetValue<string>('bodyPreview', ''), 1, 2000));
        Exit(Ok(R));
      finally
        V.Free;
      end;
    end

    else if (Op = 'create') or (Op = 'update') then
    begin
      if Op = 'create' then
      begin
        if (AParams.Subject = '') or (AParams.StartTime = '') or (AParams.EndTime = '') then
          raise EGraph.Create('"subject", "startTime" and "endTime" are required for create');
      end
      else if Id = '' then
        raise EGraph.Create('"id" is required for update');
      B := EventBody(AParams, Op = 'create');
      try
        if Op = 'create' then
          V := Graph(AuthContext, 'POST', '/me/events', B, 'outlook.timezone="' + TZ(AParams) + '"')
        else
          V := Graph(AuthContext, 'PATCH', '/me/events/' + Id, B, 'outlook.timezone="' + TZ(AParams) + '"');
      finally
        B.Free;
      end;
      try
        if V is TJSONObject then
          Exit(Ok(EventSummary(TJSONObject(V))));
        Exit(Ok(TJSONObject.Create.AddPair('ok', TJSONBool.Create(True))));
      finally
        V.Free;
      end;
    end

    else if Op = 'delete' then
    begin
      if Id = '' then raise EGraph.Create('"id" is required for delete');
      Graph(AuthContext, 'DELETE', '/me/events/' + Id).Free;
      Exit(Ok(TJSONObject.Create.AddPair('deleted', TJSONBool.Create(True))));
    end

    else
      raise EGraph.Create('Unknown operation: ' + Op);
  except
    on Ex: Exception do
      Result := Fail('calendar', Ex.Message);
  end;
end;

// ── OneDrive ─────────────────────────────────────────────────────────────────

const
  DRIVE_SEL = 'id,name,size,folder,file,lastModifiedDateTime,webUrl';

function ItemSummary(I: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', I.GetValue<string>('id', ''));
  Result.AddPair('name', I.GetValue<string>('name', ''));
  Result.AddPair('type', IfThen(Assigned(I.GetValue('folder')), 'folder', 'file'));
  Result.AddPair('size', TJSONNumber.Create(I.GetValue<Int64>('size', 0)));
  Result.AddPair('modified', I.GetValue<string>('lastModifiedDateTime', ''));
  Result.AddPair('url', I.GetValue<string>('webUrl', ''));
end;

function ItemList(V: TJSONValue): TJSONObject;
var
  Arr: TJSONArray;
begin
  Arr := TJSONArray.Create;
  Result := TJSONObject.Create(TJSONPair.Create('items', Arr));
  if (V is TJSONObject) and (TJSONObject(V).GetValue('value') is TJSONArray) then
    for var I in TJSONArray(TJSONObject(V).GetValue('value')) do
      if I is TJSONObject then Arr.Add(ItemSummary(TJSONObject(I)));
end;

function IsTextName(const AName: string): Boolean;
const
  EXTS: array[0..10] of string = ('.txt', '.md', '.csv', '.json', '.xml', '.html',
    '.htm', '.log', '.yaml', '.yml', '.tsv');
begin
  Result := False;
  for var X in EXTS do
    if EndsText(X, AName) then Exit(True);
end;

constructor TOneDriveTool.Create;
begin
  inherited;
  FName := 'onedrive';
  FDescription :=
    'OneDrive files of the connected Microsoft account (read-only). ' +
    'Operations: list (path?: folder contents, default root); search (query); ' +
    'get (id: details and web link); read (id: content of a text file up to 200 KB — ' +
    'txt, md, csv, json, xml, html; for other types share the web link).';
end;

function TOneDriveTool.ExecuteWithParams(const AParams: TOneDriveParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op, Id, P: string;
  V: TJSONValue;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then Op := 'list';
    Id := TNetEncoding.URL.Encode(Trim(AParams.Id));
    var Top := '$top=' + IntToStr(ClampLimit(AParams.Limit, 25, 100));

    if Op = 'list' then
    begin
      P := Trim(AParams.Path).Trim(['/']);
      if P = '' then
        V := Graph(AuthContext, 'GET', '/me/drive/root/children?' + Top + '&$select=' + DRIVE_SEL)
      else
        V := Graph(AuthContext, 'GET', '/me/drive/root:/' + Enc(P).Replace('%2F', '/') +
          ':/children?' + Top + '&$select=' + DRIVE_SEL);
      try
        Exit(Ok(ItemList(V)));
      finally
        V.Free;
      end;
    end

    else if Op = 'search' then
    begin
      if Trim(AParams.Query) = '' then raise EGraph.Create('"query" is required for search');
      V := Graph(AuthContext, 'GET', '/me/drive/root/search(q=''' +
        Enc(Trim(AParams.Query).Replace('''', '''''')) + ''')?' + Top + '&$select=' + DRIVE_SEL);
      try
        Exit(Ok(ItemList(V)));
      finally
        V.Free;
      end;
    end

    else if Op = 'get' then
    begin
      if Id = '' then raise EGraph.Create('"id" is required for get');
      V := Graph(AuthContext, 'GET', '/me/drive/items/' + Id + '?$select=' + DRIVE_SEL);
      try
        if not (V is TJSONObject) then raise EGraph.Create('respuesta vacia');
        Exit(Ok(ItemSummary(TJSONObject(V))));
      finally
        V.Free;
      end;
    end

    else if Op = 'read' then
    begin
      if Id = '' then raise EGraph.Create('"id" is required for read');
      V := Graph(AuthContext, 'GET', '/me/drive/items/' + Id + '?$select=' + DRIVE_SEL);
      var Name, Url: string;
      var Size: Int64;
      try
        if not (V is TJSONObject) then raise EGraph.Create('respuesta vacia');
        Name := TJSONObject(V).GetValue<string>('name', '');
        Url  := TJSONObject(V).GetValue<string>('webUrl', '');
        Size := TJSONObject(V).GetValue<Int64>('size', 0);
        if Assigned(TJSONObject(V).GetValue('folder')) then
          raise EGraph.Create('Es una carpeta: usa list con su ruta.');
      finally
        V.Free;
      end;
      if not IsTextName(Name) or (Size > 200 * 1024) then
        Exit(Ok(TJSONObject.Create.AddPair('name', Name)
          .AddPair('readable', TJSONBool.Create(False))
          .AddPair('reason', 'Solo se leen archivos de texto de hasta 200 KB.')
          .AddPair('url', Url)));
      // /content redirige a la URL de descarga; THTTPClient sigue el 302
      var C := THTTPClient.Create;
      try
        C.ConnectionTimeout := 10000;
        C.ResponseTimeout := 60000;
        var R := C.Get(GRAPH_URL + '/me/drive/items/' + Id + '/content', nil,
          [TNameValuePair.Create('Authorization', AuthHeader(AuthContext))]);
        if R.StatusCode >= 400 then
          raise EGraph.CreateFmt('No se pudo descargar (HTTP %d).', [R.StatusCode]);
        Exit(Ok(TJSONObject.Create.AddPair('name', Name)
          .AddPair('content', Copy(R.ContentAsString(TEncoding.UTF8), 1, 200000))));
      finally
        C.Free;
      end;
    end

    else
      raise EGraph.Create('Unknown operation: ' + Op);
  except
    on Ex: Exception do
      Result := Fail('onedrive', Ex.Message);
  end;
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('outlook', function: IAiMCPTool begin Result := TOutlookTool.Create; end);
  AServer.RegisterTool('calendar', function: IAiMCPTool begin Result := TCalendarTool.Create; end);
  AServer.RegisterTool('onedrive', function: IAiMCPTool begin Result := TOneDriveTool.Create; end);
  WriteLn(ErrOutput, '[MCPService]   + outlook, calendar, onedrive');
end;

end.
