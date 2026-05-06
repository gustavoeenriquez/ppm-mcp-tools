unit MCPTool.KV;

(*
  MCPTool.KV  ·  mcp-kv

  Fast persistent key-value store with in-memory singleton cache.
  Each namespace is a separate JSON file loaded once and kept in memory.
  Mutating operations flush to disk immediately.

  Operations:
    set        {key, kvalue}              -> {ok, key}
    get        {key}                      -> {ok, found, key, value}
    delete     {key}                      -> {ok, key, existed}
    list                                  -> {ok, keys[], count}
    list_all                              -> {ok, entries{}, count}
    clear                                 -> {ok, cleared:N}
    search     {query}                    -> {ok, matches{}, count}
    append     {key, kvalue}              -> {ok, key, value}
    count                                 -> {ok, count}
    namespaces                            -> {ok, list[], count}

  Optional for all ops: namespace (default: "default"), storage_path
  Storage: {storage_path}/kv/{namespace}.json
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON,
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.SyncObjs;

type
  TKVParams = class
  private
    FOperation:   string;
    FNamespace:   string;
    FStoragePath: string;
    FKey:         string;
    FKvalue:      string;
    FQuery:       string;
  public
    [AiMCPSchemaDescription('Operation: set, get, delete, list, list_all, clear, search, append, count, namespaces')]
    property Operation:   string read FOperation   write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Namespace for isolation. Default: "default". Each namespace is a separate JSON file.')]
    property Namespace:   string read FNamespace   write FNamespace;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Storage base directory. Default: {Documents}/mcp-kv/')]
    property StoragePath: string read FStoragePath write FStoragePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Key name (required for: set, get, delete, append)')]
    property Key:         string read FKey         write FKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Value to store as string (required for: set, append)')]
    property Kvalue:      string read FKvalue      write FKvalue;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Substring query for search (required for: search)')]
    property Query:       string read FQuery       write FQuery;
  end;

  TKVTool = class(TAiMCPToolBase<TKVParams>)
  private
    function  ResolveDir(const P: TKVParams): string;
    function  NSFilePath(const Dir, NS: string): string;
    function  SafeNS(const NS: string): string;
    function  GetData(const FP: string): TJSONObject;      // caller MUST hold GKVLock
    procedure FlushData(const FP: string; Data: TJSONObject); // caller MUST hold GKVLock
    function  DoSet(const P: TKVParams): TJSONObject;
    function  DoGet(const P: TKVParams): TJSONObject;
    function  DoDelete(const P: TKVParams): TJSONObject;
    function  DoList(const P: TKVParams): TJSONObject;
    function  DoListAll(const P: TKVParams): TJSONObject;
    function  DoClear(const P: TKVParams): TJSONObject;
    function  DoSearch(const P: TKVParams): TJSONObject;
    function  DoAppend(const P: TKVParams): TJSONObject;
    function  DoCount(const P: TKVParams): TJSONObject;
    function  DoNamespaces(const P: TKVParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TKVParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure SetDefaultStoragePath(const APath: string);
procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  StrUtils;

var
  GKVCache:          TObjectDictionary<string, TJSONObject>;
  GKVLock:           TCriticalSection;
  GDefaultStoragePath: string = '';

{ TKVTool }

function TKVTool.SafeNS(const NS: string): string;
var
  I: Integer;
  C: Char;
  S: string;
begin
  Result := Trim(NS);
  if Result = '' then Result := 'default';
  S := '';
  for I := 1 to Length(Result) do
  begin
    C := Result[I];
    if CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) then
      S := S + C
    else
      S := S + '_';
  end;
  if S = '' then S := 'default';
  Result := S;
end;

function TKVTool.ResolveDir(const P: TKVParams): string;
begin
  if Trim(P.StoragePath) <> '' then
    Result := P.StoragePath
  else if GDefaultStoragePath <> '' then
    Result := GDefaultStoragePath
  else
    Result := TPath.Combine(TPath.GetDocumentsPath, 'mcp-kv');
end;

function TKVTool.NSFilePath(const Dir, NS: string): string;
begin
  Result := TPath.Combine(Dir, SafeNS(NS) + '.json');
end;

function TKVTool.GetData(const FP: string): TJSONObject;
// Caller MUST hold GKVLock
var
  Content: string;
  Parsed:  TJSONValue;
begin
  if GKVCache.TryGetValue(FP, Result) then
    Exit;

  if TFile.Exists(FP) then
  begin
    Content := TFile.ReadAllText(FP, TEncoding.UTF8);
    Parsed  := TJSONObject.ParseJSONValue(Trim(Content));
    if (Parsed <> nil) and (Parsed is TJSONObject) then
      Result := TJSONObject(Parsed)
    else
    begin
      if Parsed <> nil then Parsed.Free;
      Result := TJSONObject.Create;
    end;
  end
  else
    Result := TJSONObject.Create;

  GKVCache.Add(FP, Result);
end;

procedure TKVTool.FlushData(const FP: string; Data: TJSONObject);
// Caller MUST hold GKVLock
var
  Dir: string;
begin
  Dir := TPath.GetDirectoryName(FP);
  if not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);
  TFile.WriteAllText(FP, Data.ToJSON, TEncoding.UTF8);
