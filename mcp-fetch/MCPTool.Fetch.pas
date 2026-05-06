unit MCPTool.Fetch;

{
  MCPTool.Fetch
  MCP tool: mcp-fetch

  General-purpose HTTP client.

  Operations (via the "method" parameter):
    GET    - fetch a URL, return status + body
    POST   - send body to a URL
    PUT    - replace resource at a URL
    PATCH  - partial update
    DELETE - delete a resource
    HEAD   - fetch headers only (no body)

  All operations return: status, ok, contentType, body (truncated to maxBodySize),
  responseHeaders (selected), and elapsed_ms.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Math,
  System.Net.HttpClient,
  System.Net.URLClient;

type

  // ── Parameters ─────────────────────────────────────────────────────────────

  TFetchParams = class
  private
    FUrl:         string;
    FMethod:      string;
    FBody:        string;
    FContentType: string;
    FHeaders:     string;
    FTimeout:     Integer;
    FMaxBodySize: Integer;
  public
    [AiMCPSchemaDescription('Target URL (must include https:// or http://)')]
    property Url: string read FUrl write FUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('HTTP method: GET, POST, PUT, PATCH, DELETE, HEAD (default: GET)')]
    property Method: string read FMethod write FMethod;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Request body text for POST/PUT/PATCH')]
    property Body: string read FBody write FBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Content-Type header (default: application/json for POST/PUT/PATCH)')]
    property ContentType: string read FContentType write FContentType;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Extra request headers as JSON object: {"Authorization": "Bearer token"}')]
    property Headers: string read FHeaders write FHeaders;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Request timeout in seconds (default: 30)')]
    property Timeout: Integer read FTimeout write FTimeout;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum response body characters to return (default: 524288 ≈ 512 KB)')]
    property MaxBodySize: Integer read FMaxBodySize write FMaxBodySize;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TFetchTool = class(TAiMCPToolBase<TFetchParams>)
  private
    procedure ApplyHeaders(Client: THTTPClient; const HeadersJSON: string);
  protected
    function ExecuteWithParams(const AParams: TFetchParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.DateUtils;

// ── Helpers ─────────────────────────────────────────────────────────────────

procedure TFetchTool.ApplyHeaders(Client: THTTPClient; const HeadersJSON: string);
begin
  if Trim(HeadersJSON) = '' then Exit;
  var JV := TJSONObject.ParseJSONValue(HeadersJSON);
  if not Assigned(JV) then Exit;
  try
    if JV is TJSONObject then
      for var Pair in TJSONObject(JV) do
        Client.CustomHeaders[Pair.JsonString.Value] := Pair.JsonValue.Value;
  finally
    JV.Free;
  end;
end;

// ── Main execution ──────────────────────────────────────────────────────────

function TFetchTool.ExecuteWithParams(const AParams: TFetchParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  R: TJSONObject;
begin
  try
    if AParams.Url = '' then
      raise Exception.Create('"url" is required');

    var Method := UpperCase(Trim(AParams.Method));
    if Method = '' then Method := 'GET';

    var TimeoutSec := AParams.Timeout;
    if TimeoutSec <= 0 then TimeoutSec := 30;

    var MaxChars := AParams.MaxBodySize;
    if MaxChars <= 0 then MaxChars := 524288;

    var Client := THTTPClient.Create;
    try
      Client.ConnectionTimeout := TimeoutSec * 1000;
      Client.ResponseTimeout   := TimeoutSec * 1000;
      Client.HandleRedirects   := True;

      ApplyHeaders(Client, AParams.Headers);

      var CT := AParams.ContentType;
      if CT = '' then CT := 'application/json';

      var T0 := Now;
      var Response: IHTTPResponse;

      if (Method = 'POST') or (Method = 'PUT') or (Method = 'PATCH') then
      begin
        Client.CustomHeaders['Content-Type'] := CT;
        var Stream := TStringStream.Create(AParams.Body, TEncoding.UTF8);
        try
          if      Method = 'POST'  then Response := Client.Post(AParams.Url, Stream)
          else if Method = 'PUT'   then Response := Client.Put(AParams.Url, Stream)
          else                          Response := Client.Patch(AParams.Url, Stream);
        finally
          Stream.Free;
        end;
      end
      else if Method = 'DELETE' then
        Response := Client.Delete(AParams.Url)
      else if Method = 'HEAD' then
        Response := Client.Head(AParams.Url)
      else
        Response := Client.Get(AParams.Url);

      var ElapsedMs := MilliSecondsBetween(Now, T0);

      var Body := '';
      if Method <> 'HEAD' then
        Body := Response.ContentAsString(TEncoding.UTF8);

      var Truncated := False;
      if Length(Body) > MaxChars then
      begin
        Body      := Copy(Body, 1, MaxChars);
        Truncated := True;
      end;

      // Selected response headers
      var RespHeaders := TJSONObject.Create;
      for var H in Response.Headers do
      begin
        var HName := LowerCase(H.Name);
        if (HName = 'content-type') or (HName = 'content-length') or
           (HName = 'server') or (HName = 'x-request-id') or
           (HName = 'date') or (HName = 'cache-control') then
          RespHeaders.AddPair(H.Name, H.Value);
      end;

      R := TJSONObject.Create;
      R.AddPair('url',              AParams.Url);
      R.AddPair('method',           Method);
      R.AddPair('status',           TJSONNumber.Create(Response.StatusCode));
      R.AddPair('ok',               TJSONBool.Create(Response.StatusCode < 400));
      R.AddPair('content_type',     Response.MimeType);
      R.AddPair('body_length',      TJSONNumber.Create(Length(Body)));
      R.AddPair('truncated',        TJSONBool.Create(Truncated));
      R.AddPair('elapsed_ms',       TJSONNumber.Create(ElapsedMs));
      R.AddPair('response_headers', RespHeaders);
      R.AddPair('body',             Body);

      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    finally
      Client.Free;
    end;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-fetch]: ' + E.Message)
        .Build;
  end;
end;

constructor TFetchTool.Create;
begin
  inherited;
  FName        := 'mcp-fetch';
  FDescription :=
    'General-purpose HTTP client. ' +
    'Supports GET, POST, PUT, PATCH, DELETE, HEAD. ' +
    'method: HTTP verb (default GET). ' +
    'body: request body for POST/PUT/PATCH. ' +
    'contentType: Content-Type header (default application/json). ' +
    'headers: extra request headers as JSON object. ' +
    'timeout: seconds before giving up (default 30). ' +
    'maxBodySize: max chars of response body to return (default 524288). ' +
    'Returns: status, ok, contentType, body, truncated, elapsed_ms, responseHeaders.';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-fetch',
    function: IAiMCPTool
    begin
      Result := TFetchTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-fetch] ready');
end;

end.
