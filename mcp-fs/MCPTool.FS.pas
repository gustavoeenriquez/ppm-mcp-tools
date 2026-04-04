// Nombre: Gustavo Enríquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit MCPTool.FS;

(*
  MCPTool.FS  ·  mcp-fs  ·  port 8649

  Full filesystem manager: read, write, append, delete, copy, move,
  mkdir, rmdir, list, stat, exists, find, count.

  Operations:
    read    {path, offset?, limit?, encoding?}                     → {ok, content, lines, total}
    write   {path, content, encoding?, overwrite?}                 → {ok, path, size}
    append  {path, content, encoding?}                             → {ok, path, size}
    delete  {path}                                                 → {ok, path, existed}
    copy    {path, dest, overwrite?}                               → {ok, src, dest, size}
    move    {path, dest, overwrite?}                               → {ok, src, dest}
    mkdir   {path, recursive?}                                     → {ok, path}
    rmdir   {path, recursive?}                                     → {ok, path, existed}
    list    {path, pattern?, recursive?, sort?, offset?, limit?}   → {ok, entries[], total, count}
    stat    {path}                                                  → {ok, exists, is_dir, size, created, modified}
    exists  {path}                                                  → {ok, exists}
    find    {path, pattern, recursive?, sort?, offset?, limit?}    → {ok, matches[], total, count}
    count   {path, pattern?, recursive?}                           → {ok, total}

  Port: 8649
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults;

type
  TFSParams = class
  private
    FOperation: string;
    FPath:      string;
    FDest:      string;
    FContent:   string;
    FPattern:   string;
    FEncoding:  string;
    FSort:      string;
    FOffset:    Integer;
    FLimit:     Integer;
    FOverwrite: Boolean;
    FRecursive: Boolean;
  public
    [AiMCPSchemaDescription('Operation: read, write, append, delete, copy, move, mkdir, rmdir, list, stat, exists, find, count')]
    property Operation: string  read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('File or directory path. Required for all operations.')]
    property Path:      string  read FPath      write FPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Destination path. Required for: copy, move.')]
    property Dest:      string  read FDest      write FDest;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Text content to write or append. Required for: write, append.')]
    property Content:   string  read FContent   write FContent;

    [AiMCPOptional]
    [AiMCPSchemaDescription('File name filter pattern. Examples: "*.pas", "*.txt". Default: "*". Used by: list, find, count.')]
    property Pattern:   string  read FPattern   write FPattern;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Text encoding: "utf8" (default), "utf16", "ansi". Used by: read, write, append.')]
    property Encoding:  string  read FEncoding  write FEncoding;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Sort entries by: name, ext, size, date. Append :asc or :desc suffix. Default: name:asc. Used by: list, find.')]
    property Sort:      string  read FSort      write FSort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('For read: first line to read (1-based, default 1). For list/find: number of entries to skip (default 0).')]
    property Offset:    Integer read FOffset    write FOffset;

    [AiMCPOptional]
    [AiMCPSchemaDescription('For read: number of lines (default 0=all). For list/find: max entries to return (default 0=all).')]
    property Limit:     Integer read FLimit     write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Overwrite if destination exists. Used by: write, copy, move. Default: false')]
    property Overwrite: Boolean read FOverwrite write FOverwrite;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Recurse into subdirectories. Used by: list, find, count, mkdir, rmdir. Default: false')]
    property Recursive: Boolean read FRecursive write FRecursive;
  end;

  TFSTool = class(TAiMCPToolBase<TFSParams>)
  private
    function ResolveEncoding(const Enc: string): TEncoding;
    procedure ParseSort(const SortParam: string; out Field, Dir: string);
    function DoRead(const P: TFSParams): TJSONObject;
    function DoWrite(const P: TFSParams): TJSONObject;
    function DoAppend(const P: TFSParams): TJSONObject;
    function DoDelete(const P: TFSParams): TJSONObject;
    function DoCopy(const P: TFSParams): TJSONObject;
    function DoMove(const P: TFSParams): TJSONObject;
    function DoMkdir(const P: TFSParams): TJSONObject;
    function DoRmdir(const P: TFSParams): TJSONObject;
    function DoList(const P: TFSParams): TJSONObject;
    function DoStat(const P: TFSParams): TJSONObject;
    function DoExists(const P: TFSParams): TJSONObject;
    function DoFind(const P: TFSParams): TJSONObject;
    function DoCount(const P: TFSParams): TJSONObject;
    function FormatDate(const DT: TDateTime): string;
  protected
    function ExecuteWithParams(const AParams: TFSParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ --- Internal record for sortable FS entries --------------------------------- }

