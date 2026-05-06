unit MCPTool.Compress;

{
  MCPTool.Compress  ·  mcp-compress

  ZIP compression/decompression using Delphi's built-in System.Zip.
  No external dependencies.

  Operations:
    list      - list entries in a ZIP file with sizes and compression ratios.
    compress  - create a ZIP from files or a folder.
    extract   - extract all or specific entries from a ZIP.
    add       - add a file to an existing ZIP (creates if not exists).
    info      - summary of a ZIP: entry count, total/compressed size, ratio.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.IOUtils,
  System.Zip,
  System.Math;

type

  TCompressParams = class
  private
    FOperation:  string;
    FPath:       string;
    FFiles:      string;
    FFolder:     string;
    FOutputDir:  string;
    FEntries:    string;
    FLevel:      Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list, compress, extract, add, info')]
    property Operation: string  read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Path to the ZIP file (source for list/extract/add/info, output for compress)')]
    property Path:      string  read FPath      write FPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('compress/add: comma-separated list of file paths to add')]
    property Files:     string  read FFiles     write FFiles;

    [AiMCPOptional]
    [AiMCPSchemaDescription('compress: folder to compress recursively (alternative to files)')]
    property Folder:    string  read FFolder    write FFolder;

    [AiMCPOptional]
    [AiMCPSchemaDescription('extract: output directory (default: same folder as ZIP)')]
    property OutputDir: string  read FOutputDir write FOutputDir;

    [AiMCPOptional]
    [AiMCPSchemaDescription('extract: comma-separated entry names to extract (empty = all)')]
    property Entries:   string  read FEntries   write FEntries;

    [AiMCPOptional]
    [AiMCPSchemaDescription('compress/add: compression level 0-9 (0=store, 1-9=deflate; default 6)')]
    property Level:     Integer read FLevel     write FLevel;
  end;

  TCompressTool = class(TAiMCPToolBase<TCompressParams>)
  private
    function LevelToComp(Level: Integer): TZipCompression;
    function DoList(const P: TCompressParams): TJSONObject;
    function DoInfo(const P: TCompressParams): TJSONObject;
    function DoCompress(const P: TCompressParams): TJSONObject;
    function DoExtract(const P: TCompressParams): TJSONObject;
    function DoAdd(const P: TCompressParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TCompressParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ TCompressParams }

constructor TCompressParams.Create;
begin
  inherited;
  FLevel := 6;
end;

{ TCompressTool }

function TCompressTool.LevelToComp(Level: Integer): TZipCompression;
begin
  if Level = 0 then
    Result := zcStored
  else
    Result := zcDeflate;
end;

function TCompressTool.DoList(const P: TCompressParams): TJSONObject;
var
  Zip:     TZipFile;
  Entries: TJSONArray;
  Entry:   TJSONObject;
  LH:      TZipHeader;
  i:       Integer;
  Ratio:   Double;
begin
  Zip := TZipFile.Create;
  try
    Zip.Open(P.Path, zmRead);
    Entries := TJSONArray.Create;
    for i := 0 to Zip.FileCount - 1 do
    begin
      LH := Zip.FileInfo[i];
      Entry := TJSONObject.Create;
      Entry.AddPair('name',            string(LH.FileName));
      Entry.AddPair('size',            TJSONNumber.Create(LH.UncompressedSize));
      Entry.AddPair('compressed_size', TJSONNumber.Create(LH.CompressedSize));
      if LH.UncompressedSize > 0 then
        Ratio := 1.0 - LH.CompressedSize / LH.UncompressedSize
      else
        Ratio := 0;
      Entry.AddPair('ratio',           TJSONNumber.Create(Round(Ratio * 1000) / 10));
      Entry.AddPair('crc32',           TJSONNumber.Create(LH.CRC32));
      Entries.Add(Entry);
    end;
    Result := TJSONObject.Create;
    Result.AddPair('entries', Entries);
    Result.AddPair('count',   TJSONNumber.Create(Zip.FileCount));
    Result.AddPair('ok',      TJSONTrue.Create);
  finally
    Zip.Free;
  end;
end;

