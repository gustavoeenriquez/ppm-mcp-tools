unit MCPTool.XML;

(*
  MCPTool.XML
  MCP tool: mcp-xml

  100% Delphi built-in XML support (Xml.XMLDoc / Xml.XMLIntf).
  Input: file path or inline XML string.

  Operations:
    parse    - validate XML, root tag, element/attribute count, max depth, encoding
    get      - navigate slash-path (root/items/item[0]) to node, return text or @attr
    find     - find all elements by tag name, return array (up to limit)
    format   - pretty-print XML with indentation
    minify   - strip whitespace between elements, compact output
    to_json  - recursive XML-to-JSON (same-name siblings -> arrays, @attr keys)
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  Xml.XMLDoc,
  Xml.XMLIntf;

type

  // ── Parameters ──────────────────────────────────────────────────────────────

  TXMLParams = class
  private
    FOperation:  string;
    FFilePath:   string;
    FXml:        string;
    FOutputPath: string;
    FPath:       string;
    FTag:        string;
    FAttribute:  string;
    FLimit:      Integer;
  public
    [AiMCPSchemaDescription('Operation: parse, get, find, format, minify, to_json')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Input XML file path')]
    property FilePath:   string  read FFilePath   write FFilePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Inline XML string (alternative to filePath)')]
    property Xml:        string  read FXml        write FXml;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Output file path (for format and minify operations)')]
    property OutputPath: string  read FOutputPath write FOutputPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Slash-path to element for get, e.g. "root/items/item[0]"')]
    property Path:       string  read FPath       write FPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Tag name for find operation')]
    property Tag:        string  read FTag        write FTag;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Attribute name to read for get operation (without @)')]
    property Attribute:  string  read FAttribute  write FAttribute;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max results for find (default 50)')]
    property Limit:      Integer read FLimit      write FLimit;
  end;

  // ── Tool ────────────────────────────────────────────────────────────────────

  TXMLTool = class(TAiMCPToolBase<TXMLParams>)
  private
    function LoadDoc(const P: TXMLParams): IXMLDocument;
    function GetXMLText(const P: TXMLParams): string;

    function OpParse(const P: TXMLParams): TJSONObject;
    function OpGet(const P: TXMLParams): TJSONObject;
    function OpFind(const P: TXMLParams): TJSONObject;
    function OpFormat(const P: TXMLParams): TJSONObject;
    function OpMinify(const P: TXMLParams): TJSONObject;
    function OpToJson(const P: TXMLParams): TJSONObject;

    function CountElements(Node: IXMLNode): Integer;
    function CountAttributes(Node: IXMLNode): Integer;
    function MaxDepth(Node: IXMLNode; Depth: Integer): Integer;
    function FindAll(Node: IXMLNode; const TagName: string;
      Results: TJSONArray; Limit: Integer): Integer;
    function NavPath(Root: IXMLNode; const Path: string): IXMLNode;
    function NodeToJSON(Node: IXMLNode): TJSONValue;
    function MinifyXML(const Src: string): string;
  protected
    function ExecuteWithParams(const AParams: TXMLParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Helpers ─────────────────────────────────────────────────────────────────

function TXMLTool.GetXMLText(const P: TXMLParams): string;
begin
  if P.FilePath <> '' then
  begin
    if not TFile.Exists(P.FilePath) then
      raise Exception.CreateFmt('File not found: "%s"', [P.FilePath]);
    Result := TFile.ReadAllText(P.FilePath, TEncoding.UTF8);
  end
  else if P.Xml <> '' then
    Result := P.Xml
  else
    raise Exception.Create('"filePath" or "xml" is required');
end;

function TXMLTool.LoadDoc(const P: TXMLParams): IXMLDocument;
var
  Src: string;
begin
  Src := GetXMLText(P);
  Result := TXMLDocument.Create(nil);
  Result.Active := True;
  Result.LoadFromXML(Src);
end;

function TXMLTool.CountElements(Node: IXMLNode): Integer;
var
  i: Integer;
begin
  Result := 0;
  if Node = nil then Exit;
  for i := 0 to Node.ChildNodes.Count - 1 do
  begin
    if Node.ChildNodes[i].NodeType = ntElement then
    begin
      Inc(Result);
      Inc(Result, CountElements(Node.ChildNodes[i]));
    end;
  end;
end;

function TXMLTool.CountAttributes(Node: IXMLNode): Integer;
var
  i: Integer;
begin
  Result := 0;
  if Node = nil then Exit;
  if Node.NodeType = ntElement then
    Result := Node.AttributeNodes.Count;
  for i := 0 to Node.ChildNodes.Count - 1 do
    Inc(Result, CountAttributes(Node.ChildNodes[i]));
end;

function TXMLTool.MaxDepth(Node: IXMLNode; Depth: Integer): Integer;
var
  i, D: Integer;
begin
  Result := Depth;
  if Node = nil then Exit;
  for i := 0 to Node.ChildNodes.Count - 1 do
    if Node.ChildNodes[i].NodeType = ntElement then
    begin
      D := MaxDepth(Node.ChildNodes[i], Depth + 1);
      if D > Result then Result := D;
    end;
end;

function TXMLTool.FindAll(Node: IXMLNode; const TagName: string;
  Results: TJSONArray; Limit: Integer): Integer;
var
  i:    Integer;
  Obj:  TJSONObject;
  Text: string;
begin
  Result := 0;
  if Node = nil then Exit;
  for i := 0 to Node.ChildNodes.Count - 1 do
  begin
    if Results.Count >= Limit then Break;
    if Node.ChildNodes[i].NodeType = ntElement then
    begin
      if SameText(Node.ChildNodes[i].NodeName, TagName) then
      begin
        Obj := TJSONObject.Create;
        Text := Trim(Node.ChildNodes[i].Text);
        if Length(Text) > 200 then
          Text := Copy(Text, 1, 200) + '...';
        Obj.AddPair('tag',  Node.ChildNodes[i].NodeName);
        Obj.AddPair('text', Text);
        if Node.ChildNodes[i].AttributeNodes.Count > 0 then
        begin
          var Attrs := TJSONObject.Create;
          var j: Integer;
          for j := 0 to Node.ChildNodes[i].AttributeNodes.Count - 1 do
            Attrs.AddPair(Node.ChildNodes[i].AttributeNodes[j].NodeName,
                          Node.ChildNodes[i].AttributeNodes[j].Text);
          Obj.AddPair('attributes', Attrs);
        end;
        Results.AddElement(Obj);
        Inc(Result);
      end;
      Inc(Result, FindAll(Node.ChildNodes[i], TagName, Results, Limit));
    end;
  end;
end;

function TXMLTool.NavPath(Root: IXMLNode; const Path: string): IXMLNode;
var
  Parts: TArray<string>;
  Seg:   string;
  Cur:   IXMLNode;
  Idx:   Integer;
  Name:  string;
  M:     TMatch;
  i:     Integer;
begin
  Result := nil;
  if Path = '' then
  begin
    Result := Root;
    Exit;
  end;

  Parts := Path.Split(['/']);
  Cur   := Root;

  for Seg in Parts do
  begin
    if Cur = nil then Exit;
    if Seg = '' then Continue;

    M    := TRegEx.Match(Seg, '^(.+)\[(\d+)\]$');
    if M.Success then
    begin
      Name := M.Groups[1].Value;
      Idx  := StrToInt(M.Groups[2].Value);
    end
    else
    begin
      Name := Seg;
      Idx  := 0;
    end;

    var Found := 0;
    var Next: IXMLNode := nil;
    for i := 0 to Cur.ChildNodes.Count - 1 do
    begin
      if (Cur.ChildNodes[i].NodeType = ntElement) and
         SameText(Cur.ChildNodes[i].NodeName, Name) then
      begin
        if Found = Idx then
        begin
          Next := Cur.ChildNodes[i];
          Break;
        end;
        Inc(Found);
      end;
    end;
    Cur := Next;
  end;

  Result := Cur;
end;

function TXMLTool.NodeToJSON(Node: IXMLNode): TJSONValue;
var
  Obj:        TJSONObject;
  i:          Integer;
  Child:      IXMLNode;
  ChildName:  string;
  Existing:   TJSONValue;
  Arr:        TJSONArray;
  ChildVal:   TJSONValue;
  ClonedVal:  TJSONValue;
  HasChildren: Boolean;
  TextContent: string;
begin
  if Node = nil then
    Exit(TJSONNull.Create);

  if Node.NodeType = ntText then
    Exit(TJSONString.Create(Node.Text));

  if Node.NodeType <> ntElement then
    Exit(TJSONNull.Create);

  Obj := TJSONObject.Create;

  // attributes as @name keys
  for i := 0 to Node.AttributeNodes.Count - 1 do
    Obj.AddPair('@' + Node.AttributeNodes[i].NodeName,
                Node.AttributeNodes[i].Text);

  // check for element children
  HasChildren := False;
  for i := 0 to Node.ChildNodes.Count - 1 do
    if Node.ChildNodes[i].NodeType = ntElement then
    begin
      HasChildren := True;
      Break;
    end;

  if not HasChildren then
  begin
    TextContent := Trim(Node.Text);
    if (Node.AttributeNodes.Count = 0) then
      Exit(TJSONString.Create(TextContent));
    // has attributes + text content
    if TextContent <> '' then
      Obj.AddPair('#text', TextContent);
    Exit(Obj);
  end;

  // element children — merge same-name into arrays
  for i := 0 to Node.ChildNodes.Count - 1 do
  begin
    Child := Node.ChildNodes[i];
    if Child.NodeType <> ntElement then Continue;

    ChildName := Child.NodeName;
    ChildVal  := NodeToJSON(Child);
    Existing  := Obj.GetValue(ChildName);

    if Existing = nil then
      Obj.AddPair(ChildName, ChildVal)
    else if Existing is TJSONArray then
      TJSONArray(Existing).AddElement(ChildVal)
    else
    begin
      // promote to array — clone existing value, remove old pair, build array
      ClonedVal := Obj.GetValue(ChildName).Clone as TJSONValue;
      Obj.RemovePair(ChildName).Free;
      Arr := TJSONArray.Create;
      Arr.AddElement(ClonedVal);
      Arr.AddElement(ChildVal);
      Obj.AddPair(ChildName, Arr);
    end;
  end;

  Result := Obj;
end;

function TXMLTool.MinifyXML(const Src: string): string;
begin
  // strip whitespace-only text nodes (whitespace between > and <)
  Result := TRegEx.Replace(Src, '>\s+<', '><');
  Result := Trim(Result);
end;

// ── Operations ───────────────────────────────────────────────────────────────

function TXMLTool.OpParse(const P: TXMLParams): TJSONObject;
var
  Doc:  IXMLDocument;
  Root: IXMLNode;
  Src:  string;
begin
  Src := GetXMLText(P);
  Doc := TXMLDocument.Create(nil);
  Doc.Active := True;
  try
    Doc.LoadFromXML(Src);
  except
    on E: Exception do
      raise Exception.Create('XML parse error: ' + E.Message);
  end;

  Root := Doc.DocumentElement;

  Result := TJSONObject.Create;
  Result.AddPair('valid', TJSONBool.Create(True));

  if P.FilePath <> '' then
    Result.AddPair('file', P.FilePath);

  if Root <> nil then
  begin
    Result.AddPair('root_tag',       Root.NodeName);
    Result.AddPair('element_count',  TJSONNumber.Create(CountElements(Root) + 1));
    Result.AddPair('attribute_count',TJSONNumber.Create(CountAttributes(Root)));
    Result.AddPair('max_depth',      TJSONNumber.Create(MaxDepth(Root, 1)));
  end;

  if Doc.Encoding <> '' then
    Result.AddPair('encoding', Doc.Encoding)
  else
    Result.AddPair('encoding', 'UTF-8');

  Result.AddPair('version', IfThen(Doc.Version <> '', Doc.Version, '1.0'));
  Result.AddPair('size_bytes', TJSONNumber.Create(Length(Src)));
end;

function TXMLTool.OpGet(const P: TXMLParams): TJSONObject;
var
  Doc:  IXMLDocument;
  Root: IXMLNode;
  Node: IXMLNode;
  Val:  string;
begin
  if P.Path = '' then
    raise Exception.Create('"path" is required for get');

  Doc  := LoadDoc(P);
  Root := Doc.DocumentElement;

  // strip leading root tag from path if present
  var PathStr := P.Path;
  var FirstSeg := PathStr;
  var SlashPos := Pos('/', PathStr);
  if SlashPos > 0 then
    FirstSeg := Copy(PathStr, 1, SlashPos - 1)
  else
    FirstSeg := PathStr;

  if SameText(FirstSeg, Root.NodeName) then
  begin
    if SlashPos > 0 then
      PathStr := Copy(PathStr, SlashPos + 1, MaxInt)
    else
      PathStr := '';
  end;

  Node := NavPath(Root, PathStr);

  Result := TJSONObject.Create;
  Result.AddPair('path', P.Path);

  if Node = nil then
  begin
    Result.AddPair('found', TJSONBool.Create(False));
    Exit;
  end;

  Result.AddPair('found', TJSONBool.Create(True));
  Result.AddPair('tag',   Node.NodeName);

  if P.Attribute <> '' then
  begin
    if Node.HasAttribute(P.Attribute) then
      Val := Node.Attributes[P.Attribute]
    else
      Val := '';
    Result.AddPair('attribute', P.Attribute);
    Result.AddPair('value',     Val);
  end
  else
  begin
    Result.AddPair('text', Trim(Node.Text));

    if Node.AttributeNodes.Count > 0 then
    begin
      var Attrs := TJSONObject.Create;
      var i: Integer;
      for i := 0 to Node.AttributeNodes.Count - 1 do
        Attrs.AddPair(Node.AttributeNodes[i].NodeName,
                      Node.AttributeNodes[i].Text);
      Result.AddPair('attributes', Attrs);
    end;
  end;
end;

function TXMLTool.OpFind(const P: TXMLParams): TJSONObject;
var
  Doc:     IXMLDocument;
  Results: TJSONArray;
  Lim:     Integer;
begin
  if P.Tag = '' then
    raise Exception.Create('"tag" is required for find');

  Lim := P.Limit;
  if Lim <= 0 then Lim := 50;

  Doc     := LoadDoc(P);
  Results := TJSONArray.Create;

  FindAll(Doc.DocumentElement, P.Tag, Results, Lim);

  Result := TJSONObject.Create;
  Result.AddPair('tag',   P.Tag);
  Result.AddPair('count', TJSONNumber.Create(Results.Count));
  Result.AddPair('items', Results);
end;

function TXMLTool.OpFormat(const P: TXMLParams): TJSONObject;
var
  Src:       string;
  Doc:       IXMLDocument;
  Formatted: string;
begin
  Src := GetXMLText(P);
  Doc := TXMLDocument.Create(nil);
  Doc.Active := True;
  Doc.LoadFromXML(Src);

  Doc.Options := Doc.Options + [doNodeAutoIndent];
  Doc.SaveToXML(Formatted);

  if P.OutputPath <> '' then
    TFile.WriteAllText(P.OutputPath, Formatted, TEncoding.UTF8);

  Result := TJSONObject.Create;
  if P.OutputPath <> '' then
    Result.AddPair('output', P.OutputPath);
  Result.AddPair('size_bytes', TJSONNumber.Create(Length(Formatted)));
  if P.OutputPath = '' then
    Result.AddPair('xml', Formatted);
end;

function TXMLTool.OpMinify(const P: TXMLParams): TJSONObject;
var
  Src:      string;
  Minified: string;
begin
  Src      := GetXMLText(P);
  Minified := MinifyXML(Src);

  if P.OutputPath <> '' then
    TFile.WriteAllText(P.OutputPath, Minified, TEncoding.UTF8);

  Result := TJSONObject.Create;
  Result.AddPair('original_bytes', TJSONNumber.Create(Length(Src)));
  Result.AddPair('minified_bytes', TJSONNumber.Create(Length(Minified)));
  if P.OutputPath <> '' then
    Result.AddPair('output', P.OutputPath)
  else
    Result.AddPair('xml', Minified);
end;

function TXMLTool.OpToJson(const P: TXMLParams): TJSONObject;
var
  Doc:  IXMLDocument;
  Root: IXMLNode;
  JVal: TJSONValue;
  JObj: TJSONObject;
begin
  Doc  := LoadDoc(P);
  Root := Doc.DocumentElement;

  JVal := NodeToJSON(Root);

  JObj := TJSONObject.Create;
  JObj.AddPair(Root.NodeName, JVal);

  Result := TJSONObject.Create;
  Result.AddPair('json', JObj);
end;

// ── Main dispatch ────────────────────────────────────────────────────────────

function TXMLTool.ExecuteWithParams(const AParams: TXMLParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Data: TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));

    if      Op = 'parse'   then Data := OpParse(AParams)
    else if Op = 'get'     then Data := OpGet(AParams)
    else if Op = 'find'    then Data := OpFind(AParams)
    else if Op = 'format'  then Data := OpFormat(AParams)
    else if Op = 'minify'  then Data := OpMinify(AParams)
    else if Op = 'to_json' then Data := OpToJson(AParams)
    else raise Exception.CreateFmt(
      'Unknown operation: "%s". Valid: parse, get, find, format, minify, to_json', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(Data.ToJSON).Build;
    Data.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-xml]: ' + E.Message)
        .Build;
  end;
end;

constructor TXMLTool.Create;
begin
  inherited;
  FName        := 'mcp-xml';
  FDescription :=
    'Parse and query XML documents. 100% Delphi built-in XML support, no external libs. ' +
    'parse: validate, root tag, element/attribute count, depth, encoding. ' +
    'get: navigate slash-path (root/items/item[0]) to read text or attribute. ' +
    'find: find all elements by tag name. ' +
    'format: pretty-print with indentation. ' +
    'minify: compact XML, strip whitespace between elements. ' +
    'to_json: convert XML to JSON (same-name siblings become arrays, attributes as @name).';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-xml',
    function: IAiMCPTool
    begin
      Result := TXMLTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-xml] registered.');
end;

end.
