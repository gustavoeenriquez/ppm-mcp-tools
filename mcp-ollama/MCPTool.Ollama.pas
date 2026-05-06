unit MCPTool.Ollama;

{
  MCPTool.Ollama  ·  mcp-ollama  (port 8626)
  Local Ollama inference server (http://localhost:11434 by default).

  Operations:
    list        - list locally available models
    pull        - pull/download a model
    delete      - delete a local model
    show        - show model info and Modelfile
    running     - list currently loaded models
    generate    - text completion (single-turn)
    chat        - multi-turn chat
    embeddings  - generate embeddings for text
    copy        - copy a model to a new name
    health      - check Ollama server health
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TOllamaParams = class
  private
    FOperation: string;
    FHost:      string;
    FModel:     string;
    FPrompt:    string;
    FMessages:  string;
    FSystem:    string;
    FOptions:   string;
    FStream:    Boolean;
    FFrom:      string;
    FTo_:       string;
    FTexts:     string;
    FKeepAlive: string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list, pull, delete, show, running, generate, chat, embeddings, copy, health')]
    property Operation: string  read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Ollama server host (default: http://localhost:11434)')]
    property Host:      string  read FHost      write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Model name (e.g. llama3, mistral, phi3, gemma2, qwen2.5)')]
    property Model:     string  read FModel     write FModel;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Prompt text for generate')]
    property Prompt:    string  read FPrompt    write FPrompt;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Chat messages as JSON array: [{"role":"user","content":"Hello"}]')]
    property Messages:  string  read FMessages  write FMessages;

    [AiMCPOptional]
    [AiMCPSchemaDescription('System prompt for generate/chat')]
    property System_:   string  read FSystem    write FSystem;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Model options as JSON object: {"temperature":0.7,"num_predict":256}')]
    property Options:   string  read FOptions   write FOptions;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Source model name for copy operation')]
    property From_:     string  read FFrom      write FFrom;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Destination model name for copy operation')]
    property To__:      string  read FTo_       write FTo_;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Texts for embeddings as JSON string array: ["text1","text2"]')]
    property Texts:     string  read FTexts     write FTexts;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Keep model loaded duration: "5m", "1h", "0" to unload (default: "5m")')]
    property KeepAlive: string  read FKeepAlive write FKeepAlive;
  end;

  TOllamaTool = class(TAiMCPToolBase<TOllamaParams>)
  private
    function GetHost(const P: TOllamaParams): string;
    function ApiGet(const URL: string): string;
    function ApiPost(const URL, Body: string): string;
    function ApiDelete(const URL, Body: string): string;
    function Wrap(const Raw: string): TJSONObject;
    function DoList(const P: TOllamaParams): TJSONObject;
    function DoPull(const P: TOllamaParams): TJSONObject;
    function DoDelete(const P: TOllamaParams): TJSONObject;
    function DoShow(const P: TOllamaParams): TJSONObject;
    function DoRunning(const P: TOllamaParams): TJSONObject;
    function DoGenerate(const P: TOllamaParams): TJSONObject;
    function DoChat(const P: TOllamaParams): TJSONObject;
    function DoEmbeddings(const P: TOllamaParams): TJSONObject;
    function DoCopy(const P: TOllamaParams): TJSONObject;
    function DoHealth(const P: TOllamaParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TOllamaParams;
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

{ TOllamaParams }

constructor TOllamaParams.Create;
begin
  inherited;
  FHost      := 'http://localhost:11434';
  FStream    := False;
  FKeepAlive := '5m';
end;

{ TOllamaTool }

function TOllamaTool.GetHost(const P: TOllamaParams): string;
begin
  Result := Trim(P.Host);
  if Result = '' then Result := 'http://localhost:11434';
  // Strip trailing slash
  while (Result <> '') and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

function TOllamaTool.ApiGet(const URL: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp   := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TOllamaTool.ApiPost(const URL, Body: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp   := HTTP.Post(URL, Stream, nil,
      [TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TOllamaTool.ApiDelete(const URL, Body: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp   := HTTP.Delete(URL, Stream, nil,
      [TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TOllamaTool.Wrap(const Raw: string): TJSONObject;
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

function TOllamaTool.DoList(const P: TOllamaParams): TJSONObject;
begin
  Result := Wrap(ApiGet(GetHost(P) + '/api/tags'));
end;

function TOllamaTool.DoPull(const P: TOllamaParams): TJSONObject;
var
  M, Body: string;
begin
  M := Trim(P.Model);
  if M = '' then raise Exception.Create('"model" required for pull');
  Body   := Format('{"model":"%s","stream":false}', [M]);
  Result := Wrap(ApiPost(GetHost(P) + '/api/pull', Body));
end;

function TOllamaTool.DoDelete(const P: TOllamaParams): TJSONObject;
var
  M, Body: string;
begin
  M := Trim(P.Model);
  if M = '' then raise Exception.Create('"model" required for delete');
  Body   := Format('{"model":"%s"}', [M]);
  Result := Wrap(ApiDelete(GetHost(P) + '/api/delete', Body));
  if not Result.GetValue<Boolean>('ok', False) then
    Result.AddPair('deleted', TJSONString.Create(M));
end;

function TOllamaTool.DoShow(const P: TOllamaParams): TJSONObject;
var
  M, Body: string;
begin
  M := Trim(P.Model);
  if M = '' then raise Exception.Create('"model" required for show');
  Body   := Format('{"model":"%s","verbose":false}', [M]);
  Result := Wrap(ApiPost(GetHost(P) + '/api/show', Body));
end;

function TOllamaTool.DoRunning(const P: TOllamaParams): TJSONObject;
begin
  Result := Wrap(ApiGet(GetHost(P) + '/api/ps'));
end;

function TOllamaTool.DoGenerate(const P: TOllamaParams): TJSONObject;
var
  M, Pr, Body, Sys, Opts, KA: string;
begin
  M  := Trim(P.Model);  if M  = '' then raise Exception.Create('"model" required for generate');
  Pr := Trim(P.Prompt); if Pr = '' then raise Exception.Create('"prompt" required for generate');
  Sys  := Trim(P.System_);
  Opts := Trim(P.Options);
  KA   := Trim(P.KeepAlive); if KA = '' then KA := '5m';

  Body := Format('{"model":"%s","prompt":"%s","stream":false,"keep_alive":"%s"',
    [M, Pr.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,''), KA]);
  if Sys  <> '' then Body := Body + Format(',"system":"%s"',
    [Sys.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);
  if Opts <> '' then Body := Body + ',"options":' + Opts;
  Body   := Body + '}';
  Result := Wrap(ApiPost(GetHost(P) + '/api/generate', Body));
end;

function TOllamaTool.DoChat(const P: TOllamaParams): TJSONObject;
var
  M, Msgs, Body, Sys, Opts, KA: string;
begin
  M    := Trim(P.Model);    if M    = '' then raise Exception.Create('"model" required for chat');
  Msgs := Trim(P.Messages); if Msgs = '' then raise Exception.Create('"messages" JSON array required for chat');
  Sys  := Trim(P.System_);
  Opts := Trim(P.Options);
  KA   := Trim(P.KeepAlive); if KA = '' then KA := '5m';

  Body := Format('{"model":"%s","messages":%s,"stream":false,"keep_alive":"%s"', [M, Msgs, KA]);
  if Sys  <> '' then Body := Body + Format(',"system":"%s"',
    [Sys.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);
  if Opts <> '' then Body := Body + ',"options":' + Opts;
  Body   := Body + '}';
  Result := Wrap(ApiPost(GetHost(P) + '/api/chat', Body));
end;

function TOllamaTool.DoEmbeddings(const P: TOllamaParams): TJSONObject;
var
  M, Texts, Body: string;
begin
  M     := Trim(P.Model); if M = '' then raise Exception.Create('"model" required for embeddings');
  Texts := Trim(P.Texts);
  if Texts = '' then
  begin
    // Fall back to prompt if texts not given
    Texts := Trim(P.Prompt);
    if Texts = '' then raise Exception.Create('"texts" (JSON array) or "prompt" required for embeddings');
    Body := Format('{"model":"%s","input":"%s"}',
      [M, Texts.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);
  end
  else
    Body := Format('{"model":"%s","input":%s}', [M, Texts]);
  Result := Wrap(ApiPost(GetHost(P) + '/api/embed', Body));
end;

function TOllamaTool.DoCopy(const P: TOllamaParams): TJSONObject;
var
  From, To_, Body: string;
begin
  From := Trim(P.From_); if From = '' then raise Exception.Create('"from" required for copy');
  To_  := Trim(P.To__);  if To_  = '' then raise Exception.Create('"to" required for copy');
  Body   := Format('{"source":"%s","destination":"%s"}', [From, To_]);
  Result := Wrap(ApiPost(GetHost(P) + '/api/copy', Body));
end;

function TOllamaTool.DoHealth(const P: TOllamaParams): TJSONObject;
var
  Raw: string;
begin
  Raw    := ApiGet(GetHost(P) + '/');
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('status',  TJSONString.Create('healthy'));
  Result.AddPair('response', TJSONString.Create(Raw));
  Result.AddPair('host',    TJSONString.Create(GetHost(P)));
end;

function TOllamaTool.ExecuteWithParams(const AParams: TOllamaParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list'       then R := DoList(AParams)
    else if Op = 'pull'       then R := DoPull(AParams)
    else if Op = 'delete'     then R := DoDelete(AParams)
    else if Op = 'show'       then R := DoShow(AParams)
    else if Op = 'running'    then R := DoRunning(AParams)
    else if Op = 'generate'   then R := DoGenerate(AParams)
    else if Op = 'chat'       then R := DoChat(AParams)
    else if Op = 'embeddings' then R := DoEmbeddings(AParams)
    else if Op = 'copy'       then R := DoCopy(AParams)
    else if Op = 'health'     then R := DoHealth(AParams)
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

constructor TOllamaTool.Create;
begin
  inherited;
  FName        := 'mcp-ollama';
  FDescription :=
    'Local Ollama inference server. Default host: http://localhost:11434. ' +
    'Operations: list → available models, ' +
    'pull (params: model) → download model, ' +
    'delete (params: model) → remove model, ' +
    'show (params: model) → model info, ' +
    'running → currently loaded models, ' +
    'generate (params: model, prompt, system?, options?) → text completion, ' +
    'chat (params: model, messages=JSON array [{role,content}], system?, options?) → conversation, ' +
    'embeddings (params: model, texts=JSON array or prompt) → vector embeddings, ' +
    'copy (params: from, to) → duplicate model, ' +
    'health → server status. ' +
    'host param overrides default server URL. keepAlive controls model unload timeout.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-ollama',
    function: IAiMCPTool
    begin
      Result := TOllamaTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-ollama');
end;

end.