type
  TFSEntry = record
    Name:     string;
    Path:     string;
    IsDir:    Boolean;
    Size:     Int64;
    Modified: TDateTime;
  end;

{ TFSTool }

function TFSTool.FormatDate(const DT: TDateTime): string;
begin
  Result := System.SysUtils.FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', DT);
end;

function TFSTool.ResolveEncoding(const Enc: string): TEncoding;
var
  E: string;
begin
  E := LowerCase(Trim(Enc));
  if      E = 'utf16'  then Result := TEncoding.Unicode
  else if E = 'ansi'   then Result := TEncoding.ANSI
  else                      Result := TEncoding.UTF8;
end;

procedure TFSTool.ParseSort(const SortParam: string; out Field, Dir: string);
var
  Parts: TArray<string>;
begin
  Parts := LowerCase(Trim(SortParam)).Split([':']);
  if (Length(Parts) >= 1) and (Trim(Parts[0]) <> '') then
    Field := Trim(Parts[0])
  else
    Field := 'name';
  if (Length(Parts) >= 2) and (Trim(Parts[1]) <> '') then
    Dir := Trim(Parts[1])
  else
    Dir := 'asc';
  if not ((Field = 'name') or (Field = 'ext') or (Field = 'size') or (Field = 'date')) then
    Field := 'name';
  if not ((Dir = 'asc') or (Dir = 'desc')) then
    Dir := 'asc';
end;

{ --- Helper: build a TJSONObject from a TFSEntry ----------------------------- }

function EntryToJSON(const E: TFSEntry): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name',     E.Name);
  Result.AddPair('path',     E.Path);
  Result.AddPair('is_dir',   TJSONBool.Create(E.IsDir));
  Result.AddPair('size',     TJSONNumber.Create(E.Size));
  Result.AddPair('modified', System.SysUtils.FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', E.Modified));
end;

{ --- Helper: collect dir entries into a dynamic array ----------------------- }

function CollectEntries(const BasePath, Pat: string; SearchOpt: TSearchOption): TArray<TFSEntry>;
var
  Files, Dirs: TArray<string>;
  FP:   string;
  E:    TFSEntry;
  List: TList<TFSEntry>;
begin
  List := TList<TFSEntry>.Create;
  try
    Dirs := TDirectory.GetDirectories(BasePath, Pat, SearchOpt);
    for FP in Dirs do
    begin
      E.Name     := TPath.GetFileName(FP);
      E.Path     := FP;
      E.IsDir    := True;
      E.Size     := 0;
      E.Modified := TDirectory.GetLastWriteTime(FP);
      List.Add(E);
    end;
    Files := TDirectory.GetFiles(BasePath, Pat, SearchOpt);
    for FP in Files do
    begin
      E.Name     := TPath.GetFileName(FP);
      E.Path     := FP;
      E.IsDir    := False;
      E.Size     := TFile.GetSize(FP);
      E.Modified := TFile.GetLastWriteTime(FP);
      List.Add(E);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ --- Helper: sort a TFSEntry array in-place --------------------------------- }

procedure SortEntries(var Entries: TArray<TFSEntry>; const Field, Dir: string);
var
  Cmp: IComparer<TFSEntry>;
begin
  Cmp := TComparer<TFSEntry>.Construct(
    function(const A, B: TFSEntry): Integer
    var
      VA, VB: string;
    begin
      if Field = 'size' then
      begin
        if      A.Size < B.Size then Result := -1
        else if A.Size > B.Size then Result :=  1
        else                         Result :=  0;
      end
      else if Field = 'ext' then
      begin
        VA := LowerCase(TPath.GetExtension(A.Name));
        VB := LowerCase(TPath.GetExtension(B.Name));
        Result := CompareText(VA, VB);
        if Result = 0 then Result := CompareText(LowerCase(A.Name), LowerCase(B.Name));
      end
      else if Field = 'date' then
      begin
        if      A.Modified < B.Modified then Result := -1
        else if A.Modified > B.Modified then Result :=  1
        else                                 Result :=  0;
      end
      else // 'name'
        Result := CompareText(LowerCase(A.Name), LowerCase(B.Name));

      if Dir = 'desc' then Result := -Result;
    end);
  TArray.Sort<TFSEntry>(Entries, Cmp);
end;