function TCompressTool.DoInfo(const P: TCompressParams): TJSONObject;
var
  Zip:           TZipFile;
  LH:            TZipHeader;
  i:             Integer;
  TotalSize:     Int64;
  CompressedSz:  Int64;
  FileSize:      Int64;
  Ratio:         Double;
  Count:         Integer;
  FS:            TFileStream;
begin
  TotalSize    := 0;
  CompressedSz := 0;
  Count        := 0;

  Zip := TZipFile.Create;
  try
    Zip.Open(P.Path, zmRead);
    Count := Zip.FileCount;
    for i := 0 to Zip.FileCount - 1 do
    begin
      LH           := Zip.FileInfo[i];
      TotalSize    := TotalSize    + LH.UncompressedSize;
      CompressedSz := CompressedSz + LH.CompressedSize;
    end;
  finally
    Zip.Free;
  end;

  FS := TFileStream.Create(P.Path, fmOpenRead or fmShareDenyNone);
  try
    FileSize := FS.Size;
  finally
    FS.Free;
  end;

  if TotalSize > 0 then
    Ratio := 1.0 - CompressedSz / TotalSize
  else
    Ratio := 0;

  Result := TJSONObject.Create;
  Result.AddPair('path',            P.Path);
  Result.AddPair('zip_size',        TJSONNumber.Create(FileSize));
  Result.AddPair('entry_count',     TJSONNumber.Create(Count));
  Result.AddPair('total_size',      TJSONNumber.Create(TotalSize));
  Result.AddPair('compressed_size', TJSONNumber.Create(CompressedSz));
  Result.AddPair('ratio_pct',       TJSONNumber.Create(Round(Ratio * 1000) / 10));
  Result.AddPair('ok',              TJSONTrue.Create);
end;

function TCompressTool.DoCompress(const P: TCompressParams): TJSONObject;
var
  Zip:        TZipFile;
  FilePaths:  TArray<string>;
  Added:      TJSONArray;
  AddedCount: Integer;
  OutPath:    string;
  FolderBase: string;
  F:          string;
  EntryName:  string;
  ZipSize:    Int64;
  FS:         TFileStream;
