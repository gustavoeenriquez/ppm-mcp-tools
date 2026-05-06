unit MCPTool.JsonQuery;

{
  MCPTool.JsonQuery
  MCP tool: mcp-json-query

  Operations:
    validate — check if the JSON string is syntactically valid
    format   — pretty-print JSON with configurable indent
    minify   — compact JSON (remove all whitespace)
    get      — get value at a dot-notation path  (e.g. "user.address.city", "items[0].name")
    keys     — list keys of a JSON object (at path or root)
    values   — list values of a JSON object or array (at path or root)
    count    — count items in an array / keys in an object (at path or root)
    type     — return the JSON type at a path or root
    flatten  — flatten nested object to a flat dot-notation key/value map
    merge    — deep-merge two JSON objects (json + json2)

  Path notation:
    "name"            top-level key
    "user.name"       nested key
    "items[0]"        array index
    "items[0].title"  combined
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.StrUtils;

type

  // ── Parameters ─────────────────────────────────────────────────────────────

  TJsonQueryParams = class
  private
    FOperation: string;
    FJson:      string;
    FPath:      string;
    FNewValue:  string;
    FJson2:     string;
    FIndent:    Integer;
  public
    [AiMCPSchemaDescription('Operation: validate, format, minify, get, keys, values, count, type, flatten, merge')]
    property Operation: string read FOperation write FOperation;

    [AiMCPSchemaDescription('Input JSON string')]
    property Json: string read FJson write FJson;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Dot-notation path for get/keys/values/count/type. ' +
      'Examples: "user.name", "items[0]", "items[0].title". Empty = root')]
    property Path: string read FPath write FPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Second JSON object to merge into the first (for merge operation)')]
    property Json2: string read FJson2 write FJson2;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Indentation spaces for format operation (default: 2)')]
    property Indent: Integer read FIndent write FIndent;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TJsonQueryTool = class(TAiMCPToolBase<TJsonQueryParams>)
  private
    function NavigatePath(Root: TJSONValue; const Path: string): TJSONValue;
    function FormatJSON(const JSON: string; Spaces: Integer): string;
    procedure FlattenObject(Obj: TJSONValue; const Prefix: string;
      Collector: TJSONObject);
    function DeepMerge(Base, Override_: TJSONObject): TJSONObject;
    function JSONTypeName(V: TJSONValue): string;
  protected
    function ExecuteWithParams(const AParams: TJsonQueryParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Path navigator ─────────────────────────────────────────────────────────
//
//   Splits "a.b[2].c" into segments: "a", "b", 2 (idx), "c"
//   and traverses the JSON tree accordingly.

function TJsonQueryTool.NavigatePath(Root: TJSONValue;
  const Path: string): TJSONValue;
var
  Segs:  TArray<string>;
  Seg:   string;
  Cur:   TJSONValue;
  Key:   string;
  Idx:   Integer;
  BrPos: Integer;
begin
  Result := Root;
  if (Path = '') or (Path = '.') then Exit;

  Cur  := Root;
  Segs := Path.Split(['.']);

  for Seg in Segs do
  begin
    if Cur = nil then Exit(nil);

    // Check for array index: "name[0]" or "[0]"
    BrPos := Pos('[', Seg);
    if BrPos > 0 then
    begin
      Key := Copy(Seg, 1, BrPos - 1);
      Idx := StrToIntDef(
               Copy(Seg, BrPos + 1, Pos(']', Seg) - BrPos - 1), -1);

      // Navigate key part first (if any)
      if Key <> '' then
      begin
        if Cur is TJSONObject then
          Cur := TJSONObject(Cur).GetValue(Key)
        else
          Exit(nil);
      end;

      // Then navigate index
      if (Idx >= 0) and (Cur is TJSONArray) then
      begin
        if Idx < TJSONArray(Cur).Count then
          Cur := TJSONArray(Cur).Items[Idx]
        else
          Exit(nil);
      end else
        Exit(nil);
    end
    else
    begin
      // Plain key
      if Cur is TJSONObject then
        Cur := TJSONObject(Cur).GetValue(Seg)
      else
        Exit(nil);
    end;
  end;

  Result := Cur;
end;

// ── JSON formatter ─────────────────────────────────────────────────────────

function TJsonQueryTool.FormatJSON(const JSON: string; Spaces: Integer): string;
var
  Indent:   Integer;
  InStr:    Boolean;
  Esc:      Boolean;
  i:        Integer;
  c:        Char;
  Pad:      string;

  function Indentation: string;
  begin
    Result := StringOfChar(' ', Indent * Spaces);
  end;

begin
  Result  := '';
  Indent  := 0;
  InStr   := False;
  Esc     := False;
  if Spaces <= 0 then Spaces := 2;

  for i := 1 to Length(JSON) do
  begin
    c := JSON[i];

    if Esc then
    begin
      Result := Result + c;
      Esc    := False;
      Continue;
    end;

    if InStr then
    begin
      if c = '\' then Esc := True
      else if c = '"' then InStr := False;
      Result := Result + c;
      Continue;
    end;

    case c of
      '"': begin InStr := True; Result := Result + c; end;
      '{', '[':
        begin
          Inc(Indent);
          Result := Result + c + #10 + Indentation;
        end;
      '}', ']':
        begin
          Dec(Indent);
          Result := Result + #10 + Indentation + c;
        end;
      ',':
        begin
          Result := Result + c + #10 + Indentation;
        end;
      ':':
        begin
          Result := Result + ': ';
        end;
      ' ', #9, #10, #13: ; // skip existing whitespace
    else
      Result := Result + c;
    end;
  end;
end;

// ── Flatten ─────────────────────────────────────────────────────────────────

procedure TJsonQueryTool.FlattenObject(Obj: TJSONValue; const Prefix: string;
  Collector: TJSONObject);
var
  Pair: TJSONPair;
  Item: TJSONValue;
  i:    Integer;
  Key:  string;
begin
  if Obj is TJSONObject then
  begin
    for Pair in TJSONObject(Obj) do
    begin
      Key := IfThen(Prefix = '', Pair.JsonString.Value,
                    Prefix + '.' + Pair.JsonString.Value);
      FlattenObject(Pair.JsonValue, Key, Collector);
    end;
  end
  else if Obj is TJSONArray then
  begin
    for i := 0 to TJSONArray(Obj).Count - 1 do
    begin
      Item := TJSONArray(Obj).Items[i];
      Key  := Format('%s[%d]', [Prefix, i]);
      FlattenObject(Item, Key, Collector);
    end;
  end
  else
  begin
    if Prefix <> '' then
      Collector.AddPair(Prefix, Obj.Clone as TJSONValue);
  end;
end;

// ── Deep merge ──────────────────────────────────────────────────────────────

function TJsonQueryTool.DeepMerge(Base, Override_: TJSONObject): TJSONObject;
var
  Pair:     TJSONPair;
  BaseVal:  TJSONValue;
begin
  Result := Base.Clone as TJSONObject;
  for Pair in Override_ do
  begin
    BaseVal := Result.GetValue(Pair.JsonString.Value);
    if (BaseVal is TJSONObject) and (Pair.JsonValue is TJSONObject) then
    begin
      // Recursively merge nested objects
      var Merged := DeepMerge(TJSONObject(BaseVal), TJSONObject(Pair.JsonValue));
      Result.RemovePair(Pair.JsonString.Value).Free;
      Result.AddPair(Pair.JsonString.Value, Merged);
    end
    else
    begin
      // Override leaf value
      var Existing := Result.RemovePair(Pair.JsonString.Value);
      if Existing <> nil then Existing.Free;
      Result.AddPair(Pair.JsonString.Value, Pair.JsonValue.Clone as TJSONValue);
    end;
  end;
end;

// ── Type name ───────────────────────────────────────────────────────────────

function TJsonQueryTool.JSONTypeName(V: TJSONValue): string;
begin
  if V = nil             then Result := 'null'
  else if V is TJSONObject  then Result := 'object'
  else if V is TJSONArray   then Result := 'array'
  else if V is TJSONString  then Result := 'string'
  else if V is TJSONNumber  then Result := 'number'
  else if V is TJSONBool    then Result := 'boolean'
  else if V is TJSONNull    then Result := 'null'
  else                         Result := 'unknown';
end;

// ── Main execution ──────────────────────────────────────────────────────────

function TJsonQueryTool.ExecuteWithParams(const AParams: TJsonQueryParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Root: TJSONValue;
  R:    TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));

    // validate doesn't need parseable JSON to report the error
    if Op = 'validate' then
    begin
      R := TJSONObject.Create;
      R.AddPair('operation', Op);
      try
        Root := TJSONObject.ParseJSONValue(AParams.Json, True);
        if Root = nil then
        begin
          R.AddPair('valid', TJSONBool.Create(False));
          R.AddPair('error', 'Invalid JSON');
        end else begin
          R.AddPair('valid', TJSONBool.Create(True));
          R.AddPair('type',  JSONTypeName(Root));
          Root.Free;
        end;
      except
        on E: Exception do
        begin
          R.AddPair('valid', TJSONBool.Create(False));
          R.AddPair('error', E.Message);
        end;
      end;
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
      Exit;
    end;

    // format and minify work on the raw string
    if Op = 'format' then
    begin
      var Spaces := AParams.Indent;
      if Spaces <= 0 then Spaces := 2;
      var Formatted := FormatJSON(AParams.Json, Spaces);
      R := TJSONObject.Create;
      R.AddPair('operation', Op);
      R.AddPair('result',    Formatted);
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
      Exit;
    end;

    if Op = 'minify' then
    begin
      Root := TJSONObject.ParseJSONValue(AParams.Json, True);
      if Root = nil then raise Exception.Create('Invalid JSON input');
      try
        R := TJSONObject.Create;
        R.AddPair('operation', Op);
        R.AddPair('result',    Root.ToString);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      finally
        Root.Free;
      end;
      Exit;
    end;

    // All other ops need parsed JSON
    if AParams.Json = '' then
      raise Exception.Create('"json" is required');

    Root := TJSONObject.ParseJSONValue(AParams.Json, True);
    if Root = nil then raise Exception.Create('Invalid JSON input');

    try
      var Target := NavigatePath(Root, AParams.Path);

      if Op = 'get' then
      begin
        R := TJSONObject.Create;
        R.AddPair('path',  AParams.Path);
        if Target = nil then
        begin
          R.AddPair('found', TJSONBool.Create(False));
          R.AddPair('value', TJSONNull.Create);
        end else begin
          R.AddPair('found', TJSONBool.Create(True));
          R.AddPair('type',  JSONTypeName(Target));
          R.AddPair('value', Target.Clone as TJSONValue);
        end;
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'keys' then
      begin
        if not (Target is TJSONObject) then
          raise Exception.Create('Target at path is not an object');
        var Arr := TJSONArray.Create;
        for var Pair in TJSONObject(Target) do
          Arr.Add(Pair.JsonString.Value);
        R := TJSONObject.Create;
        R.AddPair('path',  AParams.Path);
        R.AddPair('count', TJSONNumber.Create(TJSONObject(Target).Count));
        R.AddPair('keys',  Arr);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'values' then
      begin
        var Arr := TJSONArray.Create;
        if Target is TJSONObject then
          for var Pair in TJSONObject(Target) do
            Arr.AddElement(Pair.JsonValue.Clone as TJSONValue)
        else if Target is TJSONArray then
          for var i := 0 to TJSONArray(Target).Count - 1 do
            Arr.AddElement(TJSONArray(Target).Items[i].Clone as TJSONValue)
        else
          raise Exception.Create('Target at path is not an object or array');
        R := TJSONObject.Create;
        R.AddPair('path',   AParams.Path);
        R.AddPair('count',  TJSONNumber.Create(Arr.Count));
        R.AddPair('values', Arr);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'count' then
      begin
        var N: Integer;
        if      Target is TJSONObject then N := TJSONObject(Target).Count
        else if Target is TJSONArray  then N := TJSONArray(Target).Count
        else                               N := 1;
        R := TJSONObject.Create;
        R.AddPair('path',  AParams.Path);
        R.AddPair('type',  JSONTypeName(Target));
        R.AddPair('count', TJSONNumber.Create(N));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'type' then
      begin
        R := TJSONObject.Create;
        R.AddPair('path', AParams.Path);
        R.AddPair('type', JSONTypeName(Target));
        if Target <> nil then
          R.AddPair('value', Target.Clone as TJSONValue);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'flatten' then
      begin
        if not (Root is TJSONObject) then
          raise Exception.Create('flatten requires a root JSON object');
        var Flat := TJSONObject.Create;
        FlattenObject(Root, '', Flat);
        R := TJSONObject.Create;
        R.AddPair('count',  TJSONNumber.Create(Flat.Count));
        R.AddPair('result', Flat);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'merge' then
      begin
        if AParams.Json2 = '' then
          raise Exception.Create('"json2" is required for merge');
        if not (Root is TJSONObject) then
          raise Exception.Create('merge requires json to be an object');
        var Root2 := TJSONObject.ParseJSONValue(AParams.Json2, True);
        if Root2 = nil then raise Exception.Create('Invalid JSON in json2');
        if not (Root2 is TJSONObject) then
        begin
          Root2.Free;
          raise Exception.Create('merge requires json2 to be an object');
        end;
        try
          var Merged := DeepMerge(TJSONObject(Root), TJSONObject(Root2));
          R := TJSONObject.Create;
          R.AddPair('result', Merged);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Root2.Free;
        end;
      end

      else
        raise Exception.CreateFmt(
          'Unknown operation: "%s". Valid: validate, format, minify, get, ' +
          'keys, values, count, type, flatten, merge', [Op]);

    finally
      Root.Free;
    end;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-json-query]: ' + E.Message)
        .Build;
  end;
end;

constructor TJsonQueryTool.Create;
begin
  inherited;
  FName        := 'mcp-json-query';
  FDescription :=
    'Query and manipulate JSON data. ' +
    'validate: check syntax. format: pretty-print. minify: compact. ' +
    'get: extract value at dot-notation path (e.g. "user.address.city", "items[0].name"). ' +
    'keys/values/count: inspect objects and arrays. ' +
    'type: get JSON type at path. flatten: flatten nested object. ' +
    'merge: deep-merge two JSON objects.';
end;

// ── Registration ───────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-json-query',
    function: IAiMCPTool
    begin
      Result := TJsonQueryTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-json-query] registered.');
end;

end.