{ ---------------------------------------------------------------------------- }

function TFSTool.DoRead(const P: TFSParams): TJSONObject;
var
  Lines:     TStringList;
  Start:     Integer;
  Count:     Integer;
  I:         Integer;
  SB:        TStringBuilder;
  Enc:       TEncoding;
  LineCount: Integer;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for read');
  if not TFile.Exists(P.Path) then
    raise Exception.CreateFmt('File not found: %s', [P.Path]);

  Enc   := ResolveEncoding(P.Encoding);
  Lines := TStringList.Create;
  SB    := TStringBuilder.Create;
  try
    Lines.LoadFromFile(P.Path, Enc);
    LineCount := Lines.Count;

    Start := P.Offset;
    if Start < 1 then Start := 1;
    Start := Min(Start, LineCount + 1);

    Count := P.Limit;
    if Count <= 0 then
      Count := LineCount - Start + 1
    else
      Count := Min(Count, LineCount - Start + 1);

    for I := Start - 1 to Start - 1 + Count - 1 do
    begin
      if SB.Length > 0 then SB.Append(#10);
      SB.Append(Lines[I]);
    end;

    Result := TJSONObject.Create;
    Result.AddPair('ok',      TJSONTrue.Create);
    Result.AddPair('path',    P.Path);
    Result.AddPair('content', SB.ToString);
    Result.AddPair('lines',   TJSONNumber.Create(Count));
    Result.AddPair('total',   TJSONNumber.Create(LineCount));
  finally
    Lines.Free;
    SB.Free;
  end;
end;

function TFSTool.DoWrite(const P: TFSParams): TJSONObject;
var
  Enc: TEncoding;
  Dir: string;
begin
  if P.Path    = '' then raise Exception.Create('"path" is required for write');
  if P.Content = '' then raise Exception.Create('"content" is required for write');
  if TFile.Exists(P.Path) and not P.Overwrite then
    raise Exception.CreateFmt('File already exists (use overwrite:true): %s', [P.Path]);

  Dir := TPath.GetDirectoryName(P.Path);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);

  Enc := ResolveEncoding(P.Encoding);
  TFile.WriteAllText(P.Path, P.Content, Enc);

  Result := TJSONObject.Create;
  Result.AddPair('ok',   TJSONTrue.Create);
  Result.AddPair('path', P.Path);
  Result.AddPair('size', TJSONNumber.Create(TFile.GetSize(P.Path)));
end;

function TFSTool.DoAppend(const P: TFSParams): TJSONObject;
var
  Enc:      TEncoding;
  Existing: string;
  Dir:      string;
begin
  if P.Path    = '' then raise Exception.Create('"path" is required for append');
  if P.Content = '' then raise Exception.Create('"content" is required for append');

  Dir := TPath.GetDirectoryName(P.Path);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);

  Enc := ResolveEncoding(P.Encoding);
  if TFile.Exists(P.Path) then
    Existing := TFile.ReadAllText(P.Path, Enc)
  else
    Existing := '';

  TFile.WriteAllText(P.Path, Existing + P.Content, Enc);

  Result := TJSONObject.Create;
  Result.AddPair('ok',   TJSONTrue.Create);
  Result.AddPair('path', P.Path);
  Result.AddPair('size', TJSONNumber.Create(TFile.GetSize(P.Path)));
end;

function TFSTool.DoDelete(const P: TFSParams): TJSONObject;
var
  Existed: Boolean;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for delete');
  Existed := TFile.Exists(P.Path);
  if Existed then
    TFile.Delete(P.Path);
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('path',    P.Path);
  Result.AddPair('existed', TJSONBool.Create(Existed));
end;

function TFSTool.DoCopy(const P: TFSParams): TJSONObject;
var
  DestDir: string;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for copy');
  if P.Dest = '' then raise Exception.Create('"dest" is required for copy');
  if not TFile.Exists(P.Path) then
    raise Exception.CreateFmt('Source not found: %s', [P.Path]);
  if TFile.Exists(P.Dest) and not P.Overwrite then
    raise Exception.CreateFmt('Destination exists (use overwrite:true): %s', [P.Dest]);

  DestDir := TPath.GetDirectoryName(P.Dest);
  if (DestDir <> '') and not TDirectory.Exists(DestDir) then
    TDirectory.CreateDirectory(DestDir);

  TFile.Copy(P.Path, P.Dest, P.Overwrite);

  Result := TJSONObject.Create;
  Result.AddPair('ok',   TJSONTrue.Create);
  Result.AddPair('src',  P.Path);
  Result.AddPair('dest', P.Dest);
  Result.AddPair('size', TJSONNumber.Create(TFile.GetSize(P.Dest)));
