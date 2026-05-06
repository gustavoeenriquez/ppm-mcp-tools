unit MCPTool.AzureOpenAI;

(*
  MCPTool.AzureOpenAI  ·  mcp-azure-openai  (port 8642)
  Azure OpenAI Service REST API wrapper.

  Operations:
    chat              - POST /openai/deployments/{id}/chat/completions
    complete          - POST /openai/deployments/{id}/completions
    embeddings        - POST /openai/deployments/{id}/embeddings
    list_deployments  - GET  /openai/deployments
    get_model         - GET  /openai/deployments/{id}
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TAzureOpenAIParams = class
  private
    FOperation:    string;
    FEndpoint:     string;
    FApiKey:       string;
    FDeploymentId: string;
    FPrompt:       string;
    FMessages:     string;
    FMaxTokens:    Integer;
    FTemperature:  string;
    FApiVersion:   string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: chat, complete, embeddings, list_deployments, get_model')]
    property Operation:    string  read FOperation    write FOperation;

    [AiMCPSchemaDescription('Azure OpenAI endpoint URL e.g. https://myresource.openai.azure.com')]
    property Endpoint:     string  read FEndpoint     write FEndpoint;

    [AiMCPSchemaDescription('Azure OpenAI API key')]
    property ApiKey:       string  read FApiKey       write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Deployment/model name e.g. gpt-4, gpt-35-turbo (required for chat, complete, embeddings, get_model)')]
    property DeploymentId: string  read FDeploymentId write FDeploymentId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('User prompt for chat/complete operations (used when Messages is not provided)')]
    property Prompt:       string  read FPrompt       write FPrompt;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON array string of messages for chat e.g. [{"role":"user","content":"hi"}]')]
    property Messages:     string  read FMessages     write FMessages;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max tokens to generate (default: 1000)')]
    property MaxTokens:    Integer read FMaxTokens    write FMaxTokens;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Temperature 0.0-2.0 as string e.g. "0.7" (omit to use model default)')]
    property Temperature:  string  read FTemperature  write FTemperature;

    [AiMCPOptional]
    [AiMCPSchemaDescription('API version string (default: 2024-02-01)')]
    property ApiVersion:   string  read FApiVersion   write FApiVersion;
  end;

  TAzureOpenAITool = class(TAiMCPToolBase<TAzureOpenAIParams>)
  private
    function BaseURL(const Endpoint, DeploymentId, Resource, ApiVersion: string): string;
    function ApiGet(const URL, ApiKey: string): string;
    function ApiPost(const URL, ApiKey, Body: string): string;
    function Wrap(const Raw: string): TJSONObject;
    function GetApiVersion(const P: TAzureOpenAIParams): string;
    function GetMaxTokens(const P: TAzureOpenAIParams): Integer;
    function DoChat(const P: TAzureOpenAIParams): TJSONObject;
    function DoComplete(const P: TAzureOpenAIParams): TJSONObject;
    function DoEmbeddings(const P: TAzureOpenAIParams): TJSONObject;
    function DoListDeployments(const P: TAzureOpenAIParams): TJSONObject;
    function DoGetModel(const P: TAzureOpenAIParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TAzureOpenAIParams;
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
  System.NetEncoding;

{ TAzureOpenAIParams }

constructor TAzureOpenAIParams.Create;
begin
  inherited;
  FMaxTokens  := 1000;
  FApiVersion := '2024-02-01';
end;

{ TAzureOpenAITool }

function TAzureOpenAITool.GetApiVersion(const P: TAzureOpenAIParams): string;
begin
  Result := Trim(P.ApiVersion);
  if Result = '' then
    Result := '2024-02-01';
end;

function TAzureOpenAITool.GetMaxTokens(const P: TAzureOpenAIParams): Integer;
begin
  Result := P.MaxTokens;
  if Result <= 0 then
    Result := 1000;
end;

function TAzureOpenAITool.BaseURL(const Endpoint, DeploymentId, Resource,
  ApiVersion: string): string;
var
  Base: string;
begin
  Base := Trim(Endpoint);
  while (Base <> '') and (Base[Length(Base)] = '/') do
    Delete(Base, Length(Base), 1);
  if DeploymentId <> '' then
    Result := Base + '/openai/deployments/' + DeploymentId + '/' + Resource +
              '?api-version=' + ApiVersion
  else
    Result := Base + '/openai/deployments?api-version=' + ApiVersion;
end;

function TAzureOpenAITool.ApiGet(const URL, ApiKey: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp   := HTTP.Get(URL, nil,
      [TNameValuePair.Create('api-key', ApiKey),
       TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TAzureOpenAITool.ApiPost(const URL, ApiKey, Body: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp   := HTTP.Post(URL, Stream, nil,
      [TNameValuePair.Create('api-key', ApiKey),
       TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TAzureOpenAITool.Wrap(const Raw: string): TJSONObject;
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
    if Raw <> '' then
      Result.AddPair('response', TJSONString.Create(Raw));
  end;
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TAzureOpenAITool.DoChat(const P: TAzureOpenAIParams): TJSONObject;
var
  DeployId, Msgs, Prompt, Body, Temp, URL, ApiVer: string;
  MaxT: Integer;
begin
  DeployId := Trim(P.DeploymentId);
  if DeployId = '' then
    raise Exception.Create('"deploymentId" required for chat');

  Msgs   := Trim(P.Messages);
  Prompt := Trim(P.Prompt);
  MaxT   := GetMaxTokens(P);
  Temp   := Trim(P.Temperature);
  ApiVer := GetApiVersion(P);

  if Msgs <> '' then
    Body := Format('{"messages":%s,"max_tokens":%d', [Msgs, MaxT])
  else if Prompt <> '' then
    Body := Format('{"messages":[{"role":"user","content":"%s"}],"max_tokens":%d',
      [Prompt.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,''),
       MaxT])
  else
    raise Exception.Create('"prompt" or "messages" required for chat');

  if Temp <> '' then
    Body := Body + ',"temperature":' + Temp;
  Body := Body + '}';

  URL    := BaseURL(P.Endpoint, DeployId, 'chat/completions', ApiVer);
  Result := Wrap(ApiPost(URL, P.ApiKey, Body));
end;

function TAzureOpenAITool.DoComplete(const P: TAzureOpenAIParams): TJSONObject;
var
  DeployId, Prompt, Body, Temp, URL, ApiVer: string;
  MaxT: Integer;
begin
  DeployId := Trim(P.DeploymentId);
  if DeployId = '' then
    raise Exception.Create('"deploymentId" required for complete');

  Prompt := Trim(P.Prompt);
  if Prompt = '' then
    raise Exception.Create('"prompt" required for complete');

  MaxT   := GetMaxTokens(P);
  Temp   := Trim(P.Temperature);
  ApiVer := GetApiVersion(P);

  Body := Format('{"prompt":"%s","max_tokens":%d',
    [Prompt.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,''),
     MaxT]);
  if Temp <> '' then
    Body := Body + ',"temperature":' + Temp;
  Body := Body + '}';

  URL    := BaseURL(P.Endpoint, DeployId, 'completions', ApiVer);
  Result := Wrap(ApiPost(URL, P.ApiKey, Body));
end;

function TAzureOpenAITool.DoEmbeddings(const P: TAzureOpenAIParams): TJSONObject;
var
  DeployId, Input, Body, URL, ApiVer: string;
begin
  DeployId := Trim(P.DeploymentId);
  if DeployId = '' then
    raise Exception.Create('"deploymentId" required for embeddings');

  Input := Trim(P.Prompt);
  if Input = '' then
    raise Exception.Create('"prompt" (input text) required for embeddings');

  ApiVer := GetApiVersion(P);
  Body   := Format('{"input":"%s"}',
    [Input.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);

  URL    := BaseURL(P.Endpoint, DeployId, 'embeddings', ApiVer);
  Result := Wrap(ApiPost(URL, P.ApiKey, Body));
end;

function TAzureOpenAITool.DoListDeployments(const P: TAzureOpenAIParams): TJSONObject;
var
  Base, URL, ApiVer: string;
begin
  Base   := Trim(P.Endpoint);
  while (Base <> '') and (Base[Length(Base)] = '/') do
    Delete(Base, Length(Base), 1);
  ApiVer := GetApiVersion(P);
  // list_deployments uses api-version 2022-12-01 by convention but honour override
  URL    := Base + '/openai/deployments?api-version=' + ApiVer;
  Result := Wrap(ApiGet(URL, P.ApiKey));
end;

function TAzureOpenAITool.DoGetModel(const P: TAzureOpenAIParams): TJSONObject;
var
  DeployId, Base, URL, ApiVer: string;
begin
  DeployId := Trim(P.DeploymentId);
  if DeployId = '' then
    raise Exception.Create('"deploymentId" required for get_model');

  Base   := Trim(P.Endpoint);
  while (Base <> '') and (Base[Length(Base)] = '/') do
    Delete(Base, Length(Base), 1);
  ApiVer := GetApiVersion(P);
  URL    := Base + '/openai/deployments/' + DeployId + '?api-version=' + ApiVer;
  Result := Wrap(ApiGet(URL, P.ApiKey));
end;

function TAzureOpenAITool.ExecuteWithParams(const AParams: TAzureOpenAIParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    if Trim(AParams.Endpoint) = '' then
      raise Exception.Create('"endpoint" is required');
    if Trim(AParams.ApiKey) = '' then
      raise Exception.Create('"apiKey" is required');

    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then
      raise Exception.Create('"operation" is required');

    if      Op = 'chat'             then R := DoChat(AParams)
    else if Op = 'complete'         then R := DoComplete(AParams)
    else if Op = 'embeddings'       then R := DoEmbeddings(AParams)
    else if Op = 'list_deployments' then R := DoListDeployments(AParams)
    else if Op = 'get_model'        then R := DoGetModel(AParams)
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

constructor TAzureOpenAITool.Create;
begin
  inherited;
  FName        := 'mcp-azure-openai';
  FDescription :=
    'Azure OpenAI Service REST API. Requires endpoint (e.g. https://myresource.openai.azure.com) ' +
    'and apiKey. ' +
    'Operations: ' +
    'chat (params: deploymentId, prompt OR messages=JSON array [{role,content}], maxTokens?, temperature?) ' +
      '→ chat completion response, ' +
    'complete (params: deploymentId, prompt, maxTokens?, temperature?) ' +
      '→ text completion response, ' +
    'embeddings (params: deploymentId, prompt=input text) ' +
      '→ embedding vectors, ' +
    'list_deployments → all deployed models in the resource, ' +
    'get_model (params: deploymentId) → single deployment info. ' +
    'apiVersion defaults to 2024-02-01. ' +
    'temperature is a string e.g. "0.7" to avoid decimal serialization issues.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-azure-openai',
    function: IAiMCPTool
    begin
      Result := TAzureOpenAITool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-azure-openai');
end;

end.
