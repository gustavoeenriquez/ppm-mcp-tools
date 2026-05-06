unit MCPTool.SendGrid;

{
  MCPTool.SendGrid  ·  mcp-sendgrid

  Email delivery via SendGrid API v3.

  Operations:
    send         - send an email (simple or templated)
    send_bulk    - send to multiple recipients
    templates    - list dynamic transactional templates
    suppressions - list unsubscribed addresses
    stats        - get email delivery statistics (last N days)
    validate     - validate an email address (requires Email Validation add-on)
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.NetEncoding;

type

  TSendGridParams = class
  private
    FOperation:   string;
    FApiKey:      string;
    FTo:          string;
    FFrom:        string;
    FFromName:    string;
    FSubject:     string;
    FBody:        string;
    FHtmlBody:    string;
    FTemplateId:  string;
    FTemplateData:string;
    FDays:        Integer;
    FEmail:       string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: send, send_bulk, templates, suppressions, stats, validate')]
    property Operation:    string  read FOperation    write FOperation;

    [AiMCPSchemaDescription('SendGrid API key (starts with SG.)')]
    property ApiKey:       string  read FApiKey       write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Recipient email(s); comma-separated for multiple (for send/send_bulk)')]
    property &To:          string  read FTo           write FTo;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Sender email address')]
    property From:         string  read FFrom         write FFrom;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Sender display name')]
    property FromName:     string  read FFromName     write FFromName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Email subject')]
    property Subject:      string  read FSubject      write FSubject;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Plain text email body')]
    property Body:         string  read FBody         write FBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('HTML email body')]
    property HtmlBody:     string  read FHtmlBody     write FHtmlBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Dynamic template ID (for templated emails)')]
    property TemplateId:   string  read FTemplateId   write FTemplateId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Template dynamic data as JSON object, e.g. {"name":"Alice"}')]
    property TemplateData: string  read FTemplateData write FTemplateData;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of days for stats (default: 7)')]
    property Days:         Integer read FDays         write FDays;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Email to validate (for validate operation)')]
    property Email:        string  read FEmail        write FEmail;
  end;

  TSendGridTool = class(TAiMCPToolBase<TSendGridParams>)
  private
    function HttpGet(const URL, ApiKey: string): string;
    function HttpPost(const URL, ApiKey, Body: string): string;
    function BuildSendBody(const P: TSendGridParams): string;
    function DoSend(const P: TSendGridParams): TJSONObject;
    function DoSendBulk(const P: TSendGridParams): TJSONObject;
    function DoTemplates(const P: TSendGridParams): TJSONObject;
    function DoSuppressions(const P: TSendGridParams): TJSONObject;
    function DoStats(const P: TSendGridParams): TJSONObject;
    function DoValidate(const P: TSendGridParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TSendGridParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

const
  API_URL = 'https://api.sendgrid.com/v3';

{ TSendGridParams }

constructor TSendGridParams.Create;
begin
  inherited;
  FDays := 7;
end;

{ TSendGridTool }

function TSendGridTool.HttpGet(const URL, ApiKey: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 10000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + ApiKey)]);
    Result := Resp.ContentAsString;
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('SendGrid API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 400)]);
  finally
    HTTP.Free;
  end;
end;

function TSendGridTool.HttpPost(const URL, ApiKey, Body: string): string;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  Stream: TStringStream;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    HTTP.ConnectionTimeout := 10000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Post(URL, Stream, nil, [
      TNameValuePair.Create('Authorization', 'Bearer ' + ApiKey),
      TNameValuePair.Create('Content-Type',  'application/json')
    ]);
    Result := Resp.ContentAsString;
    // 200, 201, 202, 204 are success
    if (Resp.StatusCode >= 400) then
      raise Exception.CreateFmt('SendGrid API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 400)]);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TSendGridTool.BuildSendBody(const P: TSendGridParams): string;
var
  Root:           TJSONObject;
  Personaliz:     TJSONArray;
  PObj:           TJSONObject;
  ToArr:          TJSONArray;
  FromObj:        TJSONObject;
  ContentArr:     TJSONArray;
  Recipients:     TArray<string>;
  i:              Integer;
begin
  Recipients := P.&To.Split([',', ';']);

  Root       := TJSONObject.Create;
  Personaliz := TJSONArray.Create;
  PObj       := TJSONObject.Create;
  ToArr      := TJSONArray.Create;

  for i := 0 to High(Recipients) do
  begin
    var R := Trim(Recipients[i]);
    if R <> '' then
    begin
      var ToObj := TJSONObject.Create;
      ToObj.AddPair('email', R);
      ToArr.AddElement(ToObj);
    end;
  end;
  PObj.AddPair('to', ToArr);

  // Template data
  if P.TemplateData <> '' then
  begin
    var TplData := TJSONObject.ParseJSONValue(P.TemplateData);
    if TplData <> nil then
      PObj.AddPair('dynamic_template_data', TplData);
  end;

  Personaliz.AddElement(PObj);
  Root.AddPair('personalizations', Personaliz);

  // From
  FromObj := TJSONObject.Create;
  FromObj.AddPair('email', P.From);
  if P.FromName <> '' then
    FromObj.AddPair('name', P.FromName);
  Root.AddPair('from', FromObj);

  // Subject / template
  if P.TemplateId <> '' then
    Root.AddPair('template_id', P.TemplateId)
  else
  begin
    Root.AddPair('subject', P.Subject);
    ContentArr := TJSONArray.Create;
    if P.Body <> '' then
    begin
      var TextContent := TJSONObject.Create;
      TextContent.AddPair('type', 'text/plain');
      TextContent.AddPair('value', P.Body);
      ContentArr.AddElement(TextContent);
    end;
    if P.HtmlBody <> '' then
    begin
      var HtmlContent := TJSONObject.Create;
      HtmlContent.AddPair('type', 'text/html');
      HtmlContent.AddPair('value', P.HtmlBody);
      ContentArr.AddElement(HtmlContent);
    end;
    Root.AddPair('content', ContentArr);
  end;

  Result := Root.ToJSON;
  Root.Free;
end;

function TSendGridTool.DoSend(const P: TSendGridParams): TJSONObject;
var
  Body: string;
begin
  if P.ApiKey = '' then raise Exception.Create('"api_key" required');
  if P.&To    = '' then raise Exception.Create('"to" required for send');
  if P.From   = '' then raise Exception.Create('"from" required for send');
  if (P.TemplateId = '') and (P.Subject = '') then
    raise Exception.Create('"subject" or "template_id" required for send');
  if (P.TemplateId = '') and (P.Body = '') and (P.HtmlBody = '') then
    raise Exception.Create('"body" or "html_body" required for send');

  Body := BuildSendBody(P);
  HttpPost(API_URL + '/mail/send', P.ApiKey, Body);

  Result := TJSONObject.Create;
  Result.AddPair('to',      P.&To);
  Result.AddPair('from',    P.From);
  Result.AddPair('subject', P.Subject);
  Result.AddPair('sent',    TJSONTrue.Create);
  Result.AddPair('ok',      TJSONTrue.Create);
end;

function TSendGridTool.DoSendBulk(const P: TSendGridParams): TJSONObject;
begin
  // Send to multiple (comma-separated) recipients — same as DoSend
  Result := DoSend(P);
end;

function TSendGridTool.DoTemplates(const P: TSendGridParams): TJSONObject;
var
  RespStr: string;
  Parsed:  TJSONValue;
  Arr:     TJSONArray;
  Out:     TJSONArray;
  i:       Integer;
begin
  if P.ApiKey = '' then raise Exception.Create('"api_key" required');
  RespStr := HttpGet(API_URL + '/templates?generations=dynamic&page_size=100', P.ApiKey);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Out := TJSONArray.Create;
    Arr := nil;
    if Parsed is TJSONObject then
      (Parsed as TJSONObject).TryGetValue<TJSONArray>('templates', Arr);
    if Arr = nil then
    begin
      // Try direct array
      if Parsed is TJSONArray then Arr := Parsed as TJSONArray;
    end;
    if Arr <> nil then
      for i := 0 to Arr.Count - 1 do
      begin
        var T    := Arr.Items[i] as TJSONObject;
        var Item := TJSONObject.Create;
        Item.AddPair('id',   T.GetValue<string>('id', ''));
        Item.AddPair('name', T.GetValue<string>('name', ''));
        Out.AddElement(Item);
      end;

    Result := TJSONObject.Create;
    Result.AddPair('templates', Out);
    Result.AddPair('count',     TJSONNumber.Create(Out.Count));
    Result.AddPair('ok',        TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TSendGridTool.DoSuppressions(const P: TSendGridParams): TJSONObject;
var
  RespStr: string;
  Parsed:  TJSONValue;
  Arr:     TJSONArray;
  Out:     TJSONArray;
  i:       Integer;
begin
  if P.ApiKey = '' then raise Exception.Create('"api_key" required');
  RespStr := HttpGet(API_URL + '/suppression/unsubscribes?limit=100', P.ApiKey);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Out := TJSONArray.Create;
    if Parsed is TJSONArray then
    begin
      Arr := Parsed as TJSONArray;
      for i := 0 to Arr.Count - 1 do
      begin
        var Item := Arr.Items[i] as TJSONObject;
        var R    := TJSONObject.Create;
        R.AddPair('email',   Item.GetValue<string>('email', ''));
        R.AddPair('created', TJSONNumber.Create(Item.GetValue<Integer>('created', 0)));
        Out.AddElement(R);
      end;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('suppressions', Out);
    Result.AddPair('count',        TJSONNumber.Create(Out.Count));
    Result.AddPair('ok',           TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TSendGridTool.DoStats(const P: TSendGridParams): TJSONObject;
var
  Days:    Integer;
  StartDt: TDateTime;
  StartStr: string;
  RespStr: string;
  Parsed:  TJSONValue;
  Arr:     TJSONArray;
  TotalObj: TJSONObject;
  i:       Integer;
begin
  if P.ApiKey = '' then raise Exception.Create('"api_key" required');
  Days    := P.Days;
  if Days <= 0 then Days := 7;
  StartDt := Date - Days;
  StartStr := FormatDateTime('yyyy-mm-dd', StartDt);

  RespStr := HttpGet(Format('%s/stats?start_date=%s&aggregated_by=day', [API_URL, StartStr]), P.ApiKey);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    TotalObj := TJSONObject.Create;
    TotalObj.AddPair('requests', TJSONNumber.Create(0));
    TotalObj.AddPair('delivered', TJSONNumber.Create(0));
    TotalObj.AddPair('opens',    TJSONNumber.Create(0));
    TotalObj.AddPair('clicks',   TJSONNumber.Create(0));
    TotalObj.AddPair('bounces',  TJSONNumber.Create(0));

    if Parsed is TJSONArray then
    begin
      Arr := Parsed as TJSONArray;
      for i := 0 to Arr.Count - 1 do
      begin
        var Day := Arr.Items[i] as TJSONObject;
        var StatsArr: TJSONArray := nil;
        Day.TryGetValue<TJSONArray>('stats', StatsArr);
        if (StatsArr = nil) or (StatsArr.Count = 0) then Continue;
        var S := StatsArr.Items[0] as TJSONObject;
        var Metrics: TJSONObject := nil;
        S.TryGetValue<TJSONObject>('metrics', Metrics);
        if Metrics = nil then Continue;
        for var Field in ['requests','delivered','opens','clicks','bounces'] do
        begin
          var N: TJSONNumber := nil;
          if TotalObj.TryGetValue<TJSONNumber>(Field, N) then
          begin
            var Add := Metrics.GetValue<Integer>(Field, 0);
            var Old := N.AsInt;
            TotalObj.RemovePair(Field).Free;
            TotalObj.AddPair(Field, TJSONNumber.Create(Old + Add));
          end;
        end;
      end;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('start_date', StartStr);
    Result.AddPair('days',       TJSONNumber.Create(Days));
    Result.AddPair('totals',     TotalObj);
    Result.AddPair('ok',         TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TSendGridTool.DoValidate(const P: TSendGridParams): TJSONObject;
var
  Body:    string;
  RespStr: string;
  Parsed:  TJSONValue;
  J:       TJSONObject;
begin
  if P.ApiKey = '' then raise Exception.Create('"api_key" required');
  if P.Email  = '' then raise Exception.Create('"email" required for validate');

  Body    := '{"email":"' + P.Email + '"}';
  RespStr := HttpPost(API_URL + '/validations/email', P.ApiKey, Body);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
    begin
      J := Parsed as TJSONObject;
      Result.AddPair('email',     P.Email);
      Result.AddPair('valid',     TJSONBool.Create(J.GetValue<Boolean>('is_valid_format', False)));
      Result.AddPair('verdict',   J.GetValue<string>('verdict', ''));
      Result.AddPair('score',     TJSONNumber.Create(J.GetValue<Double>('score', 0)));
      Result.AddPair('suggested', J.GetValue<string>('did_you_mean', ''));
    end;
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TSendGridTool.ExecuteWithParams(const AParams: TSendGridParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'send'         then R := DoSend(AParams)
    else if Op = 'send_bulk'    then R := DoSendBulk(AParams)
    else if Op = 'templates'    then R := DoTemplates(AParams)
    else if Op = 'suppressions' then R := DoSuppressions(AParams)
    else if Op = 'stats'        then R := DoStats(AParams)
    else if Op = 'validate'     then R := DoValidate(AParams)
    else raise Exception.CreateFmt('Unknown operation "%s"', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message.Replace('\','\\').Replace('"','\"')
                   .Replace(#10,'\n').Replace(#13,'') + '"}')
        .Build;
  end;
end;

constructor TSendGridTool.Create;
begin
  inherited;
  FName        := 'mcp-sendgrid';
  FDescription :=
    'Email delivery via SendGrid API v3. Requires a SendGrid API key. ' +
    'Operations: ' +
    'send (send email; params: api_key, to, from, subject, body/html_body or template_id), ' +
    'send_bulk (send to multiple comma-separated recipients), ' +
    'templates (list dynamic templates; param: api_key), ' +
    'suppressions (list unsubscribed addresses; param: api_key), ' +
    'stats (delivery statistics; params: api_key, days?), ' +
    'validate (validate email address; params: api_key, email).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-sendgrid',
    function: IAiMCPTool
    begin
      Result := TSendGridTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-sendgrid');
end;

end.