end;

function TFSTool.DoMove(const P: TFSParams): TJSONObject;
var
  DestDir: string;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for move');
  if P.Dest = '' then raise Exception.Create('"dest" is required for move');
  if not TFile.Exists(P.Path) then
    raise Exception.CreateFmt('Source not found: %s', [P.Path]);
  if TFile.Exists(P.Dest) then
  begin
    if not P.Overwrite then
      raise Exception.CreateFmt('Destination exists (use overwrite:true): %s', [P.Dest]);
    TFile.Delete(P.Dest);
  end;

  DestDir := TPath.GetDirectoryName(P.Dest);
  if (DestDir <> '') and not TDirectory.Exists(DestDir) then
    TDirectory.CreateDirectory(DestDir);

  TFile.Move(P.Path, P.Dest);

  Result := TJSONObject.Create;
  Result.AddPair('ok',   TJSONTrue.Create);
  Result.AddPair('src',  P.Path);
  Result.AddPair('dest', P.Dest);
end;

function TFSTool.DoMkdir(const P: TFSParams): TJSONObject;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for mkdir');
  if TDirectory.Exists(P.Path) then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('ok',      TJSONTrue.Create);
    Result.AddPair('path',    P.Path);
    Result.AddPair('created', TJSONFalse.Create);
    Exit;
  end;
  if P.Recursive then
    TDirectory.CreateDirectory(P.Path)
  else
  begin
    var Parent := TPath.GetDirectoryName(P.Path);
    if (Parent <> '') and not TDirectory.Exists(Parent) then
      raise Exception.CreateFmt('Parent directory does not exist (use recursive:true): %s', [Parent]);
    TDirectory.CreateDirectory(P.Path);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('path',    P.Path);
  Result.AddPair('created', TJSONTrue.Create);
end;

function TFSTool.DoRmdir(const P: TFSParams): TJSONObject;
var
  Existed: Boolean;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for rmdir');
  Existed := TDirectory.Exists(P.Path);
  if Existed then
    TDirectory.Delete(P.Path, P.Recursive);
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('path',    P.Path);
  Result.AddPair('existed', TJSONBool.Create(Existed));
end;

function TFSTool.DoList(const P: TFSParams): TJSONObject;
var
  Pat:       string;
  SearchOpt: TSearchOption;
  All:       TArray<TFSEntry>;
  Total:     Integer;
  Skip:      Integer;
  MaxCount:  Integer;
  I:         Integer;
  Arr:       TJSONArray;
  SortField, SortDir: string;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for list');
  if not TDirectory.Exists(P.Path) then
    raise Exception.CreateFmt('Directory not found: %s', [P.Path]);

  Pat := P.Pattern;
  if Pat = '' then Pat := '*';
  if P.Recursive then SearchOpt := TSearchOption.soAllDirectories
  else SearchOpt := TSearchOption.soTopDirectoryOnly;

  All := CollectEntries(P.Path, Pat, SearchOpt);
  Total := Length(All);

  ParseSort(P.Sort, SortField, SortDir);
  SortEntries(All, SortField, SortDir);

  Skip := P.Offset;
  if Skip < 0 then Skip := 0;
  MaxCount := P.Limit;
  if (MaxCount <= 0) or (MaxCount > Total - Skip) then MaxCount := Total - Skip;
  if MaxCount < 0 then MaxCount := 0;

  Arr := TJSONArray.Create;
  for I := Skip to Skip + MaxCount - 1 do
    Arr.AddElement(EntryToJSON(All[I]));

  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('path',    P.Path);
  Result.AddPair('total',   TJSONNumber.Create(Total));
  Result.AddPair('entries', Arr);
  Result.AddPair('count',   TJSONNumber.Create(Arr.Count));
end;

