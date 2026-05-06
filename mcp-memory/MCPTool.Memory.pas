unit MCPTool.Memory;

(*
  MCPTool.Memory  ·  mcp-memory

  Simple in-memory key-value store with persistence to a JSON file.

  Operations:
    store     - store a value for a key: {key, memvalue}
    retrieve  - get value for a key: {key} -> {ok, key, value}
    delete    - remove a key: {key} -> {ok, deleted}
    list      - list all stored keys -> {ok, keys:[...]}
    list_all  - list all key-value pairs -> {ok, entries:{...}}
    clear     - clear all memory -> {ok, cleared:N}
    search    - find keys/values containing substring: {query} -> {ok, matches:{...}}
    append    - append text to existing value: {key, memvalue}
    count     - count entries -> {ok, count:N}

  Storage: JSON file at {StoragePath}/mcp_memory.json
  Default StoragePath: TPath.GetDocumentsPath
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type

  TMemoryParams = class
  private
    FOperation:   string;
    FStoragePath: string;
    FKey:         string;
    FValue:       string;
    FQuery:       string;
  public
    [AiMCPSchemaDescription('Operation: store, retrieve, delete, list, list_all, clear, search, append, count')]
    property Operation:   string read FOperation   write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Directory path for the JSON storage file (default: Documents folder)')]
    property StoragePath: string read FStoragePath write FStoragePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Memory key (required for store, retrieve, delete, append)')]
    property Key:         string read FKey         write FKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Value to store (required for store, append)')]
    property MemValue:    string read FValue        write FValue;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search query substring (required for search)')]
    property Query:       string read FQuery        write FQuery;
  end;

  TMemoryTool = class(TAiMCPToolBase<TMemoryParams>)
  private
    function GetFilePath(const StoragePath: string): string;
    function ResolveStoragePath(const StoragePath: string): string;
    function LoadData(const StoragePath: string): TJSONObject;
    function SaveData(const StoragePath: string; Data: TJSONObject): Boolean;
    function DoStore(const P: TMemoryParams): TJSONObject;
    function DoRetrieve(const P: TMemoryParams): TJSONObject;
    function DoDelete(const P: TMemoryParams): TJSONObject;
    function DoList(const P: TMemoryParams): TJSONObject;
    function DoListAll(const P: TMemoryParams): TJSONObject;
    function DoClear(const P: TMemoryParams): TJSONObject;
    function DoSearch(const P: TMemoryParams): TJSONObject;
    function DoAppend(const P: TMemoryParams): TJSONObject;
    function DoCount(const P: TMemoryParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TMemoryParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils;

{ TMemoryTool }

function TMemoryTool.ResolveStoragePath(const StoragePath: string): string;
begin
  if Trim(StoragePath) = '' then
    Result := TPath.GetDocumentsPath
  else
    Result := StoragePath;
end;

function TMemoryTool.GetFilePath(const StoragePath: string): string;
begin
  Result := TPath.Combine(StoragePath, 'mcp_memory.json');
end;

function TMemoryTool.LoadData(const StoragePath: string): TJSONObject;
var
  FilePath: string;
  Content:  string;
  Parsed:   TJSONValue;
begin
  FilePath := GetFilePath(StoragePath);
  if not TFile.Exists(FilePath) then
  begin
    Result := TJSONObject.Create;
    Exit;
  end;
  Content := TFile.ReadAllText(FilePath, TEncoding.UTF8);
  if Trim(Content) = '' then
  begin
    Result := TJSONObject.Create;
    Exit;
  end;
  Parsed := TJSONObject.ParseJSONValue(Content);
  if (Parsed <> nil) and (Parsed is TJSONObject) then
    Result := Parsed as TJSONObject
  else
  begin
    if Parsed <> nil then
      Parsed.Free;
    Result := TJSONObject.Create;
  end;
end;

function TMemoryTool.SaveData(const StoragePath: string; Data: TJSONObject): Boolean;
var
  FilePath: string;
  Dir:      string;
begin
  Result   := False;
  FilePath := GetFilePath(StoragePath);
  Dir      := TPath.GetDirectoryName(FilePath);
  if not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);
  TFile.WriteAllText(FilePath, Data.ToJSON, TEncoding.UTF8);
  Result := True;
end;

function TMemoryTool.DoStore(const P: TMemoryParams): TJSONObject;
var
  Dir:  string;
  Data: TJSONObject;
begin
  if P.Key = '' then
    raise Exception.Create('"key" is required for store');
  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    if Data.GetValue(P.Key) <> nil then
      Data.RemovePair(P.Key).Free;
    Data.AddPair(P.Key, P.MemValue);
    SaveData(Dir, Data);
  finally
    Data.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',    TJSONTrue.Create);
  Result.AddPair('key',   P.Key);
  Result.AddPair('value', P.MemValue);
end;

function TMemoryTool.DoRetrieve(const P: TMemoryParams): TJSONObject;
var
  Dir:      string;
  Data:     TJSONObject;
  Pair:     TJSONPair;
  Found:    Boolean;
  ValStr:   string;
begin
  if P.Key = '' then
    raise Exception.Create('"key" is required for retrieve');
  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Pair := Data.Get(P.Key);
    if Pair <> nil then
    begin
      Found  := True;
      ValStr := Pair.JsonValue.Value;
    end
    else
    begin
      Found  := False;
      ValStr := '';
    end;
  finally
    Data.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',    TJSONTrue.Create);
  Result.AddPair('key',   P.Key);
  Result.AddPair('found', TJSONBool.Create(Found));
  Result.AddPair('value', ValStr);
end;

function TMemoryTool.DoDelete(const P: TMemoryParams): TJSONObject;
var
  Dir:     string;
  Data:    TJSONObject;
  Removed: TJSONPair;
  Existed: Boolean;
begin
  if P.Key = '' then
    raise Exception.Create('"key" is required for delete');
  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Removed := Data.RemovePair(P.Key);
    if Removed <> nil then
    begin
      Existed := True;
      Removed.Free;
      SaveData(Dir, Data);
    end
    else
      Existed := False;
  finally
    Data.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('deleted', P.Key);
  Result.AddPair('existed', TJSONBool.Create(Existed));
end;

function TMemoryTool.DoList(const P: TMemoryParams): TJSONObject;
var
  Dir:  string;
  Data: TJSONObject;
  Arr:  TJSONArray;
  Pair: TJSONPair;
begin
  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Arr := TJSONArray.Create;
    for Pair in Data do
      Arr.Add(Pair.JsonString.Value);
  finally
    Data.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',    TJSONTrue.Create);
  Result.AddPair('keys',  Arr);
  Result.AddPair('count', TJSONNumber.Create(Arr.Count));
end;

function TMemoryTool.DoListAll(const P: TMemoryParams): TJSONObject;
var
  Dir:     string;
  Data:    TJSONObject;
  Entries: TJSONObject;
  Pair:    TJSONPair;
  Count:   Integer;
begin
  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Entries := TJSONObject.Create;
    Count   := 0;
    for Pair in Data do
    begin
      Entries.AddPair(Pair.JsonString.Value, Pair.JsonValue.Value);
      Inc(Count);
    end;
  finally
    Data.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('entries', Entries);
  Result.AddPair('count',   TJSONNumber.Create(Count));
end;

function TMemoryTool.DoClear(const P: TMemoryParams): TJSONObject;
var
  Dir:   string;
  Data:  TJSONObject;
  Empty: TJSONObject;
  Count: Integer;
begin
  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Count := Data.Count;
  finally
    Data.Free;
  end;
  Empty := TJSONObject.Create;
  try
    SaveData(Dir, Empty);
  finally
    Empty.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('cleared', TJSONNumber.Create(Count));
end;

function TMemoryTool.DoSearch(const P: TMemoryParams): TJSONObject;
var
  Dir:     string;
  Data:    TJSONObject;
  Matches: TJSONObject;
  Pair:    TJSONPair;
  Q:       string;
  K:       string;
  V:       string;
  Count:   Integer;
begin
  if P.Query = '' then
    raise Exception.Create('"query" is required for search');
  Dir  := ResolveStoragePath(P.StoragePath);
  Q    := LowerCase(P.Query);
  Data := LoadData(Dir);
  try
    Matches := TJSONObject.Create;
    Count   := 0;
    for Pair in Data do
    begin
      K := Pair.JsonString.Value;
      V := Pair.JsonValue.Value;
      if (Pos(Q, LowerCase(K)) > 0) or (Pos(Q, LowerCase(V)) > 0) then
      begin
        Matches.AddPair(K, V);
        Inc(Count);
      end;
    end;
  finally
    Data.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('query',   P.Query);
  Result.AddPair('matches', Matches);
  Result.AddPair('count',   TJSONNumber.Create(Count));
end;

function TMemoryTool.DoAppend(const P: TMemoryParams): TJSONObject;
var
  Dir:      string;
  Data:     TJSONObject;
  Existing: string;
  NewVal:   string;
  Pair:     TJSONPair;
begin
  if P.Key = '' then
    raise Exception.Create('"key" is required for append');
  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Pair := Data.Get(P.Key);
    if Pair <> nil then
      Existing := Pair.JsonValue.Value
    else
      Existing := '';

    if Existing = '' then
      NewVal := P.MemValue
    else
      NewVal := Existing + #10 + P.MemValue;

    if Data.GetValue(P.Key) <> nil then
      Data.RemovePair(P.Key).Free;
    Data.AddPair(P.Key, NewVal);
    SaveData(Dir, Data);
  finally
    Data.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',    TJSONTrue.Create);
  Result.AddPair('key',   P.Key);
  Result.AddPair('value', NewVal);
end;

function TMemoryTool.DoCount(const P: TMemoryParams): TJSONObject;
var
  Dir:  string;
  Data: TJSONObject;
  N:    Integer;
begin
  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    N := Data.Count;
  finally
    Data.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',    TJSONTrue.Create);
  Result.AddPair('count', TJSONNumber.Create(N));
end;

function TMemoryTool.ExecuteWithParams(const AParams: TMemoryParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'store'    then R := DoStore(AParams)
    else if Op = 'retrieve' then R := DoRetrieve(AParams)
    else if Op = 'delete'   then R := DoDelete(AParams)
    else if Op = 'list'     then R := DoList(AParams)
    else if Op = 'list_all' then R := DoListAll(AParams)
    else if Op = 'clear'    then R := DoClear(AParams)
    else if Op = 'search'   then R := DoSearch(AParams)
    else if Op = 'append'   then R := DoAppend(AParams)
    else if Op = 'count'    then R := DoCount(AParams)
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

constructor TMemoryTool.Create;
begin
  inherited;
  FName        := 'mcp-memory';
  FDescription :=
    'In-memory key-value store with JSON file persistence. ' +
    'Operations: ' +
    'store (save a value; params: key, memvalue, storagepath?), ' +
    'retrieve (get a value; params: key, storagepath?), ' +
    'delete (remove a key; params: key, storagepath?), ' +
    'list (list all keys; params: storagepath?), ' +
    'list_all (list all key-value pairs; params: storagepath?), ' +
    'clear (delete all entries; params: storagepath?), ' +
    'search (find by key/value substring; params: query, storagepath?), ' +
    'append (append text to a key; params: key, memvalue, storagepath?), ' +
    'count (count entries; params: storagepath?). ' +
    'Storage file: mcp_memory.json in Documents folder by default.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-memory',
    function: IAiMCPTool
    begin
      Result := TMemoryTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-memory] ready');
end;

end.
