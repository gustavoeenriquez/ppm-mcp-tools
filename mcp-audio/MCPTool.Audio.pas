unit MCPTool.Audio;

(*
  MCPTool.Audio
  MCP tool: mcp-audio

  100% Delphi, no DLLs.
  Supported input formats: WAV, FLAC, Ogg Vorbis, Ogg Opus.

  Operations:
    info           - format, sample rate, channels, bit depth, duration, bitrate, file size
    convert_to_wav - decode any supported format to WAV (16/24/32-bit PCM output)
    waveform       - amplitude envelope: array of peak values per time bin

  Parameters:
    operation   (required) - info, convert_to_wav, waveform
    filePath    - input audio file path
    outputPath  - output file path (for convert_to_wav)
    bins        - number of amplitude bins for waveform (default 100, max 1000)
    bitDepth    - output bit depth for convert_to_wav: 16, 24 or 32 (default 16)
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.Math,
  AudioTypes,
  AudioCodec,
  WAVWriter;

type

  // ── Parameters ──────────────────────────────────────────────────────────────

  TAudioParams = class
  private
    FOperation:  string;
    FFilePath:   string;
    FOutputPath: string;
    FBins:       Integer;
    FBitDepth:   Integer;
  public
    [AiMCPSchemaDescription('Operation: info, convert_to_wav, waveform')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Input audio file path (WAV, FLAC, Ogg Vorbis, Ogg Opus)')]
    property FilePath:   string  read FFilePath   write FFilePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Output file path for convert_to_wav')]
    property OutputPath: string  read FOutputPath write FOutputPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of amplitude bins for waveform (default 100, max 1000)')]
    property Bins:       Integer read FBins       write FBins;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Output bit depth for convert_to_wav: 16, 24 or 32 (default 16)')]
    property BitDepth:   Integer read FBitDepth   write FBitDepth;
  end;

  // ── Tool ────────────────────────────────────────────────────────────────────

  TAudioTool = class(TAiMCPToolBase<TAudioParams>)
  private
    function LoadDecoder(const APath: string): IAudioDecoder;
    function FormatName(F: TAudioFormat): string;

    function OpInfo(const P: TAudioParams): TJSONObject;
    function OpConvertToWav(const P: TAudioParams): TJSONObject;
    function OpWaveform(const P: TAudioParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TAudioParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Helpers ─────────────────────────────────────────────────────────────────

function TAudioTool.LoadDecoder(const APath: string): IAudioDecoder;
begin
  if APath = '' then
    raise Exception.Create('"filePath" is required');
  if not TFile.Exists(APath) then
    raise Exception.CreateFmt('File not found: "%s"', [APath]);

  Result := CreateAudioDecoderFromFile(APath);
  if Result = nil then
    raise Exception.Create(
      'Unsupported or unreadable audio format. Supported: WAV, FLAC, Ogg Vorbis, Ogg Opus');
  if not Result.Ready then
    raise Exception.Create('Audio file could not be parsed (bad header or corrupted data)');
end;

function TAudioTool.FormatName(F: TAudioFormat): string;
begin
  case F of
    afWAV:    Result := 'WAV';
    afFLAC:   Result := 'FLAC';
    afVorbis: Result := 'Ogg Vorbis';
    afOpus:   Result := 'Ogg Opus';
    afMP3:    Result := 'MP3';
  else
    Result := 'Unknown';
  end;
end;

// ── Operations ───────────────────────────────────────────────────────────────

function TAudioTool.OpInfo(const P: TAudioParams): TJSONObject;
var
  Dec:    IAudioDecoder;
  Info:   TAudioInfo;
  FSize:  Int64;
begin
  Dec   := LoadDecoder(P.FilePath);
  Info  := Dec.Info;
  FSize := TFile.GetSize(P.FilePath);

  Result := TJSONObject.Create;
  Result.AddPair('file',         P.FilePath);
  Result.AddPair('file_size',    TJSONNumber.Create(FSize));
  Result.AddPair('format',       FormatName(Info.Format));
  Result.AddPair('sample_rate',  TJSONNumber.Create(Int64(Info.SampleRate)));
  Result.AddPair('channels',     TJSONNumber.Create(Info.Channels));
  Result.AddPair('bit_depth',    TJSONNumber.Create(Info.BitDepth));
  Result.AddPair('is_float',     TJSONBool.Create(Info.IsFloat));
  Result.AddPair('duration_ms',  TJSONNumber.Create(Info.DurationMs));
  Result.AddPair('bitrate_kbps', TJSONNumber.Create(Int64(Info.BitRate)));

  if Info.DurationMs > 0 then
    Result.AddPair('duration_sec', TJSONNumber.Create(Info.DurationMs / 1000.0));
end;

function TAudioTool.OpConvertToWav(const P: TAudioParams): TJSONObject;
var
  Dec:    IAudioDecoder;
  Info:   TAudioInfo;
  Writer: TWAVWriter;
  Buf:    TAudioBuffer;
  OutFmt: TWAVOutputFormat;
  BD:     Integer;
  Frames: Int64;
begin
  if P.OutputPath = '' then
    raise Exception.Create('"outputPath" is required for convert_to_wav');

  Dec  := LoadDecoder(P.FilePath);
  Info := Dec.Info;

  BD := P.BitDepth;
  if BD = 0 then BD := 16;
  case BD of
    24: OutFmt := woPCM24;
    32: OutFmt := woPCM32;
  else
    OutFmt := woPCM16;
    BD     := 16;
  end;

  Writer := TWAVWriter.Create(P.OutputPath, Info.SampleRate, Info.Channels, OutFmt);
  try
    Frames := 0;
    while Dec.Decode(Buf) = adrOK do
    begin
      if (Buf <> nil) and (Length(Buf) > 0) and (Length(Buf[0]) > 0) then
      begin
        Writer.WriteSamples(Buf);
        Inc(Frames, Length(Buf[0]));
      end;
    end;
    Writer.Finalize;
  finally
    Writer.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('input',       P.FilePath);
  Result.AddPair('output',      P.OutputPath);
  Result.AddPair('format',      FormatName(Info.Format) + ' → WAV PCM' + IntToStr(BD));
  Result.AddPair('sample_rate', TJSONNumber.Create(Int64(Info.SampleRate)));
  Result.AddPair('channels',    TJSONNumber.Create(Info.Channels));
  Result.AddPair('bit_depth',   TJSONNumber.Create(BD));
  Result.AddPair('frames',      TJSONNumber.Create(Frames));
  Result.AddPair('file_size',   TJSONNumber.Create(TFile.GetSize(P.OutputPath)));
end;

function TAudioTool.OpWaveform(const P: TAudioParams): TJSONObject;
var
  Dec:         IAudioDecoder;
  Info:        TAudioInfo;
  Buf:         TAudioBuffer;
  BlockPeaks:  TArray<Single>;
  BlockCount:  Integer;
  BinCount:    Integer;
  Peak:        Single;
  ch, s:       Integer;
  Arr:         TJSONArray;
  BlocksPerBin: Integer;
  b, Start, Finish: Integer;
  BinPeak:     Single;
begin
  Dec  := LoadDecoder(P.FilePath);
  Info := Dec.Info;

  BinCount := P.Bins;
  if BinCount <= 0 then BinCount := 100;
  if BinCount > 1000 then BinCount := 1000;

  // Phase 1: collect per-decode-block peak amplitudes
  SetLength(BlockPeaks, 0);
  BlockCount := 0;

  while Dec.Decode(Buf) = adrOK do
  begin
    if (Buf = nil) or (Length(Buf) = 0) or (Length(Buf[0]) = 0) then
      Continue;

    Peak := 0;
    for ch := 0 to Length(Buf) - 1 do
      for s := 0 to Length(Buf[ch]) - 1 do
        if Abs(Buf[ch][s]) > Peak then
          Peak := Abs(Buf[ch][s]);

    if BlockCount >= Length(BlockPeaks) then
      SetLength(BlockPeaks, Max(BlockCount + 1, BlockCount * 2 + 64));
    BlockPeaks[BlockCount] := Peak;
    Inc(BlockCount);
  end;

  // Phase 2: group blocks into bins
  Arr := TJSONArray.Create;

  if BlockCount = 0 then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('file',       P.FilePath);
    Result.AddPair('format',     FormatName(Info.Format));
    Result.AddPair('bins',       TJSONNumber.Create(0));
    Result.AddPair('waveform',   Arr);
    Exit;
  end;

  BlocksPerBin := Max(1, (BlockCount + BinCount - 1) div BinCount);
  BinCount     := (BlockCount + BlocksPerBin - 1) div BlocksPerBin;

  for b := 0 to BinCount - 1 do
  begin
    Start  := b * BlocksPerBin;
    Finish := Min(Start + BlocksPerBin - 1, BlockCount - 1);
    BinPeak := 0;
    for s := Start to Finish do
      if BlockPeaks[s] > BinPeak then
        BinPeak := BlockPeaks[s];
    Arr.AddElement(TJSONNumber.Create(RoundTo(BinPeak, -4)));
  end;

  Result := TJSONObject.Create;
  Result.AddPair('file',        P.FilePath);
  Result.AddPair('format',      FormatName(Info.Format));
  Result.AddPair('sample_rate', TJSONNumber.Create(Int64(Info.SampleRate)));
  Result.AddPair('channels',    TJSONNumber.Create(Info.Channels));
  Result.AddPair('bins',        TJSONNumber.Create(BinCount));
  Result.AddPair('waveform',    Arr);
end;

// ── Main dispatch ────────────────────────────────────────────────────────────

function TAudioTool.ExecuteWithParams(const AParams: TAudioParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Data: TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));

    if      Op = 'info'           then Data := OpInfo(AParams)
    else if Op = 'convert_to_wav' then Data := OpConvertToWav(AParams)
    else if Op = 'waveform'       then Data := OpWaveform(AParams)
    else raise Exception.CreateFmt(
      'Unknown operation: "%s". Valid: info, convert_to_wav, waveform', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(Data.ToJSON).Build;
    Data.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-audio]: ' + E.Message)
        .Build;
  end;
end;

constructor TAudioTool.Create;
begin
  inherited;
  FName        := 'mcp-audio';
  FDescription :=
    'Read and convert audio files. 100% Delphi, no external DLLs. ' +
    'Supported input: WAV, FLAC, Ogg Vorbis, Ogg Opus. ' +
    'info: format, sample rate, channels, bit depth, duration, bitrate. ' +
    'convert_to_wav: decode any supported format to WAV (16/24/32-bit PCM). ' +
    'waveform: amplitude envelope as array of peak values per time bin.';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-audio',
    function: IAiMCPTool
    begin
      Result := TAudioTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-audio] registered.');
end;

end.
