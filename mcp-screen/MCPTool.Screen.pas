unit MCPTool.Screen;

(*
  MCPTool.Screen
  MCP tool: mcp-screen

  Capture the Windows desktop (full screen or a specific area) and save as PNG/JPEG/BMP.
  Uses pure Win32 GDI + Delphi VCL imaging units — no external dependencies.

  Operations:
    info         - primary and virtual screen dimensions, monitor count
    capture      - capture full virtual screen (all monitors) to a file
    capture_area - capture a specific rectangle to a file

  Output format is determined by the file extension in outputPath:
    .png  — PNG (lossless, default)
    .jpg / .jpeg — JPEG (lossy, smaller)
    .bmp  — Bitmap (uncompressed)
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.IOUtils,
  System.Types,
  Winapi.Windows,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Vcl.Imaging.jpeg;

type

  // ── Parameters ──────────────────────────────────────────────────────────────

  TScreenParams = class
  private
    FOperation:  string;
    FOutputPath: string;
    FX:          Integer;
    FY:          Integer;
    FWidth:      Integer;
    FHeight:     Integer;
  public
    [AiMCPSchemaDescription('Operation: info, capture, capture_area')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Output file path (.png, .jpg, .bmp) for capture/capture_area')]
    property OutputPath: string  read FOutputPath write FOutputPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Left coordinate for capture_area (pixels from primary screen left edge)')]
    property X:          Integer read FX          write FX;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Top coordinate for capture_area (pixels from primary screen top)')]
    property Y:          Integer read FY          write FY;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Width of capture area in pixels (required for capture_area)')]
    property Width:      Integer read FWidth      write FWidth;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Height of capture area in pixels (required for capture_area)')]
    property Height:     Integer read FHeight     write FHeight;
  end;

  // ── Tool ────────────────────────────────────────────────────────────────────

  TScreenTool = class(TAiMCPToolBase<TScreenParams>)
  private
    function CaptureRect(const ARect: TRect): Vcl.Graphics.TBitmap;
    procedure SaveBitmap(Bmp: Vcl.Graphics.TBitmap; const Path: string);
    function OpInfo(const P: TScreenParams): TJSONObject;
    function OpCapture(const P: TScreenParams): TJSONObject;
    function OpCaptureArea(const P: TScreenParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TScreenParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Capture helpers ──────────────────────────────────────────────────────────

function TScreenTool.CaptureRect(const ARect: TRect): Vcl.Graphics.TBitmap;
var
  ScreenDC: HDC;
  MemDC:    HDC;
  HBmp:     HBITMAP;
  OldBmp:   HBITMAP;
  W, H:     Integer;
begin
  W := ARect.Width;
  H := ARect.Height;
  if (W <= 0) or (H <= 0) then
    raise Exception.Create('Capture rectangle has zero or negative dimensions');

  Result             := Vcl.Graphics.TBitmap.Create;
  Result.Width       := W;
  Result.Height      := H;
  Result.PixelFormat := pf32bit;

  ScreenDC := GetDC(0);
  if ScreenDC = 0 then
    raise Exception.Create('GetDC failed');
  try
    MemDC := CreateCompatibleDC(ScreenDC);
    try
      HBmp   := CreateCompatibleBitmap(ScreenDC, W, H);
      OldBmp := SelectObject(MemDC, HBmp);
      try
        BitBlt(MemDC, 0, 0, W, H, ScreenDC, ARect.Left, ARect.Top, SRCCOPY);
        BitBlt(Result.Canvas.Handle, 0, 0, W, H, MemDC, 0, 0, SRCCOPY);
      finally
        SelectObject(MemDC, OldBmp);
        DeleteObject(HBmp);
      end;
    finally
      DeleteDC(MemDC);
    end;
  finally
    ReleaseDC(0, ScreenDC);
  end;
end;

procedure TScreenTool.SaveBitmap(Bmp: Vcl.Graphics.TBitmap; const Path: string);
var
  Ext:  string;
  PNG:  TPngImage;
  JPEG: TJpegImage;
begin
  Ext := LowerCase(ExtractFileExt(Path));
  TDirectory.CreateDirectory(ExtractFilePath(Path));

  if (Ext = '.jpg') or (Ext = '.jpeg') then
  begin
    JPEG := TJpegImage.Create;
    try
      JPEG.Assign(Bmp);
      JPEG.CompressionQuality := 90;
      JPEG.SaveToFile(Path);
    finally
      JPEG.Free;
    end;
  end
  else if Ext = '.bmp' then
    Bmp.SaveToFile(Path)
  else
  begin
    PNG := TPngImage.Create;
    try
      PNG.Assign(Bmp);
      PNG.SaveToFile(Path);
    finally
      PNG.Free;
    end;
  end;
end;

// ── Operations ───────────────────────────────────────────────────────────────

function TScreenTool.OpInfo(const P: TScreenParams): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('primary_width',  TJSONNumber.Create(GetSystemMetrics(SM_CXSCREEN)));
  Result.AddPair('primary_height', TJSONNumber.Create(GetSystemMetrics(SM_CYSCREEN)));
  Result.AddPair('virtual_left',   TJSONNumber.Create(GetSystemMetrics(SM_XVIRTUALSCREEN)));
  Result.AddPair('virtual_top',    TJSONNumber.Create(GetSystemMetrics(SM_YVIRTUALSCREEN)));
  Result.AddPair('virtual_width',  TJSONNumber.Create(GetSystemMetrics(SM_CXVIRTUALSCREEN)));
  Result.AddPair('virtual_height', TJSONNumber.Create(GetSystemMetrics(SM_CYVIRTUALSCREEN)));
  Result.AddPair('monitor_count',  TJSONNumber.Create(GetSystemMetrics(SM_CMONITORS)));
end;

function TScreenTool.OpCapture(const P: TScreenParams): TJSONObject;
var
  ARect: TRect;
  Bmp:   Vcl.Graphics.TBitmap;
begin
  if P.OutputPath = '' then
    raise Exception.Create('"outputPath" is required for capture');

  ARect.Left   := GetSystemMetrics(SM_XVIRTUALSCREEN);
  ARect.Top    := GetSystemMetrics(SM_YVIRTUALSCREEN);
  ARect.Right  := ARect.Left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
  ARect.Bottom := ARect.Top  + GetSystemMetrics(SM_CYVIRTUALSCREEN);

  Bmp := CaptureRect(ARect);
  try
    SaveBitmap(Bmp, P.OutputPath);
    Result := TJSONObject.Create;
    Result.AddPair('output',     P.OutputPath);
    Result.AddPair('width',      TJSONNumber.Create(Bmp.Width));
    Result.AddPair('height',     TJSONNumber.Create(Bmp.Height));
    Result.AddPair('size_bytes', TJSONNumber.Create(TFile.GetSize(P.OutputPath)));
  finally
    Bmp.Free;
  end;
end;

function TScreenTool.OpCaptureArea(const P: TScreenParams): TJSONObject;
var
  ARect: TRect;
  Bmp:   Vcl.Graphics.TBitmap;
begin
  if P.OutputPath = '' then
    raise Exception.Create('"outputPath" is required for capture_area');
  if (P.Width <= 0) or (P.Height <= 0) then
    raise Exception.Create('"width" and "height" must be positive');

  ARect := TRect.Create(P.X, P.Y, P.X + P.Width, P.Y + P.Height);

  Bmp := CaptureRect(ARect);
  try
    SaveBitmap(Bmp, P.OutputPath);
    Result := TJSONObject.Create;
    Result.AddPair('output',     P.OutputPath);
    Result.AddPair('x',         TJSONNumber.Create(P.X));
    Result.AddPair('y',         TJSONNumber.Create(P.Y));
    Result.AddPair('width',     TJSONNumber.Create(Bmp.Width));
    Result.AddPair('height',    TJSONNumber.Create(Bmp.Height));
    Result.AddPair('size_bytes',TJSONNumber.Create(TFile.GetSize(P.OutputPath)));
  finally
    Bmp.Free;
  end;
end;

// ── Main dispatch ────────────────────────────────────────────────────────────

function TScreenTool.ExecuteWithParams(const AParams: TScreenParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Data: TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));

    if      Op = 'info'         then Data := OpInfo(AParams)
    else if Op = 'capture'      then Data := OpCapture(AParams)
    else if Op = 'capture_area' then Data := OpCaptureArea(AParams)
    else raise Exception.CreateFmt(
      'Unknown operation: "%s". Valid: info, capture, capture_area', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(Data.ToJSON).Build;
    Data.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-screen]: ' + E.Message)
        .Build;
  end;
end;

constructor TScreenTool.Create;
begin
  inherited;
  FName        := 'mcp-screen';
  FDescription :=
    'Capture the Windows screen and save to a file. Win32 GDI + VCL imaging, no external deps. ' +
    'info: primary screen size, virtual screen bounds (all monitors combined), monitor count. ' +
    'capture: capture full virtual screen (all monitors) to outputPath. ' +
    'capture_area: capture rectangle (x, y, width, height) to outputPath. ' +
    'Format from extension: .png (lossless, default), .jpg (lossy), .bmp (uncompressed). ' +
    'Returns: output path, width, height, file size in bytes.';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-screen',
    function: IAiMCPTool
    begin
      Result := TScreenTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-screen] registered.');
end;

end.