function TFSTool.DoStat(const P: TFSParams): TJSONObject;
var
  IsDir:  Boolean;
  IsFile: Boolean;
  Exists: Boolean;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for stat');
  IsDir  := TDirectory.Exists(P.Path);
  IsFile := TFile.Exists(P.Path);
  Exists := IsDir or IsFile;

  Result := TJSONObject.Create;
  Result.AddPair('ok',     TJSONTrue.Create);
  Result.AddPair('path',   P.Path);
  Result.AddPair('exists', TJSONBool.Create(Exists));

  if not Exists then Exit;

  Result.AddPair('is_dir', TJSONBool.Create(IsDir));

  if IsFile then
  begin
    Result.AddPair('size',     TJSONNumber.Create(TFile.GetSize(P.Path)));
    Result.AddPair('created',  FormatDate(TFile.GetCreationTime(P.Path)));
    Result.AddPair('modified', FormatDate(TFile.GetLastWriteTime(P.Path)));
  end
  else
  begin
    Result.AddPair('size',     TJSONNumber.Create(0));
    Result.AddPair('created',  FormatDate(TDirectory.GetCreationTime(P.Path)));
    Result.AddPair('modified', FormatDate(TDirectory.GetLastWriteTime(P.Path)));
  end;
end;

function TFSTool.DoExists(const P: TFSParams): TJSONObject;
var
  Ex: Boolean;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for exists');
  Ex := TFile.Exists(P.Path) or TDirectory.Exists(P.Path);
  Result := TJSONObject.Create;
  Result.AddPair('ok',     TJSONTrue.Create);
  Result.AddPair('path',   P.Path);
  Result.AddPair('exists', TJSONBool.Create(Ex));
end;

function TFSTool.DoFind(const P: TFSParams): TJSONObject;
var
  Pat:       string;
  SearchOpt: TSearchOption;
  All:       TArray<TFSEntry>;
  Total:     Integer;
  Skip:      Integer;
  MaxCount:  Integer;
  I:         Integer;
  Arr:       TJSONArray;
  SortField, SortDir: string;
begin
  if P.Path    = '' then raise Exception.Create('"path" is required for find');
  if P.Pattern = '' then raise Exception.Create('"pattern" is required for find');
  if not TDirectory.Exists(P.Path) then
    raise Exception.CreateFmt('Directory not found: %s', [P.Path]);

  Pat := P.Pattern;
  if P.Recursive then SearchOpt := TSearchOption.soAllDirectories
  else SearchOpt := TSearchOption.soTopDirectoryOnly;

  All := CollectEntries(P.Path, Pat, SearchOpt);
  Total := Length(All);

  ParseSort(P.Sort, SortField, SortDir);
  SortEntries(All, SortField, SortDir);

  Skip := P.Offset;
  if Skip < 0 then Skip := 0;
  MaxCount := P.Limit;
  if (MaxCount <= 0) or (MaxCount > Total - Skip) then MaxCount := Total - Skip;
  if MaxCount < 0 then MaxCount := 0;

  Arr := TJSONArray.Create;
  for I := Skip to Skip + MaxCount - 1 do
    Arr.AddElement(EntryToJSON(All[I]));

  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('path',    P.Path);
  Result.AddPair('pattern', Pat);
  Result.AddPair('total',   TJSONNumber.Create(Total));
  Result.AddPair('matches', Arr);
  Result.AddPair('count',   TJSONNumber.Create(Arr.Count));
end;

function TFSTool.DoCount(const P: TFSParams): TJSONObject;
var
  Pat:       string;
  SearchOpt: TSearchOption;
  Files, Dirs: TArray<string>;
  Total:     Integer;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for count');
  if not TDirectory.Exists(P.Path) then
    raise Exception.CreateFmt('Directory not found: %s', [P.Path]);

  Pat := P.Pattern;
  if Pat = '' then Pat := '*';
  if P.Recursive then SearchOpt := TSearchOption.soAllDirectories
  else SearchOpt := TSearchOption.soTopDirectoryOnly;

  Dirs  := TDirectory.GetDirectories(P.Path, Pat, SearchOpt);
  Files := TDirectory.GetFiles(P.Path, Pat, SearchOpt);
  Total := Length(Dirs) + Length(Files);

  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('path',    P.Path);
  Result.AddPair('pattern', Pat);
  Result.AddPair('total',   TJSONNumber.Create(Total));
end;