end;

{ --- Operations --- }

function TKVTool.DoSet(const P: TKVParams): TJSONObject;
var
  FP:   string;
  Data: TJSONObject;
begin
  if P.Key = '' then raise Exception.Create('"key" is required for set');
  FP := NSFilePath(ResolveDir(P), P.Namespace);
  GKVLock.Acquire;
  try
    Data := GetData(FP);
    if Data.GetValue(P.Key) <> nil then Data.RemovePair(P.Key).Free;
    Data.AddPair(P.Key, P.Kvalue);
    FlushData(FP, Data);
  finally
    GKVLock.Release;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',  TJSONTrue.Create);
  Result.AddPair('key', P.Key);
end;

function TKVTool.DoGet(const P: TKVParams): TJSONObject;
var
  FP:     string;
  Data:   TJSONObject;
  Pair:   TJSONPair;
  Found:  Boolean;
  ValStr: string;
begin
  if P.Key = '' then raise Exception.Create('"key" is required for get');
  FP := NSFilePath(ResolveDir(P), P.Namespace);
  GKVLock.Acquire;
  try
    Data := GetData(FP);
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
    GKVLock.Release;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',    TJSONTrue.Create);
  Result.AddPair('key',   P.Key);
  Result.AddPair('found', TJSONBool.Create(Found));
  Result.AddPair('value', ValStr);
end;

function TKVTool.DoDelete(const P: TKVParams): TJSONObject;
var
  FP:      string;
  Data:    TJSONObject;
  Removed: TJSONPair;
  Existed: Boolean;
begin
  if P.Key = '' then raise Exception.Create('"key" is required for delete');
  FP := NSFilePath(ResolveDir(P), P.Namespace);
  GKVLock.Acquire;
  try
    Data    := GetData(FP);
    Removed := Data.RemovePair(P.Key);
    Existed := Removed <> nil;
    if Existed then
    begin
      Removed.Free;
      FlushData(FP, Data);
    end;
  finally
    GKVLock.Release;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('key',     P.Key);
  Result.AddPair('existed', TJSONBool.Create(Existed));
end;

function TKVTool.DoList(const P: TKVParams): TJSONObject;
var
  FP:   string;
  Data: TJSONObject;
  Arr:  TJSONArray;
  Pair: TJSONPair;
begin
  FP  := NSFilePath(ResolveDir(P), P.Namespace);
  Arr := TJSONArray.Create;
  GKVLock.Acquire;
  try
    Data := GetData(FP);
    for Pair in Data do
      Arr.Add(Pair.JsonString.Value);
  finally
    GKVLock.Release;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',    TJSONTrue.Create);
  Result.AddPair('keys',  Arr);
  Result.AddPair('count', TJSONNumber.Create(Arr.Count));
