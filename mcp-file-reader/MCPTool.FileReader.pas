// Nombre: Gustavo Enríquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit MCPTool.FileReader;

{
  MCPTool.FileReader
  MCP tool: mcp-files

  Operations:
    read   - read file content (utf8 or ansi, up to maxSize bytes)
    write  - create or overwrite a text file
    append - append text to a file
    list   - list directory entries (pattern, recursive)
    exists - check if a path exists (file or directory)
    delete - delete a file or empty directory
    move   - move/rename a file or directory
    copy   - copy a file to a new location
    mkdir  - create a directory (all parents created as needed)
    info   - file/directory metadata: size, dates, type
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Classes,
  System.Math,
  System.Types;

type

  // ── Parameters ─────────────────────────────────────────────────────────────

  TFileReaderParams = class
  private
    FOperation:   string;
    FPath:        string;
    FContent:     string;
    FDestination: string;
    FPattern:     string;
    FRecursive:   Boolean;
    FMaxSize:     Integer;
    FEncoding:    string;
  public
    [AiMCPSchemaDescription('Operation: read, write, append, list, exists, delete, move, copy, mkdir, info')]
    property Operation: string read FOperation write FOperation;

    [AiMCPSchemaDescription('File or directory path')]
    property Path: string read FPath write FPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Text content for write/append operations')]
    property Content: string read FContent write FContent;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Destination path for move/copy operations')]
    property Destination: string read FDestination write FDestination;

    [AiMCPOptional]
    [AiMCPSchemaDescription('File glob pattern for list (e.g. *.txt). Default: *')]
    property Pattern: string read FPattern write FPattern;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Recurse into subdirectories for list (default: false)')]
    property Recursive: Boolean read FRecursive write FRecursive;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum bytes to read (default: 1048576 = 1 MB)')]
    property MaxSize: Integer read FMaxSize write FMaxSize;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Text encoding: utf8, ansi (default: utf8)')]
    property Encoding: string read FEncoding write FEncoding;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TFileReaderTool = class(TAiMCPToolBase<TFileReaderParams>)
  private
    function GetEncoding(const Name: string): TEncoding;
    function GetFileSize(const APath: string): Int64;
  protected
    function ExecuteWithParams(const AParams: TFileReaderParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Helpers ─────────────────────────────────────────────────────────────────

function TFileReaderTool.GetEncoding(const Name: string): TEncoding;
begin
  if LowerCase(Trim(Name)) = 'ansi' then
    Result := TEncoding.ANSI
  else
    Result := TEncoding.UTF8;
end;

function TFileReaderTool.GetFileSize(const APath: string): Int64;
var
  SR: TSearchRec;
begin
  Result := -1;
  if FindFirst(APath, faAnyFile, SR) = 0 then
  begin
    Result := SR.Size;
    FindClose(SR);
  end;
end;

// ── Main execution ──────────────────────────────────────────────────────────

function TFileReaderTool.ExecuteWithParams(const AParams: TFileReaderParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Path: string;
  R:    TJSONObject;
begin
  try
    Op   := LowerCase(Trim(AParams.Operation));
    Path := AParams.Path;

    // ── read ───────────────────────────────────────────────────────────────
    if Op = 'read' then
    begin
      if not TFile.Exists(Path) then
        raise Exception.CreateFmt('File not found: %s', [Path]);

      var MaxBytes   := AParams.MaxSize;
      if MaxBytes <= 0 then MaxBytes := 1048576;
      var ActualSize := GetFileSize(Path);
      var ReadSize   := Min(ActualSize, Int64(MaxBytes));

      var Bytes: TBytes;
      SetLength(Bytes, ReadSize);
      if ReadSize > 0 then
      begin
        var FS := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
        try
          FS.ReadBuffer(Bytes[0], ReadSize);
        finally
          FS.Free;
        end;
      end;

      R := TJSONObject.Create;
      R.AddPair('path',      Path);
      R.AddPair('size',      TJSONNumber.Create(ActualSize));
      R.AddPair('read',      TJSONNumber.Create(ReadSize));
      R.AddPair('truncated', TJSONBool.Create(ActualSize > MaxBytes));
      R.AddPair('content',   GetEncoding(AParams.Encoding).GetString(Bytes));
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── write ──────────────────────────────────────────────────────────────
    else if Op = 'write' then
    begin
      var Dir := TPath.GetDirectoryName(Path);
      if (Dir <> '') and not TDirectory.Exists(Dir) then
        TDirectory.CreateDirectory(Dir);
      TFile.WriteAllText(Path, AParams.Content, GetEncoding(AParams.Encoding));

      R := TJSONObject.Create;
      R.AddPair('path',    Path);
      R.AddPair('written', TJSONNumber.Create(Length(AParams.Content)));
      R.AddPair('ok',      TJSONBool.Create(True));
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── append ─────────────────────────────────────────────────────────────
    else if Op = 'append' then
    begin
      var SW := TStreamWriter.Create(Path, True, GetEncoding(AParams.Encoding));
      try
        SW.Write(AParams.Content);
      finally
        SW.Free;
      end;

      R := TJSONObject.Create;
      R.AddPair('path',     Path);
      R.AddPair('appended', TJSONNumber.Create(Length(AParams.Content)));
      R.AddPair('size',     TJSONNumber.Create(GetFileSize(Path)));
      R.AddPair('ok',       TJSONBool.Create(True));
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── list ───────────────────────────────────────────────────────────────
    else if Op = 'list' then
    begin
      if not TDirectory.Exists(Path) then
        raise Exception.CreateFmt('Directory not found: %s', [Path]);

      var Pat := AParams.Pattern;
      if Pat = '' then Pat := '*';

      var SearchOpt := TSearchOption.soTopDirectoryOnly;
      if AParams.Recursive then
        SearchOpt := TSearchOption.soAllDirectories;

      var Files := TDirectory.GetFiles(Path, Pat, SearchOpt);
      var Dirs  := TDirectory.GetDirectories(Path, '*', TSearchOption.soTopDirectoryOnly);

      var Items := TJSONArray.Create;
      for var D in Dirs do
      begin
        var Item := TJSONObject.Create;
        Item.AddPair('name', TPath.GetFileName(D));
        Item.AddPair('type', 'directory');
        Item.AddPair('path', D);
        Items.AddElement(Item);
      end;
      for var F in Files do
      begin
        var Item := TJSONObject.Create;
        Item.AddPair('name', TPath.GetFileName(F));
        Item.AddPair('type', 'file');
        Item.AddPair('path', F);
        Item.AddPair('size', TJSONNumber.Create(GetFileSize(F)));
        Items.AddElement(Item);
      end;

      R := TJSONObject.Create;
      R.AddPair('path',    Path);
      R.AddPair('count',   TJSONNumber.Create(Items.Count));
      R.AddPair('entries', Items);
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── exists ─────────────────────────────────────────────────────────────
    else if Op = 'exists' then
    begin
      var IsFile := TFile.Exists(Path);
      var IsDir  := TDirectory.Exists(Path);

      R := TJSONObject.Create;
      R.AddPair('path',   Path);
      R.AddPair('exists', TJSONBool.Create(IsFile or IsDir));
      if IsFile     then R.AddPair('type', 'file')
      else if IsDir then R.AddPair('type', 'directory')
      else               R.AddPair('type', 'not_found');
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── delete ─────────────────────────────────────────────────────────────
    else if Op = 'delete' then
    begin
      if TFile.Exists(Path) then
      begin
        TFile.Delete(Path);
        R := TJSONObject.Create;
        R.AddPair('path', Path);
        R.AddPair('type', 'file');
        R.AddPair('ok',   TJSONBool.Create(True));
      end
      else if TDirectory.Exists(Path) then
      begin
        TDirectory.Delete(Path);
        R := TJSONObject.Create;
        R.AddPair('path', Path);
        R.AddPair('type', 'directory');
        R.AddPair('ok',   TJSONBool.Create(True));
      end
      else
        raise Exception.CreateFmt('Path not found: %s', [Path]);

      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── move ───────────────────────────────────────────────────────────────
    else if Op = 'move' then
    begin
      if AParams.Destination = '' then
        raise Exception.Create('"destination" is required for move');
      if TFile.Exists(Path) then
        TFile.Move(Path, AParams.Destination)
      else if TDirectory.Exists(Path) then
        TDirectory.Move(Path, AParams.Destination)
      else
        raise Exception.CreateFmt('Source not found: %s', [Path]);

      R := TJSONObject.Create;
      R.AddPair('from', Path);
      R.AddPair('to',   AParams.Destination);
      R.AddPair('ok',   TJSONBool.Create(True));
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── copy ───────────────────────────────────────────────────────────────
    else if Op = 'copy' then
    begin
      if AParams.Destination = '' then
        raise Exception.Create('"destination" is required for copy');
      if not TFile.Exists(Path) then
        raise Exception.CreateFmt('Source file not found: %s', [Path]);
      TFile.Copy(Path, AParams.Destination, True);

      R := TJSONObject.Create;
      R.AddPair('from', Path);
      R.AddPair('to',   AParams.Destination);
      R.AddPair('size', TJSONNumber.Create(GetFileSize(AParams.Destination)));
      R.AddPair('ok',   TJSONBool.Create(True));
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── mkdir ──────────────────────────────────────────────────────────────
    else if Op = 'mkdir' then
    begin
      TDirectory.CreateDirectory(Path);

      R := TJSONObject.Create;
      R.AddPair('path', Path);
      R.AddPair('ok',   TJSONBool.Create(True));
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── info ───────────────────────────────────────────────────────────────
    else if Op = 'info' then
    begin
      R := TJSONObject.Create;
      R.AddPair('path', Path);
      R.AddPair('name', TPath.GetFileName(Path));

      if TFile.Exists(Path) then
      begin
        R.AddPair('type',      'file');
        R.AddPair('size',      TJSONNumber.Create(GetFileSize(Path)));
        R.AddPair('extension', TPath.GetExtension(Path));
        R.AddPair('modified',  FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"',
          TFile.GetLastWriteTimeUtc(Path)));
        R.AddPair('created',   FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"',
          TFile.GetCreationTimeUtc(Path)));
      end
      else if TDirectory.Exists(Path) then
      begin
        R.AddPair('type',     'directory');
        R.AddPair('modified', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"',
          TDirectory.GetLastWriteTimeUtc(Path)));
        R.AddPair('created',  FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"',
          TDirectory.GetCreationTimeUtc(Path)));
        R.AddPair('files', TJSONNumber.Create(
          Length(TDirectory.GetFiles(Path))));
        R.AddPair('dirs',  TJSONNumber.Create(
          Length(TDirectory.GetDirectories(Path))));
      end
      else
        R.AddPair('type', 'not_found');

      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    else
      raise Exception.CreateFmt(
        'Unknown operation: "%s". Valid: read, write, append, list, exists, delete, move, copy, mkdir, info',
        [Op]);

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-files]: ' + E.Message)
        .Build;
  end;
end;

constructor TFileReaderTool.Create;
begin
  inherited;
  FName        := 'mcp-files';
  FDescription :=
    'File system operations on the server. ' +
    'read: read file text (maxSize bytes, default 1MB). ' +
    'write: create or overwrite a text file. ' +
    'append: append text to a file. ' +
    'list: list directory entries (pattern glob, recursive option). ' +
    'exists: check if path exists (file or directory). ' +
    'delete: delete a file or empty directory. ' +
    'move: move or rename a file or directory. ' +
    'copy: copy a file to a new location. ' +
    'mkdir: create a directory and all parents. ' +
    'info: metadata (size, dates, entry counts).';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-files',
    function: IAiMCPTool
    begin
      Result := TFileReaderTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-files');
end;

end.