begin
  OutPath := P.Path;
  if OutPath = '' then
    raise Exception.Create('"path" (output ZIP path) is required for compress');

  if (P.Files = '') and (P.Folder = '') then
    raise Exception.Create('"files" or "folder" is required for compress');

  Added      := TJSONArray.Create;
  AddedCount := 0;

  Zip := TZipFile.Create;
  try
    Zip.Open(OutPath, zmWrite);

    if P.Files <> '' then
    begin
      FilePaths := P.Files.Split([',']);
      for F in FilePaths do
      begin
        var FTrim := Trim(F);
        if TFile.Exists(FTrim) then
        begin
          Zip.Add(FTrim, TPath.GetFileName(FTrim), LevelToComp(P.Level));
          Added.Add(TPath.GetFileName(FTrim));
          Inc(AddedCount);
        end;
      end;
    end;

    if (P.Folder <> '') and TDirectory.Exists(P.Folder) then
    begin
      FolderBase := TPath.GetFullPath(P.Folder);
      if not FolderBase.EndsWith(PathDelim) then
        FolderBase := FolderBase + PathDelim;
      for F in TDirectory.GetFiles(P.Folder, '*', TSearchOption.soAllDirectories) do
      begin
        EntryName := StringReplace(F.Substring(Length(FolderBase)),
          '\', '/', [rfReplaceAll]);
        Zip.Add(F, EntryName, LevelToComp(P.Level));
        Added.Add(EntryName);
        Inc(AddedCount);
      end;
    end;
  finally
    Zip.Free;
  end;

  ZipSize := 0;
  FS := TFileStream.Create(OutPath, fmOpenRead or fmShareDenyNone);
  try
    ZipSize := FS.Size;
  finally
    FS.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('path',     OutPath);
  Result.AddPair('added',    Added);
  Result.AddPair('count',    TJSONNumber.Create(AddedCount));
  Result.AddPair('zip_size', TJSONNumber.Create(ZipSize));
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function TCompressTool.DoExtract(const P: TCompressParams): TJSONObject;
var
  Zip:       TZipFile;
  OutDir:    string;
  Extracted: TJSONArray;
  Count:     Integer;
  EntryList: TArray<string>;
  HasFilter: Boolean;
  LH:        TZipHeader;
  i:         Integer;
  ETrim:     string;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for extract');

  OutDir := P.OutputDir;
  if OutDir = '' then
    OutDir := TPath.GetDirectoryName(P.Path);
  TDirectory.CreateDirectory(OutDir);

  if P.Entries <> '' then
    EntryList := P.Entries.Split([','])
  else
    EntryList := nil;
  HasFilter := Length(EntryList) > 0;

  Extracted := TJSONArray.Create;
  Count     := 0;

  Zip := TZipFile.Create;
  try
    Zip.Open(P.Path, zmRead);

    if not HasFilter then
    begin
      Zip.ExtractAll(OutDir);
      Count := Zip.FileCount;
      for i := 0 to Zip.FileCount - 1 do
      begin
        LH := Zip.FileInfo[i];
        Extracted.Add(string(LH.FileName));
      end;
    end
    else
    begin
      for var Entry in EntryList do
      begin
        ETrim := Trim(Entry);
        Zip.Extract(ETrim, OutDir);
        Extracted.Add(ETrim);
        Inc(Count);
      end;
    end;
  finally
    Zip.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('output_dir', OutDir);
  Result.AddPair('extracted',  Extracted);
  Result.AddPair('count',      TJSONNumber.Create(Count));
  Result.AddPair('ok',         TJSONTrue.Create);
end;

function TCompressTool.DoAdd(const P: TCompressParams): TJSONObject;
var
  Zip:       TZipFile;
  FilePaths: TArray<string>;
  Added:     TJSONArray;
  Count:     Integer;
  Mode:      TZipMode;
  F:         string;
begin
  if P.Path  = '' then raise Exception.Create('"path" is required for add');
  if P.Files = '' then raise Exception.Create('"files" is required for add');

  if TFile.Exists(P.Path) then
    Mode := zmReadWrite
  else
    Mode := zmWrite;

  Added := TJSONArray.Create;
  Count := 0;

  Zip := TZipFile.Create;
  try
    Zip.Open(P.Path, Mode);
    FilePaths := P.Files.Split([',']);
    for F in FilePaths do
    begin
      var FTrim := Trim(F);
      if TFile.Exists(FTrim) then
      begin
        Zip.Add(FTrim, TPath.GetFileName(FTrim), LevelToComp(P.Level));
        Added.Add(TPath.GetFileName(FTrim));
        Inc(Count);
      end;
    end;
  finally
    Zip.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('path',  P.Path);
  Result.AddPair('added', Added);
  Result.AddPair('count', TJSONNumber.Create(Count));
  Result.AddPair('ok',    TJSONTrue.Create);
end;

function TCompressTool.ExecuteWithParams(const AParams: TCompressParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if Op <> 'compress' then
    begin
      if AParams.Path = '' then raise Exception.Create('"path" is required');
      if (Op = 'list') or (Op = 'info') or (Op = 'extract') then
      begin
        if not TFile.Exists(AParams.Path) then
          raise Exception.CreateFmt('File not found: %s', [AParams.Path]);
      end;
    end;

    if      Op = 'list'     then R := DoList(AParams)
    else if Op = 'info'     then R := DoInfo(AParams)
    else if Op = 'compress' then R := DoCompress(AParams)
    else if Op = 'extract'  then R := DoExtract(AParams)
    else if Op = 'add'      then R := DoAdd(AParams)
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

constructor TCompressTool.Create;
begin
  inherited;
  FName        := 'mcp-compress';
  FDescription :=
    'ZIP compression and decompression using Delphi built-in System.Zip. ' +
    'Operations: ' +
    'list (entries with sizes and compression ratio), ' +
    'info (summary: entry count, total size, compressed size, ratio), ' +
    'compress (create ZIP from files list or folder; params: path, files or folder, level 0-9), ' +
    'extract (extract to output_dir; params: path, output_dir, entries to extract or all), ' +
    'add (add files to existing or new ZIP; params: path, files).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-compress',
    function: IAiMCPTool
    begin
      Result := TCompressTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-compress] ready');
end;

end.