end;

function TKVTool.DoListAll(const P: TKVParams): TJSONObject;
var
  FP:      string;
  Data:    TJSONObject;
  Entries: TJSONObject;
  Pair:    TJSONPair;
  Count:   Integer;
begin
  FP      := NSFilePath(ResolveDir(P), P.Namespace);
  Entries := TJSONObject.Create;
  Count   := 0;
  GKVLock.Acquire;
  try
    Data := GetData(FP);
    for Pair in Data do
    begin
      Entries.AddPair(Pair.JsonString.Value, Pair.JsonValue.Value);
      Inc(Count);
    end;
  finally
    GKVLock.Release;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('entries', Entries);
  Result.AddPair('count',   TJSONNumber.Create(Count));
end;

function TKVTool.DoClear(const P: TKVParams): TJSONObject;
var
  FP:    string;
  Data:  TJSONObject;
  Count: Integer;
  Empty: TJSONObject;
begin
  FP := NSFilePath(ResolveDir(P), P.Namespace);
  GKVLock.Acquire;
  try
    Data  := GetData(FP);
    Count := Data.Count;
    Empty := TJSONObject.Create;
    GKVCache.AddOrSetValue(FP, Empty);  // replaces + frees old Data
    FlushData(FP, Empty);
  finally
    GKVLock.Release;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('cleared', TJSONNumber.Create(Count));
end;

function TKVTool.DoSearch(const P: TKVParams): TJSONObject;
var
  FP:      string;
  Data:    TJSONObject;
  Matches: TJSONObject;
  Pair:    TJSONPair;
  Q:       string;
  Count:   Integer;
begin
  if P.Query = '' then raise Exception.Create('"query" is required for search');
  FP      := NSFilePath(ResolveDir(P), P.Namespace);
  Matches := TJSONObject.Create;
  Q       := LowerCase(P.Query);
  Count   := 0;
  GKVLock.Acquire;
  try
    Data := GetData(FP);
    for Pair in Data do
    begin
      if (Pos(Q, LowerCase(Pair.JsonString.Value)) > 0) or
         (Pos(Q, LowerCase(Pair.JsonValue.Value))   > 0) then
      begin
        Matches.AddPair(Pair.JsonString.Value, Pair.JsonValue.Value);
        Inc(Count);
      end;
    end;
  finally
    GKVLock.Release;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('query',   P.Query);
  Result.AddPair('matches', Matches);
  Result.AddPair('count',   TJSONNumber.Create(Count));
end;

function TKVTool.DoAppend(const P: TKVParams): TJSONObject;
var
  FP:       string;
  Data:     TJSONObject;
  Existing: string;
  NewVal:   string;
  Pair:     TJSONPair;
begin
  if P.Key = '' then raise Exception.Create('"key" is required for append');
  FP := NSFilePath(ResolveDir(P), P.Namespace);
  GKVLock.Acquire;
  try
    Data := GetData(FP);
    Pair := Data.Get(P.Key);
    if Pair <> nil then
      Existing := Pair.JsonValue.Value
    else
      Existing := '';
    if Existing = '' then
      NewVal := P.Kvalue
    else
      NewVal := Existing + #10 + P.Kvalue;
    if Data.GetValue(P.Key) <> nil then Data.RemovePair(P.Key).Free;
    Data.AddPair(P.Key, NewVal);
    FlushData(FP, Data);
  finally
    GKVLock.Release;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',    TJSONTrue.Create);
  Result.AddPair('key',   P.Key);
  Result.AddPair('value', NewVal);
end;

function TKVTool.DoCount(const P: TKVParams): TJSONObject;
var
  FP:    string;
  Data:  TJSONObject;
  Count: Integer;
