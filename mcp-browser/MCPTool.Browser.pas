unit MCPTool.Browser;

{
  MCPTool.Browser  ·  mcp-browser

  Headless browser automation via Playwright (Python subprocess).
  Requires: Python 3.8+ with playwright installed
    pip install playwright && python -m playwright install chromium

  Operations:
    navigate   - Load a URL and return title + final URL.
    screenshot - Capture a full-page or element screenshot.
                 Returns base64 PNG or saves to outputPath.
    get_text   - Extract visible text from the page or a CSS selector.
    get_html   - Get the outer HTML of the page or a CSS selector.
    click      - Click on a CSS selector.
    fill       - Type text into an input/textarea.
    select     - Choose an option in a <select> element.
    eval       - Execute JavaScript in the page context.
    links      - Collect all <a href> links (optionally filtered by selector).
    pdf        - Save page as PDF (outputPath required).

  All operations accept:
    url        - Page URL to load before the action (optional for stateless ops)
    selector   - CSS selector (where applicable)
    timeout    - Max ms per action (default 30000)
    headless   - true (default) / false — show browser window
    waitUntil  - load|domcontentloaded|networkidle (default: load)

  Implementation: Delphi generates a Python script, runs it via subprocess,
  parses the JSON result from stdout. No Python4Delphi dependency.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.IOUtils,
  System.Diagnostics;

type

  // ── Parameters ──────────────────────────────────────────────────────────────

  TBrowserParams = class
  private
    FOperation:  string;
    FUrl:        string;
    FSelector:   string;
    FScript:     string;
    FValue:      string;
    FOutputPath: string;
    FWaitUntil:  string;
    FTimeout:    Integer;
    FHeadless:   Boolean;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: navigate, screenshot, get_text, get_html, click, fill, select, eval, links, pdf')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Page URL to navigate to before the action')]
    property Url:        string  read FUrl        write FUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('CSS selector for the target element')]
    property Selector:   string  read FSelector   write FSelector;

    [AiMCPOptional]
    [AiMCPSchemaDescription('eval: JavaScript code to execute; fill/select: value to set')]
    property Script:     string  read FScript     write FScript;

    [AiMCPOptional]
    [AiMCPSchemaDescription('fill/select: value to type or select')]
    property Value:      string  read FValue      write FValue;

    [AiMCPOptional]
    [AiMCPSchemaDescription('screenshot/pdf: file path to save the output')]
    property OutputPath: string  read FOutputPath write FOutputPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Event to wait after navigation: load (default), domcontentloaded, networkidle')]
    property WaitUntil:  string  read FWaitUntil  write FWaitUntil;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Timeout in ms per action (default 30000)')]
    property Timeout:    Integer read FTimeout    write FTimeout;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Run browser headless (default true). Set false to show the window')]
    property Headless:   Boolean read FHeadless   write FHeadless;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TBrowserTool = class(TAiMCPToolBase<TBrowserParams>)
  private
    function RunPython(const AScript: string; ATimeoutMs: Integer): string;
    function BuildScript(const P: TBrowserParams): string;
    function PyStr(const S: string): string;
    function PyBool(B: Boolean): string;
  protected
    function ExecuteWithParams(const AParams: TBrowserParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  uMakerAi.Utils.System,
  System.NetEncoding,
  System.Math,
  System.Threading,
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ELSE}
  Posix.Unistd,
{$ENDIF}
  System.SyncObjs;

{ TBrowserParams }

constructor TBrowserParams.Create;
begin
  inherited;
  FHeadless := True;
  FTimeout  := 30000;
end;

{ TBrowserTool }

