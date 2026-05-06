unit MCPTool.Replicate;

{
  MCPTool.Replicate  ·  mcp-replicate  (port 8628)
  Replicate.com — run AI models via cloud inference API.

  Operations:
    run              - run a model and wait for output (blocking)
    create           - create a prediction (async)
    get              - get prediction status/output
    cancel           - cancel a running prediction
    list             - list recent predictions
    list_models      - search/list models on Replicate
    get_model        - get model info
    list_versions    - list versions of a model
    get_version      - get specific version info
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TReplicateParams = class
  private
    FOperation:  string;
    FApiKey:     string;
    FModel:      string;
    FVersion:    string;
    FInput:      string;
    FPredId:     string;
    FWebhook:    string;
    FCursor:     string;
    FSearch:     string;
    FLimit:      Integer;
    FMaxWait:    Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: run, create, get, cancel, list, list_models, get_model, list_versions, get_version')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPSchemaDescription('Replicate API token (from replicate.com/account/api-tokens)')]
    property ApiKey:     string  read FApiKey     write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Model identifier: "owner/name" (e.g. stability-ai/sdxl) or "owner/name:version"')]
    property Model:      string  read FModel      write FModel;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Model version hash (if not embedded in model field)')]
    property Version:    string  read FVersion    write FVersion;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Model input as JSON object: {"prompt":"a cat","num_outputs":1}')]
    property Input:      string  read FInput      write FInput;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Prediction ID for get/cancel operations')]
    property PredId:     string  read FPredId     write FPredId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Webhook URL to receive prediction result (for create operation)')]
    property Webhook:    string  read FWebhook    write FWebhook;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Cursor for pagination in list operations')]
    property Cursor:     string  read FCursor     write FCursor;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search query for list_models')]
    property Search:     string  read FSearch     write FSearch;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max results for list/list_models (default: 10)')]
    property Limit:      Integer read FLimit      write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max seconds to wait for run to complete (default: 60)')]
    property MaxWait:    Integer read FMaxWait    write FMaxWait;
  end;

  TReplicateTool = class(TAiMCPToolBase<TReplicateParams>)
  private
    function ApiGet(const URL, ApiKey: string): string;
    function ApiPost(const URL, ApiKey, Body: string): string;
    function Wrap(const Raw: string): TJSONObject;
    function DoRun(const P: TReplicateParams): TJSONObject;
    function DoCreate(const P: TReplicateParams): TJSONObject;
    function DoGet(const P: TReplicateParams): TJSONObject;
    function DoCancel(const P: TReplicateParams): TJSONObject;
    function DoList(const P: TReplicateParams): TJSONObject;
    function DoListModels(const P: TReplicateParams): TJSONObject;
    function DoGetModel(const P: TReplicateParams): TJSONObject;
    function DoListVersions(const P: TReplicateParams): TJSONObject;
    function DoGetVersion(const P: TReplicateParams): TJSONObject;
    function ParseModelAndVersion(const ModelStr: string;
      out Owner, Name, Ver: string): Boolean;
  protected
    function ExecuteWithParams(const AParams: TReplicateParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.Threading;

const
  BASE = 'https://api.replicate.com/v1';

{ TReplicateParams }

constructor TReplicateParams.Create;
begin
  inherited;
  FLimit   := 10;
  FMaxWait := 60;
end;

{ TReplicateTool }

function TReplicateTool.ApiGet(const URL, ApiKey: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp   := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Trim(ApiKey)),
       TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TReplicateTool.ApiPost(const URL, ApiKey, Body: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp   := HTTP.Post(URL, Stream, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Trim(ApiKey)),
       TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TReplicateTool.Wrap(const Raw: string): TJSONObject;
var
  J: TJSONValue;
begin
  J := TJSONObject.ParseJSONValue(Raw);
  if Assigned(J) then
  begin
    if J is TJSONObject then
      Result := J as TJSONObject
    else
    begin
      Result := TJSONObject.Create;
      Result.AddPair('data', J);
    end;
  end
  else
  begin
    Result := TJSONObject.Create;
    if Raw <> '' then Result.AddPair('raw', TJSONString.Create(Raw));
  end;
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TReplicateTool.ParseModelAndVersion(const ModelStr: string;
  out Owner, Name, Ver: string): Boolean;
var
  Parts: TArray<string>;
  OwnerName: TArray<string>;
begin
  // Format: "owner/name:version" or "owner/name"
  Parts := ModelStr.Split([':']);
  OwnerName := Parts[0].Split(['/']);
  Result := Length(OwnerName) >= 2;
  if Result then
  begin
    Owner := OwnerName[0];
    Name  := OwnerName[1];
    if Length(Parts) >= 2 then Ver := Parts[1]
    else Ver := '';
  end;
end;

function TReplicateTool.DoCreate(const P: TReplicateParams): TJSONObject;
var
  M, V, Body, Owner, Name, Ver: string;
  Input: string;
begin
  M := Trim(P.Model);
  if M = '' then raise Exception.Create('"model" required (e.g. stability-ai/sdxl or owner/name:version)');
  V     := Trim(P.Version);
  Input := Trim(P.Input);
  if Input = '' then Input := '{}';

  if V = '' then
  begin
    // Try to parse version from model string
    if not ParseModelAndVersion(M, Owner, Name, Ver) then
      raise Exception.Create('Invalid model format. Use "owner/name" or "owner/name:version"');
    if Ver <> '' then
      Body := Format('{"version":"%s","input":%s}', [Ver, Input])
    else
      Body := Format('{"model":"%s","input":%s}', [M, Input]);
  end
  else
    Body := Format('{"version":"%s","input":%s}', [V, Input]);

  if Trim(P.Webhook) <> '' then
    Body := Copy(Body, 1, Length(Body) - 1) +
      Format(',"webhook":"%s","webhook_events_filter":["completed"]}', [Trim(P.Webhook)]);

  Result := Wrap(ApiPost(BASE + '/predictions', P.ApiKey, Body));
end;

function TReplicateTool.DoRun(const P: TReplicateParams): TJSONObject;
var
  PredJ:  TJSONObject;
  PredId, Status, Raw: string;
  Waited: Integer;
  MaxW:   Integer;
begin
  // Create prediction then poll until done
  PredJ := DoCreate(P);
  try
    PredId := PredJ.GetValue<string>('id', '');
    if PredId = '' then
    begin
      Result := PredJ;
      Exit;
    end;
  finally
    PredJ.Free;
  end;

  MaxW   := P.MaxWait; if MaxW <= 0 then MaxW := 60;
  Waited := 0;
  Status := 'starting';

  while (Status = 'starting') or (Status = 'processing') do
  begin
    Sleep(2000);
    Inc(Waited, 2);
    Raw    := ApiGet(BASE + '/predictions/' + PredId, P.ApiKey);
    Result := Wrap(Raw);
    Status := Result.GetValue<string>('status', 'failed');
    if Waited >= MaxW then
    begin
      Result.AddPair('timed_out', TJSONTrue.Create);
      Result.AddPair('prediction_id', TJSONString.Create(PredId));
      Exit;
    end;
    if (Status <> 'starting') and (Status <> 'processing') then
      Break;
    FreeAndNil(Result);
  end;
end;

function TReplicateTool.DoGet(const P: TReplicateParams): TJSONObject;
begin
  if Trim(P.PredId) = '' then raise Exception.Create('"predId" required for get');
  Result := Wrap(ApiGet(BASE + '/predictions/' + Trim(P.PredId), P.ApiKey));
end;

function TReplicateTool.DoCancel(const P: TReplicateParams): TJSONObject;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  if Trim(P.PredId) = '' then raise Exception.Create('"predId" required for cancel');
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create('', TEncoding.UTF8);
  try
    Resp   := HTTP.Post(BASE + '/predictions/' + Trim(P.PredId) + '/cancel',
      Stream, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Trim(P.ApiKey)),
       TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Wrap(Resp.ContentAsString(TEncoding.UTF8));
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TReplicateTool.DoList(const P: TReplicateParams): TJSONObject;
var
  URL: string;
begin
  URL := BASE + '/predictions';
  if Trim(P.Cursor) <> '' then URL := URL + '?cursor=' + Trim(P.Cursor);
  Result := Wrap(ApiGet(URL, P.ApiKey));
end;

function TReplicateTool.DoListModels(const P: TReplicateParams): TJSONObject;
var
  URL: string;
  Q:   string;
begin
  Q   := Trim(P.Search);
  if Q <> '' then
    URL := BASE + '/models?query=' + Q.Replace(' ', '+')
  else
    URL := BASE + '/models';
  Result := Wrap(ApiGet(URL, P.ApiKey));
end;

function TReplicateTool.DoGetModel(const P: TReplicateParams): TJSONObject;
var
  Owner, Name, Ver, M: string;
begin
  M := Trim(P.Model);
  if M = '' then raise Exception.Create('"model" required for get_model');
  if not ParseModelAndVersion(M, Owner, Name, Ver) then
    raise Exception.Create('Invalid model format. Use "owner/name"');
  Result := Wrap(ApiGet(Format('%s/models/%s/%s', [BASE, Owner, Name]), P.ApiKey));
end;

function TReplicateTool.DoListVersions(const P: TReplicateParams): TJSONObject;
var
  Owner, Name, Ver, M: string;
begin
  M := Trim(P.Model);
  if M = '' then raise Exception.Create('"model" required for list_versions');
  if not ParseModelAndVersion(M, Owner, Name, Ver) then
    raise Exception.Create('Invalid model format. Use "owner/name"');
  Result := Wrap(ApiGet(Format('%s/models/%s/%s/versions', [BASE, Owner, Name]), P.ApiKey));
end;

function TReplicateTool.DoGetVersion(const P: TReplicateParams): TJSONObject;
var
  Owner, Name, Ver, M, V: string;
begin
  M := Trim(P.Model);
  V := Trim(P.Version);
  if M = '' then raise Exception.Create('"model" required for get_version');
  if not ParseModelAndVersion(M, Owner, Name, Ver) then
    raise Exception.Create('Invalid model format. Use "owner/name"');
  if V = '' then V := Ver;
  if V = '' then raise Exception.Create('"version" required for get_version');
  Result := Wrap(ApiGet(Format('%s/models/%s/%s/versions/%s', [BASE, Owner, Name, V]), P.ApiKey));
end;

function TReplicateTool.ExecuteWithParams(const AParams: TReplicateParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    if Trim(AParams.ApiKey) = '' then
      raise Exception.Create('"apiKey" is required (get at replicate.com/account/api-tokens)');
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'run'           then R := DoRun(AParams)
    else if Op = 'create'        then R := DoCreate(AParams)
    else if Op = 'get'           then R := DoGet(AParams)
    else if Op = 'cancel'        then R := DoCancel(AParams)
    else if Op = 'list'          then R := DoList(AParams)
    else if Op = 'list_models'   then R := DoListModels(AParams)
    else if Op = 'get_model'     then R := DoGetModel(AParams)
    else if Op = 'list_versions' then R := DoListVersions(AParams)
    else if Op = 'get_version'   then R := DoGetVersion(AParams)
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

constructor TReplicateTool.Create;
begin
  inherited;
  FName        := 'mcp-replicate';
  FDescription :=
    'Replicate.com — run AI models (image generation, LLM, audio, video) via cloud API. ' +
    'Operations: run (params: model, input?, maxWait?) → blocking execution with output, ' +
    'create (params: model, input?, webhook?) → async prediction, returns id, ' +
    'get (params: predId) → prediction status and output, ' +
    'cancel (params: predId) → cancel running prediction, ' +
    'list → recent predictions, ' +
    'list_models (params: search?) → search model catalog, ' +
    'get_model (params: model) → model info, ' +
    'list_versions (params: model) → model versions, ' +
    'get_version (params: model, version) → version details. ' +
    'model format: "owner/name" or "owner/name:version". ' +
    'input must be JSON object matching model schema. apiKey required.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-replicate',
    function: IAiMCPTool
    begin
      Result := TReplicateTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-replicate');
end;

end.