begin
  FP := NSFilePath(ResolveDir(P), P.Namespace);
  GKVLock.Acquire;
  try
    Data  := GetData(FP);
    Count := Data.Count;
  finally
    GKVLock.Release;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',    TJSONTrue.Create);
  Result.AddPair('count', TJSONNumber.Create(Count));
end;

function TKVTool.DoNamespaces(const P: TKVParams): TJSONObject;
var
  Dir:   string;
  Arr:   TJSONArray;
  Files: TArray<string>;
  FN:    string;
begin
  Dir := ResolveDir(P);
  Arr := TJSONArray.Create;
  if TDirectory.Exists(Dir) then
  begin
    Files := TDirectory.GetFiles(Dir, '*.json');
    for FN in Files do
      Arr.Add(TPath.GetFileNameWithoutExtension(FN));
  end;
  Result := TJSONObject.Create;
  Result.AddPair('ok',    TJSONTrue.Create);
  Result.AddPair('list',  Arr);
  Result.AddPair('count', TJSONNumber.Create(Arr.Count));
end;

function TKVTool.ExecuteWithParams(const AParams: TKVParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'set'        then R := DoSet(AParams)
    else if Op = 'get'        then R := DoGet(AParams)
    else if Op = 'delete'     then R := DoDelete(AParams)
    else if Op = 'list'       then R := DoList(AParams)
    else if Op = 'list_all'   then R := DoListAll(AParams)
    else if Op = 'clear'      then R := DoClear(AParams)
    else if Op = 'search'     then R := DoSearch(AParams)
    else if Op = 'append'     then R := DoAppend(AParams)
    else if Op = 'count'      then R := DoCount(AParams)
    else if Op = 'namespaces' then R := DoNamespaces(AParams)
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

constructor TKVTool.Create;
begin
  inherited;
  FName        := 'mcp-kv';
  FDescription :=
    'Persistent key-value memory. Data is saved to disk and survives restarts.' + #10 +
    'ALWAYS pass "operation" to choose the action. Use "namespace" to separate data per session (default: "default").' + #10 +
    '' + #10 +
    'OPERATIONS AND REQUIRED PARAMS:' + #10 +
    '  set        key + kvalue          -> saves a value. Example: {operation:"set",key:"user",kvalue:"Alice",namespace:"s1"}' + #10 +
    '  get        key                   -> reads a value. Returns {found:bool, value:str}. Example: {operation:"get",key:"user",namespace:"s1"}' + #10 +
    '  list_all   (no extra params)     -> returns ALL key-value pairs. Example: {operation:"list_all",namespace:"s1"}' + #10 +
    '  list       (no extra params)     -> returns key names only. Example: {operation:"list",namespace:"s1"}' + #10 +
    '  delete     key                   -> removes a key. Example: {operation:"delete",key:"user"}' + #10 +
    '  search     query                 -> finds entries where key or value contains query. Example: {operation:"search",query:"Alice"}' + #10 +
    '  append     key + kvalue          -> appends text to existing value. Example: {operation:"append",key:"log",kvalue:"new line"}' + #10 +
    '  clear      (no extra params)     -> deletes all entries in namespace. Example: {operation:"clear",namespace:"s1"}' + #10 +
    '  count      (no extra params)     -> counts entries. Example: {operation:"count"}' + #10 +
    '  namespaces (no extra params)     -> lists available namespaces. Example: {operation:"namespaces"}';
end;

procedure SetDefaultStoragePath(const APath: string);
begin
  GDefaultStoragePath := Trim(APath);
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-kv',
    function: IAiMCPTool
    begin
      Result := TKVTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-kv] ready');
end;

initialization
  GKVCache := TObjectDictionary<string, TJSONObject>.Create([doOwnsValues]);
  GKVLock  := TCriticalSection.Create;

// No finalization: server process killed externally; OS reclaims memory.
// Data is already on disk (flush-on-write). Freeing globals races with server thread.

end.