function TBrowserTool.PyStr(const S: string): string;
begin
  Result := '"""' +
    S.Replace('\', '\\')
     .Replace('"""', '\"\"\"')
     .Replace(#13#10, '\n')
     .Replace(#10, '\n')
     .Replace(#13, '\n') +
    '"""';
end;

function TBrowserTool.PyBool(B: Boolean): string;
begin
  if B then Result := 'True' else Result := 'False';
end;

function TBrowserTool.BuildScript(const P: TBrowserParams): string;
var
  Op:        string;
  Timeout:   Integer;
  WaitUntil: string;
  Lines:     TStringBuilder;
begin
  Op        := LowerCase(Trim(P.Operation));
  Timeout   := P.Timeout;
  if Timeout <= 0 then Timeout := 30000;
  WaitUntil := LowerCase(Trim(P.WaitUntil));
  if WaitUntil = '' then WaitUntil := 'load';

  Lines := TStringBuilder.Create;
  try
    // Remove the script's own directory from sys.path to avoid shadowing stdlib
    Lines.AppendLine('import sys as _sys');
    Lines.AppendLine('if _sys.path and _sys.path[0] not in ("", None):');
    Lines.AppendLine('    try: _sys.path.remove(_sys.path[0])');
    Lines.AppendLine('    except: pass');
    Lines.AppendLine('import sys, json, base64');
    Lines.AppendLine('from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout');
    Lines.AppendLine('');
    Lines.AppendLine('def run():');
    Lines.AppendLine('    with sync_playwright() as pw:');
    Lines.AppendLine('        browser = pw.chromium.launch(headless=' + PyBool(P.Headless) + ')');
    Lines.AppendLine('        ctx = browser.new_context()');
    Lines.AppendLine('        page = ctx.new_page()');
    Lines.AppendLine('        page.set_default_timeout(' + IntToStr(Timeout) + ')');
    Lines.AppendLine('        result = {}');
    Lines.AppendLine('        try:');

    // navigate to URL if provided
    if P.Url <> '' then
    begin
      Lines.AppendLine('            resp = page.goto(' + PyStr(P.Url) + ', wait_until=' +
        PyStr(WaitUntil) + ', timeout=' + IntToStr(Timeout) + ')');
      Lines.AppendLine('            result["navigated_url"] = page.url');
      Lines.AppendLine('            result["status"] = resp.status if resp else 0');
    end;

    // operation-specific logic
    if Op = 'navigate' then
    begin
      Lines.AppendLine('            result["title"] = page.title()');
      Lines.AppendLine('            result["url"]   = page.url');
      Lines.AppendLine('            result["ok"]    = True');
    end

    else if Op = 'screenshot' then
    begin
      if P.OutputPath <> '' then
      begin
        if P.Selector <> '' then
          Lines.AppendLine('            page.locator(' + PyStr(P.Selector) + ').screenshot(path=' + PyStr(P.OutputPath) + ')')
        else
          Lines.AppendLine('            page.screenshot(path=' + PyStr(P.OutputPath) + ', full_page=True)');
        Lines.AppendLine('            result["path"] = ' + PyStr(P.OutputPath));
        Lines.AppendLine('            result["ok"]   = True');
      end
      else
      begin
        if P.Selector <> '' then
          Lines.AppendLine('            _img = page.locator(' + PyStr(P.Selector) + ').screenshot()')
        else
          Lines.AppendLine('            _img = page.screenshot(full_page=True)');
        Lines.AppendLine('            result["image_b64"] = base64.b64encode(_img).decode()');
        Lines.AppendLine('            result["ok"]        = True');
      end;
    end

    else if Op = 'get_text' then
    begin
      if P.Selector <> '' then
        Lines.AppendLine('            result["text"] = page.locator(' + PyStr(P.Selector) + ').inner_text()')
      else
        Lines.AppendLine('            result["text"] = page.inner_text("body")');
      Lines.AppendLine('            result["ok"] = True');
    end

    else if Op = 'get_html' then
    begin
      if P.Selector <> '' then
        Lines.AppendLine('            result["html"] = page.locator(' + PyStr(P.Selector) + ').inner_html()')
      else
        Lines.AppendLine('            result["html"] = page.content()');
      Lines.AppendLine('            result["ok"] = True');
    end

    else if Op = 'click' then
    begin
      if P.Selector = '' then
        raise Exception.Create('"selector" is required for click');
      Lines.AppendLine('            page.locator(' + PyStr(P.Selector) + ').click()');
      Lines.AppendLine('            result["ok"] = True');
    end

    else if Op = 'fill' then
    begin
      if P.Selector = '' then
        raise Exception.Create('"selector" is required for fill');
      Lines.AppendLine('            page.locator(' + PyStr(P.Selector) + ').fill(' + PyStr(P.Value) + ')');
      Lines.AppendLine('            result["ok"] = True');
    end

    else if Op = 'select' then
    begin
      if P.Selector = '' then
        raise Exception.Create('"selector" is required for select');
      Lines.AppendLine('            page.locator(' + PyStr(P.Selector) + ').select_option(' + PyStr(P.Value) + ')');
      Lines.AppendLine('            result["ok"] = True');
    end

    else if Op = 'eval' then
    begin
      if (P.Script = '') then
        raise Exception.Create('"script" is required for eval');
      Lines.AppendLine('            _eval_result = page.evaluate(' + PyStr(P.Script) + ')');
      Lines.AppendLine('            result["result"] = _eval_result');
      Lines.AppendLine('            result["ok"]     = True');
    end

    else if Op = 'links' then
    begin
      if P.Selector <> '' then
        Lines.AppendLine('            _els = page.locator(' + PyStr(P.Selector) + ' + " a").all()')
      else
        Lines.AppendLine('            _els = page.locator("a").all()');
      Lines.AppendLine('            _links = []');
      Lines.AppendLine('            for _el in _els:');
      Lines.AppendLine('                try:');
      Lines.AppendLine('                    _href = _el.get_attribute("href") or ""');
      Lines.AppendLine('                    _text = _el.inner_text().strip()');
      Lines.AppendLine('                    if _href: _links.append({"href": _href, "text": _text})');
      Lines.AppendLine('                except: pass');
      Lines.AppendLine('            result["links"] = _links');
      Lines.AppendLine('            result["count"] = len(_links)');
      Lines.AppendLine('            result["ok"]    = True');
    end

    else if Op = 'pdf' then
    begin
      if P.OutputPath = '' then
        raise Exception.Create('"output_path" is required for pdf');
      Lines.AppendLine('            page.pdf(path=' + PyStr(P.OutputPath) + ')');
      Lines.AppendLine('            result["path"] = ' + PyStr(P.OutputPath));
      Lines.AppendLine('            result["ok"]   = True');
    end

    else
      raise Exception.CreateFmt('Unknown operation "%s"', [Op]);

    Lines.AppendLine('        except PWTimeout as e:');
    Lines.AppendLine('            result["ok"]    = False');
    Lines.AppendLine('            result["error"] = "Timeout: " + str(e)');
    Lines.AppendLine('        except Exception as e:');
    Lines.AppendLine('            result["ok"]    = False');
    Lines.AppendLine('            result["error"] = str(e)');
    Lines.AppendLine('        finally:');
    Lines.AppendLine('            browser.close()');
    Lines.AppendLine('        print(json.dumps(result, ensure_ascii=False))');
    Lines.AppendLine('');
    Lines.AppendLine('run()');

    Result := Lines.ToString;
  finally
    Lines.Free;
  end;
end;

function TBrowserTool.RunPython(const AScript: string; ATimeoutMs: Integer): string;
var
  TmpFile: string;
  Proc:    TInteractiveProcessInfo;
  Buf:     array[0..8191] of AnsiChar;
  N:       Integer;
  SBOut, SBErr: TStringBuilder;
  SW:      TStopwatch;
begin
  TmpFile := TPath.Combine(TPath.GetTempPath, 'mcp_browser_' +
    IntToStr(TThread.CurrentThread.ThreadID) + '.py');
  TFile.WriteAllText(TmpFile, AScript, TEncoding.UTF8);
  try
    Proc := TUtilsSystem.StartInteractiveProcess('python "' + TmpFile + '"', '', nil);
    if Proc = nil then
      raise Exception.Create('Failed to start Python');
    try
      Proc.WriteInput(nil^, 0); // no stdin needed
{$IFDEF MSWINDOWS}
      if Proc.PipeHandles.InputWrite <> 0 then
      begin
        CloseHandle(Proc.PipeHandles.InputWrite);
        Proc.PipeHandles.InputWrite := 0;
      end;
{$ENDIF}
      SBOut := TStringBuilder.Create;
      SBErr := TStringBuilder.Create;
      try
        SW := TStopwatch.StartNew;
        repeat
          N := Proc.ReadOutput(Buf[0], SizeOf(Buf) - 1);
          if N > 0 then begin Buf[N] := #0; SBOut.Append(string(AnsiString(Buf))); end;
          N := Proc.ReadError(Buf[0], SizeOf(Buf) - 1);
          if N > 0 then begin Buf[N] := #0; SBErr.Append(string(AnsiString(Buf))); end;
          if not Proc.IsRunning then Break;
          if SW.ElapsedMilliseconds > ATimeoutMs then
          begin
            Proc.Kill;
            raise Exception.CreateFmt('Python timeout after %d ms', [ATimeoutMs]);
          end;
          Sleep(20);
        until False;
        // drain
        repeat
          N := Proc.ReadOutput(Buf[0], SizeOf(Buf) - 1);
          if N > 0 then begin Buf[N] := #0; SBOut.Append(string(AnsiString(Buf))); end;
        until N <= 0;
        repeat
          N := Proc.ReadError(Buf[0], SizeOf(Buf) - 1);
          if N > 0 then begin Buf[N] := #0; SBErr.Append(string(AnsiString(Buf))); end;
        until N <= 0;

        Result := Trim(SBOut.ToString);
        if (Result = '') and (SBErr.ToString <> '') then
          raise Exception.Create(Trim(SBErr.ToString));
      finally
        SBOut.Free;
        SBErr.Free;
      end;
    finally
      TUtilsSystem.StopInteractiveProcess(Proc);
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

function TBrowserTool.ExecuteWithParams(const AParams: TBrowserParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Script, RawJson: string;
  JResult: TJSONValue;
  Timeout: Integer;
begin
  try
    if AParams.Operation = '' then
      raise Exception.Create('"operation" is required');

    Timeout := AParams.Timeout;
    if Timeout <= 0 then Timeout := 30000;

    Script  := BuildScript(AParams);
    RawJson := RunPython(Script, Timeout + 10000); // extra margin for browser startup

    // Parse Python's JSON output
    JResult := TJSONObject.ParseJSONValue(RawJson);
    if JResult is TJSONObject then
    begin
      var JObj := JResult as TJSONObject;
      var ImgB64: string;
      if JObj.TryGetValue<string>('image_b64', ImgB64) then
      begin
        // Screenshot without output_path: return as proper MCP image content
        var ImgBytes := TNetEncoding.Base64.DecodeStringToBytes(ImgB64);
        var MS := TMemoryStream.Create;
        try
          MS.WriteBuffer(ImgBytes[0], Length(ImgBytes));
          Result := TAiMCPResponseBuilder.New
            .AddFileFromStream(MS, 'image.png', 'image/png')
            .Build;
        finally
          MS.Free;
        end;
      end
      else
        Result := TAiMCPResponseBuilder.New.AddText(RawJson).Build;
      JResult.Free;
    end
    else
    begin
      JResult.Free;
      Result := TAiMCPResponseBuilder.New.AddText(RawJson).Build;
    end;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message.Replace('\','\\').Replace('"','\"')
                   .Replace(#10,'\n').Replace(#13,'') + '"}')
        .Build;
  end;
end;

constructor TBrowserTool.Create;
begin
  inherited;
  FName        := 'mcp-browser';
  FDescription :=
    'Headless browser automation via Playwright/Chromium. ' +
    'Operations: navigate (load URL, get title), screenshot (full-page or element, returns base64 or saves to path), ' +
    'get_text (extract visible text), get_html (get page/element HTML), ' +
    'click (click CSS selector), fill (type into input), select (choose dropdown option), ' +
    'eval (run JavaScript, returns result), links (get all anchor links), pdf (save page as PDF). ' +
    'Params: url (page to load), selector (CSS), value (for fill/select), script (for eval), ' +
    'output_path (for screenshot/pdf), wait_until (load|domcontentloaded|networkidle), ' +
    'timeout (ms, default 30000), headless (default true).';
end;

// ── Registration ──────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-browser',
    function: IAiMCPTool
    begin
      Result := TBrowserTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-browser');
end;

end.