function TFSTool.ExecuteWithParams(const AParams: TFSParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'read'   then R := DoRead(AParams)
    else if Op = 'write'  then R := DoWrite(AParams)
    else if Op = 'append' then R := DoAppend(AParams)
    else if Op = 'delete' then R := DoDelete(AParams)
    else if Op = 'copy'   then R := DoCopy(AParams)
    else if Op = 'move'   then R := DoMove(AParams)
    else if Op = 'mkdir'  then R := DoMkdir(AParams)
    else if Op = 'rmdir'  then R := DoRmdir(AParams)
    else if Op = 'list'   then R := DoList(AParams)
    else if Op = 'stat'   then R := DoStat(AParams)
    else if Op = 'exists' then R := DoExists(AParams)
    else if Op = 'find'   then R := DoFind(AParams)
    else if Op = 'count'  then R := DoCount(AParams)
    else raise Exception.CreateFmt(
      'Unknown operation "%s". Valid: read,write,append,delete,copy,move,mkdir,rmdir,list,stat,exists,find,count', [Op]);

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

constructor TFSTool.Create;
begin
  inherited;
  FName        := 'mcp-fs';
  FDescription :=
    'Full filesystem manager: read, write, copy, move, delete files and directories.' + #10 +
    'ALWAYS include "operation" in every call. Use absolute paths to avoid ambiguity.' + #10 +
    '' + #10 +
    'OPERATIONS (required params listed after each name):' + #10 +
    '  read    — path. Optional: offset (start line 1-based), limit (line count), encoding (utf8/utf16/ansi).' + #10 +
    '            Returns content, lines read, total lines.' + #10 +
    '            Example: {"operation":"read","path":"C:/data/notes.txt","offset":1,"limit":50}' + #10 +
    '  write   — path, content. Optional: overwrite (default false), encoding. Creates file (and parent dirs).' + #10 +
    '            Example: {"operation":"write","path":"C:/data/out.txt","content":"Hello","overwrite":true}' + #10 +
    '  append  — path, content. Optional: encoding. Appends text; creates file if not exists.' + #10 +
    '            Example: {"operation":"append","path":"C:/data/log.txt","content":"New line\n"}' + #10 +
    '  delete  — path (file only). Returns existed:bool.' + #10 +
    '            Example: {"operation":"delete","path":"C:/data/old.txt"}' + #10 +
    '  copy    — path (source), dest. Optional: overwrite. Copies a file.' + #10 +
    '            Example: {"operation":"copy","path":"C:/a.txt","dest":"C:/b.txt","overwrite":true}' + #10 +
    '  move    — path (source), dest. Optional: overwrite. Moves/renames a file.' + #10 +
    '            Example: {"operation":"move","path":"C:/old.txt","dest":"C:/new.txt"}' + #10 +
    '  mkdir   — path. Optional: recursive (create parent dirs too). Creates a directory.' + #10 +
    '            Example: {"operation":"mkdir","path":"C:/data/reports/2026","recursive":true}' + #10 +
    '  rmdir   — path. Optional: recursive (delete contents too). Removes a directory.' + #10 +
    '            Example: {"operation":"rmdir","path":"C:/data/tmp","recursive":true}' + #10 +
    '  count   — path. Optional: pattern (e.g. "*.txt"), recursive. Counts entries WITHOUT loading them.' + #10 +
    '            Use this FIRST to know how many results exist before calling list/find.' + #10 +
    '            Returns total (number of matching files+dirs).' + #10 +
    '            Example: {"operation":"count","path":"C:/src","pattern":"*.pas","recursive":true}' + #10 +
    '  list    — path (directory). Optional: pattern ("*.txt"), recursive, sort, offset, limit.' + #10 +
    '            sort: "name" | "ext" | "size" | "date" with optional ":asc"/":desc" (default name:asc).' + #10 +
    '            offset: skip first N entries. limit: max entries to return (0=all).' + #10 +
    '            Returns entries[] (name, path, is_dir, size, modified), total, count.' + #10 +
    '            Example: {"operation":"list","path":"C:/src","pattern":"*.pas","sort":"size:desc","limit":20}' + #10 +
    '  stat    — path. Returns exists, is_dir, size, created, modified.' + #10 +
    '            Example: {"operation":"stat","path":"C:/data/notes.txt"}' + #10 +
    '  exists  — path. Returns exists:bool. Works for files and directories.' + #10 +
    '            Example: {"operation":"exists","path":"C:/data/notes.txt"}' + #10 +
    '  find    — path (directory), pattern (e.g. "*.log"). Optional: recursive (default true), sort, offset, limit.' + #10 +
    '            Returns matches[] (name, path, is_dir, size, modified), total, count.' + #10 +
    '            TIP: use count first on large dirs; then use offset+limit to page through results.' + #10 +
    '            Example: {"operation":"find","path":"C:/data","pattern":"*.log","sort":"date:desc","limit":10}';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-fs',
    function: IAiMCPTool
    begin
      Result := TFSTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-fs');
end;

end.
