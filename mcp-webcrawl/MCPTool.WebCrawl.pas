unit MCPTool.WebCrawl;

(*
  MCPTool.WebCrawl  -  mcp-webcrawl

  Fetch a URL and return its content as Markdown.

  Tools:
    fetch_url
      url         - URL to fetch (required)
      timeout_ms  - HTTP timeout in ms (optional, default 15000)
      user_agent  - User-Agent header (optional)

    fetch_url_js  [Windows only - requires chromedriver.exe + Chrome]
      url         - URL to render with headless Chrome (required)
      wait_ms     - extra wait after DOM ready in ms (optional, default 1500)
      driver_path - full path to chromedriver.exe (optional, searches PATH)

  Both tools return:
    { "success": true,  "url": "...", "title": "...", "markdown": "..." }
    { "success": false, "url": "...", "error": "reason" }
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  uWebCrawl,
  uExtract.Result;

{$IFDEF MSWINDOWS}
type

  TFetchJsParams = class
  private
    FUrl       : string;
    FWaitMs    : Integer;
    FDriverPath: string;
  public
    [AiMCPSchemaDescription(
      'URL to fetch and render with headless Chrome (JavaScript fully executed). ' +
      'Use for SPAs, React/Angular/Vue apps, and pages that load data via AJAX.')]
    property Url: string read FUrl write FUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription(
      'Extra milliseconds to wait after document.readyState = complete (default: 1500). ' +
      'Increase for SPAs that issue AJAX calls after initial load.')]
    property WaitMs: Integer read FWaitMs write FWaitMs;

    [AiMCPOptional]
    [AiMCPSchemaDescription(
      'Full path to chromedriver.exe. Leave empty to search the PATH.')]
    property DriverPath: string read FDriverPath write FDriverPath;
  end;
{$ENDIF}

type

  TFetchParams = class
  private
    FUrl      : string;
    FTimeoutMs: Integer;
    FUserAgent: string;
  public
    [AiMCPSchemaDescription(
      'URL to fetch (HTTP/HTTPS). Returns the page content as Markdown. ' +
      'Note: only static HTML is captured — JavaScript is NOT executed. ' +
      'For JS-rendered pages use fetch_url_js instead.')]
    property Url: string read FUrl write FUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('HTTP response timeout in milliseconds (default: 15000)')]
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Value for the User-Agent request header')]
    property UserAgent: string read FUserAgent write FUserAgent;
  end;

  TFetchTool = class(TAiMCPToolBase<TFetchParams>)
  protected
    function ExecuteWithParams(const AParams: TFetchParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

{$IFDEF MSWINDOWS}
  TFetchJsTool = class(TAiMCPToolBase<TFetchJsParams>)
  protected
    function ExecuteWithParams(const AParams: TFetchJsParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;
{$ENDIF}

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{$IFDEF MSWINDOWS}
uses uWebDriver;
{$ENDIF}

// ---------------------------------------------------------------------------
// fetch_url  (all platforms)
// ---------------------------------------------------------------------------

function TFetchTool.ExecuteWithParams(const AParams: TFetchParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Web : TWebCrawl;
  Conv: TConversionResult;
  R   : TJSONObject;
begin
  try
    if AParams.Url.Trim = '' then
      raise Exception.Create('"url" is required');

    Web := TWebCrawl.Create;
    try
      if AParams.TimeoutMs > 0 then
        Web.Timeout := AParams.TimeoutMs;
      if AParams.UserAgent <> '' then
        Web.UserAgent := AParams.UserAgent;
      Conv := Web.ConvertUrl(AParams.Url);
    finally
      Web.Free;
    end;

    R := TJSONObject.Create;
    R.AddPair('success', TJSONBool.Create(Conv.Success));
    R.AddPair('url',     AParams.Url);
    if Conv.Success then
    begin
      R.AddPair('title',    Conv.Title);
      R.AddPair('markdown', Conv.Markdown);
    end
    else
      R.AddPair('error', Conv.ErrorMessage);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [fetch_url]: ' + E.Message)
        .Build;
  end;
end;

constructor TFetchTool.Create;
begin
  inherited;
  FName        := 'fetch_url';
  FDescription :=
    'Fetch a URL via HTTP/HTTPS and return its content as Markdown. ' +
    'Follows redirects automatically. Selects converter from Content-Type: ' +
    'text/html → Markdown (headings, tables, links, code blocks); ' +
    'application/json → property/data table; text/csv → Markdown table; ' +
    'text/plain → pass-through. ' +
    'JavaScript is NOT executed — for JS-rendered pages use fetch_url_js. ' +
    'Params: url (required), timeout_ms (default 15000), user_agent.';
end;

// ---------------------------------------------------------------------------
// fetch_url_js  (Windows only — requires chromedriver.exe + Chrome)
// ---------------------------------------------------------------------------

{$IFDEF MSWINDOWS}

function TFetchJsTool.ExecuteWithParams(const AParams: TFetchJsParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  WD  : TWebDriver;
  Conv: TConversionResult;
  R   : TJSONObject;
begin
  try
    if AParams.Url.Trim = '' then
      raise Exception.Create('"url" is required');

    WD := TWebDriver.Create(AParams.DriverPath);
    try
      if AParams.WaitMs > 0 then
        WD.WaitMs := AParams.WaitMs;
      Conv := WD.ConvertUrl(AParams.Url);
    finally
      WD.Free;
    end;

    R := TJSONObject.Create;
    R.AddPair('success', TJSONBool.Create(Conv.Success));
    R.AddPair('url',     AParams.Url);
    if Conv.Success then
    begin
      R.AddPair('title',    Conv.Title);
      R.AddPair('markdown', Conv.Markdown);
    end
    else
      R.AddPair('error', Conv.ErrorMessage);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [fetch_url_js]: ' + E.Message)
        .Build;
  end;
end;

constructor TFetchJsTool.Create;
begin
  inherited;
  FName        := 'fetch_url_js';
  FDescription :=
    'Fetch a URL with a real headless Chrome browser (JavaScript fully executed). ' +
    'Use for SPAs (React, Angular, Vue), dashboards, and pages that load content via AJAX. ' +
    'Waits for document.readyState = complete, then an extra wait_ms for post-load AJAX. ' +
    'Requires: chromedriver.exe matching your Chrome version (https://googlechromelabs.github.io/chrome-for-testing/). ' +
    'Params: url (required), wait_ms (default 1500 — increase for heavy SPAs), driver_path (searches PATH if empty). ' +
    'Returns: markdown, title. Slower than fetch_url (~2–5 s); reuses Chrome session if called multiple times.';
end;

{$ENDIF}

// ---------------------------------------------------------------------------

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('fetch_url',
    function: IAiMCPTool
    begin
      Result := TFetchTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + fetch_url');

{$IFDEF MSWINDOWS}
  AServer.RegisterTool('fetch_url_js',
    function: IAiMCPTool
    begin
      Result := TFetchJsTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + fetch_url_js  (headless Chrome)');
{$ENDIF}
end;

end.
