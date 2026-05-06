unit MCPTool.Perplexity;

{
  MCPTool.Perplexity  ·  mcp-perplexity  (port 8620)
  Perplexity AI search and chat via API (api.perplexity.ai).
  Compatible with OpenAI chat completions format.

  Operations:
    search  - web-grounded search with citations
    chat    - general chat with optional online search models
    sonar   - use sonar-pro or sonar-reasoning models
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TPerplexityParams = class
  private
    FOperation:   string;
    FApiKey:      string;
    FQuery:       string;
    FModel:       string;
    FMaxTokens:   Integer;
    FTemperature: Double;
    FSystemPrompt: string;
    FMessages:    string;
    FReturnCitations: Boolean;
    FReturnImages: Boolean;
    FSearchDomainFilter: string;
    FSearchRecencyFilter: string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: search, chat')]
    property Operation:   string  read FOperation   write FOperation;

    [AiMCPSchemaDescription('Perplexity API key')]
    property ApiKey:      string  read FApiKey      write FApiKey;

    [AiMCPSchemaDescription('Query or message content')]
    property Query:       string  read FQuery       write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Model: sonar, sonar-pro, sonar-reasoning, sonar-reasoning-pro (default: sonar)')]
    property Model:       string  read FModel       write FModel;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max tokens to generate (default: 1024)')]
    property MaxTokens:   Integer read FMaxTokens   write FMaxTokens;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Temperature 0.0-2.0 (default: 0.2)')]
    property Temperature: Double  read FTemperature write FTemperature;

    [AiMCPOptional]
    [AiMCPSchemaDescription('System prompt (optional)')]
    property SystemPrompt: string read FSystemPrompt write FSystemPrompt;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Conversation history as JSON array of {role,content} objects (for chat)')]
    property Messages:    string  read FMessages    write FMessages;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Return source citations (default: true)')]
    property ReturnCitations: Boolean read FReturnCitations write FReturnCitations;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Return related images (default: false)')]
    property ReturnImages: Boolean read FReturnImages write FReturnImages;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Comma-separated domain allowlist/blocklist, prefix with - to block: "example.com,-spam.com"')]
    property SearchDomainFilter: string read FSearchDomainFilter write FSearchDomainFilter;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Recency filter: month, week, day, hour (optional)')]
    property SearchRecencyFilter: string read FSearchRecencyFilter write FSearchRecencyFilter;
  end;

  TPerplexityTool = class(TAiMCPToolBase<TPerplexityParams>)
  private
    function ApiChat(const Body, ApiKey: string): TJSONObject;
    function BuildBody(const P: TPerplexityParams; const UserMsg: string): string;
    function DoSearch(const P: TPerplexityParams): TJSONObject;
    function DoChat(const P: TPerplexityParams): TJSONObject;
    function ExtractResult(J: TJSONObject): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TPerplexityParams;
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
  System.Net.URLClient;

{ TPerplexityParams }

constructor TPerplexityParams.Create;
begin
  inherited;
  FModel            := 'sonar';
  FMaxTokens        := 1024;
  FTemperature      := 0.2;
  FReturnCitations  := True;
  FReturnImages     := False;
end;

{ TPerplexityTool }

function TPerplexityTool.ApiChat(const Body, ApiKey: string): TJSONObject;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
  Raw:    string;
  J:      TJSONValue;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Post('https://api.perplexity.ai/chat/completions', Stream, nil,
      [TNameValuePair.Create('Content-Type',  'application/json'),
       TNameValuePair.Create('Authorization', 'Bearer ' + ApiKey)]);
    Raw := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;

  J := TJSONObject.ParseJSONValue(Raw);
  if Assigned(J) and (J is TJSONObject) then
    Result := J as TJSONObject
  else
  begin
    Result := TJSONObject.Create;
    Result.AddPair('raw', TJSONString.Create(Raw));
    J.Free;
  end;
end;

function TPerplexityTool.BuildBody(const P: TPerplexityParams;
  const UserMsg: string): string;
var
  Model: string;
  RC, RI: string;
begin
  Model := Trim(P.Model);
  if Model = '' then Model := 'sonar';

  if P.ReturnCitations then RC := 'true' else RC := 'false';
  if P.ReturnImages    then RI := 'true' else RI := 'false';

  Result := Format('{"model":"%s","max_tokens":%d,"temperature":%g,' +
    '"return_citations":%s,"return_images":%s,"messages":[',
    [Model, P.MaxTokens, P.Temperature, RC, RI]);

  if Trim(P.SystemPrompt) <> '' then
    Result := Result + Format('{"role":"system","content":"%s"},',
      [P.SystemPrompt.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);

  // Add history if provided
  if Trim(P.Messages) <> '' then
  begin
    // Messages is already a JSON array body — strip brackets and append
    var Msgs := Trim(P.Messages);
    if (Msgs <> '') and (Msgs[1] = '[') then
      Msgs := Copy(Msgs, 2, Length(Msgs) - 2);
    if Msgs <> '' then
      Result := Result + Msgs + ',';
  end;

  Result := Result + Format('{"role":"user","content":"%s"}]',
    [UserMsg.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);

  if Trim(P.SearchDomainFilter) <> '' then
  begin
    var Domains := Trim(P.SearchDomainFilter).Split([',']);
    Result := Result + ',"search_domain_filter":[';
    var i: Integer;
    for i := 0 to High(Domains) do
    begin
      if i > 0 then Result := Result + ',';
      Result := Result + '"' + Trim(Domains[i]) + '"';
    end;
    Result := Result + ']';
  end;

  if Trim(P.SearchRecencyFilter) <> '' then
    Result := Result + ',"search_recency_filter":"' + Trim(P.SearchRecencyFilter) + '"';

  Result := Result + '}';
end;

function TPerplexityTool.ExtractResult(J: TJSONObject): TJSONObject;
var
  Content:   string;
  Citations: TJSONValue;
  Usage:     TJSONValue;
begin
  Result := TJSONObject.Create;

  // Extract message content
  var Choice := J.FindValue('choices[0].message.content');
  if Assigned(Choice) then
    Content := Choice.Value
  else
    Content := '';

  Result.AddPair('content', TJSONString.Create(Content));

  // Citations
  Citations := J.FindValue('citations');
  if Assigned(Citations) then
    Result.AddPair('citations', Citations.Clone as TJSONValue);

  // Model
  var ModelVal := J.FindValue('model');
  if Assigned(ModelVal) then
    Result.AddPair('model', TJSONString.Create(ModelVal.Value));

  // Usage
  Usage := J.FindValue('usage');
  if Assigned(Usage) then
    Result.AddPair('usage', Usage.Clone as TJSONValue);

  Result.AddPair('ok', TJSONTrue.Create);
  J.Free;
end;

function TPerplexityTool.DoSearch(const P: TPerplexityParams): TJSONObject;
var
  Body: string;
  J:    TJSONObject;
begin
  Body := BuildBody(P, Trim(P.Query));
  J    := ApiChat(Body, Trim(P.ApiKey));
  Result := ExtractResult(J);
end;

function TPerplexityTool.DoChat(const P: TPerplexityParams): TJSONObject;
var
  Body: string;
  J:    TJSONObject;
begin
  Body := BuildBody(P, Trim(P.Query));
  J    := ApiChat(Body, Trim(P.ApiKey));
  Result := ExtractResult(J);
end;

function TPerplexityTool.ExecuteWithParams(const AParams: TPerplexityParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');
    if Trim(AParams.ApiKey) = '' then raise Exception.Create('"apiKey" is required');
    if Trim(AParams.Query)  = '' then raise Exception.Create('"query" is required');

    if      Op = 'search' then R := DoSearch(AParams)
    else if Op = 'chat'   then R := DoChat(AParams)
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

constructor TPerplexityTool.Create;
begin
  inherited;
  FName        := 'mcp-perplexity';
  FDescription :=
    'Perplexity AI web search and chat via API. ' +
    'Operations: search (web-grounded answer with citations), chat (conversational with optional history). ' +
    'Required: apiKey, query. ' +
    'Optional: model (sonar/sonar-pro/sonar-reasoning/sonar-reasoning-pro, default: sonar), ' +
    'maxTokens (default: 1024), temperature (default: 0.2), systemPrompt, ' +
    'messages (JSON conversation history), returnCitations (default: true), ' +
    'searchDomainFilter (comma-sep domains, prefix - to block), ' +
    'searchRecencyFilter (month/week/day/hour).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-perplexity',
    function: IAiMCPTool
    begin
      Result := TPerplexityTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-perplexity');
end;

end.
