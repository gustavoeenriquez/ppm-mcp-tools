unit MCPTool.Excel;

(*
  MCPTool.Excel
  MCP tool: mcp-excel

  Read and write Excel .xlsx files natively (no COM, no Excel required).
  Implemented via ZIP + XML (Open XML format).
  No external library dependencies beyond Delphi RTL.

  Operations:
    list_sheets - list all sheet names in the workbook
    read_sheet  - read a sheet as JSON (first row = headers if hasHeader=true)
    read_range  - read a specific cell range (A1:D10) as JSON array of arrays
    write_sheet - create/overwrite an .xlsx file from a JSON array of arrays
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Zip,
  System.Math,
  System.StrUtils,
  System.Variants,
  Xml.XMLDoc,
  Xml.XMLIntf;

type

  // ── Parameters ──────────────────────────────────────────────────────────────

  TExcelParams = class
  private
    FOperation: string;
    FFilePath:  string;
    FSheet:     string;
    FRange:     string;
    FData:      string;
    FHasHeader: Boolean;
    FMaxRows:   Integer;
  public
    [AiMCPSchemaDescription('Operation: list_sheets, read_sheet, read_range, write_sheet')]
    property Operation: string  read FOperation write FOperation;

    [AiMCPSchemaDescription('Path to the .xlsx file')]
    property FilePath:  string  read FFilePath  write FFilePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Sheet name to use (default: first sheet)')]
    property Sheet:     string  read FSheet     write FSheet;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Cell range like A1:D10 (for read_range; default: all cells)')]
    property Range:     string  read FRange     write FRange;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON array of arrays for write_sheet, e.g. [["Name","Age"],["Alice",30]]')]
    property Data:      string  read FData      write FData;

    [AiMCPOptional]
    [AiMCPSchemaDescription('First row is header row for read_sheet — returns objects instead of arrays (default: false)')]
    property HasHeader: Boolean read FHasHeader write FHasHeader;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum rows to return (default: 1000)')]
    property MaxRows:   Integer read FMaxRows   write FMaxRows;
  end;

  // ── Tool ────────────────────────────────────────────────────────────────────

  TExcelTool = class(TAiMCPToolBase<TExcelParams>)
  private
    function ReadEntry(const ZF: TZipFile; const EntryName: string;
      out Content: string): Boolean;
    function GetSheetList(const ZF: TZipFile;
      out SheetNames: TArray<string>; out SheetFiles: TArray<string>): Boolean;
    function LoadSharedStrings(const ZF: TZipFile): TArray<string>;
    function ColLetterToIndex(const Col: string): Integer;
    function IndexToColLetter(Col: Integer): string;
    function CellRefToColRow(const Ref: string; out Col, Row: Integer): Boolean;
    function NodeChildText(Node: IXMLNode; const ChildName: string): string;
    function ReadWorksheet(const ZF: TZipFile; const EntryPath: string;
      const SharedStrings: TArray<string>): TArray<TArray<string>>;
    function ParseRangeBounds(const ARange: string;
      out C1, R1, C2, R2: Integer): Boolean;
    function XmlEscape(const S: string): string;
    function WriteXLSX(const FilePath: string;
      const SheetName: string; const Rows: TJSONArray): Boolean;
    function DoListSheets(const P: TExcelParams): TJSONObject;
    function DoReadSheet(const P: TExcelParams): TJSONObject;
    function DoReadRange(const P: TExcelParams): TJSONObject;
    function DoWriteSheet(const P: TExcelParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TExcelParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── ZIP entry reader ─────────────────────────────────────────────────────────

function TExcelTool.ReadEntry(const ZF: TZipFile; const EntryName: string;
  out Content: string): Boolean;
var
  Stream: TStream;
  LH:     TZipHeader;
  SL:     TStringList;
  i:      Integer;
  CName:  string;
begin
  Content := '';
  Result  := False;
  for i := 0 to ZF.FileCount - 1 do
  begin
    CName := ZF.FileNames[i];
    CName := StringReplace(CName, '\', '/', [rfReplaceAll]);
    if SameText(CName, EntryName) then
    begin
      Stream := nil;
      ZF.Read(ZF.FileNames[i], Stream, LH);
      try
        if Stream <> nil then
        begin
          SL := TStringList.Create;
          try
            Stream.Position := 0;
            SL.LoadFromStream(Stream, TEncoding.UTF8);
            Content := SL.Text;
          finally
            SL.Free;
          end;
          Result := True;
        end;
      finally
        Stream.Free;
      end;
      Break;
    end;
  end;
end;

// ── Sheet list ───────────────────────────────────────────────────────────────

function TExcelTool.GetSheetList(const ZF: TZipFile;
  out SheetNames: TArray<string>; out SheetFiles: TArray<string>): Boolean;
var
  WbXml:    string;
  RelsXml:  string;
  Doc:      TXMLDocument;
  Root:     IXMLNode;
  Sheets:   IXMLNode;
  Rels:     IXMLNode;
  SheetRIds: TArray<string>;
  i, j:    Integer;
  RId:     string;
  Target:  string;
  NName:   OleVariant;
begin
  Result := False;
  SetLength(SheetNames, 0);
  SetLength(SheetFiles, 0);

  if not ReadEntry(ZF, 'xl/workbook.xml', WbXml)              then Exit;
  if not ReadEntry(ZF, 'xl/_rels/workbook.xml.rels', RelsXml) then Exit;

  try
    Doc := TXMLDocument.Create(nil);
    try
      Doc.LoadFromXML(WbXml);
      Doc.Active := True;
      Root   := Doc.DocumentElement;
      Sheets := nil;
      for i := 0 to Root.ChildNodes.Count - 1 do
        if Root.ChildNodes[i].LocalName = 'sheets' then
        begin
          Sheets := Root.ChildNodes[i];
          Break;
        end;
      if Sheets = nil then Exit;

      SetLength(SheetNames, Sheets.ChildNodes.Count);
      SetLength(SheetRIds,  Sheets.ChildNodes.Count);
      for i := 0 to Sheets.ChildNodes.Count - 1 do
      begin
        var SNode := Sheets.ChildNodes[i];
        NName         := SNode.Attributes['name'];
        SheetNames[i] := VarToStr(NName);
        var RIdVar    := SNode.Attributes['r:id'];
        if VarIsNull(RIdVar) or VarIsEmpty(RIdVar) then
          RIdVar := SNode.Attributes['id'];
        SheetRIds[i] := VarToStr(RIdVar);
      end;
    finally
      Doc.Free;
    end;
  except
    Exit;
  end;

  SetLength(SheetFiles, Length(SheetNames));
  try
    Doc := TXMLDocument.Create(nil);
    try
      Doc.LoadFromXML(RelsXml);
      Doc.Active := True;
      Rels := Doc.DocumentElement;
      for i := 0 to Length(SheetRIds) - 1 do
      begin
        SheetFiles[i] := '';
        for j := 0 to Rels.ChildNodes.Count - 1 do
        begin
          var Rel := Rels.ChildNodes[j];
          RId    := VarToStr(Rel.Attributes['Id']);
          Target := VarToStr(Rel.Attributes['Target']);
          if SameText(RId, SheetRIds[i]) then
          begin
            SheetFiles[i] := 'xl/' + Target;
            Break;
          end;
        end;
      end;
    finally
      Doc.Free;
    end;
  except
    Exit;
  end;

  Result := True;
end;

// ── Shared strings ───────────────────────────────────────────────────────────

function TExcelTool.LoadSharedStrings(const ZF: TZipFile): TArray<string>;
var
  SstXml: string;
  Doc:    TXMLDocument;
  Root:   IXMLNode;
  i, j:  Integer;
  SI:     IXMLNode;
  T:      IXMLNode;
  RText:  string;
begin
  SetLength(Result, 0);
  if not ReadEntry(ZF, 'xl/sharedStrings.xml', SstXml) then Exit;
  if SstXml = '' then Exit;

  try
    Doc := TXMLDocument.Create(nil);
    try
      Doc.LoadFromXML(SstXml);
      Doc.Active := True;
      Root := Doc.DocumentElement;

      SetLength(Result, Root.ChildNodes.Count);
      for i := 0 to Root.ChildNodes.Count - 1 do
      begin
        SI := Root.ChildNodes[i];
        T  := nil;
        for j := 0 to SI.ChildNodes.Count - 1 do
          if SI.ChildNodes[j].LocalName = 't' then
          begin
            T := SI.ChildNodes[j];
            Break;
          end;
        if T <> nil then
          Result[i] := T.Text
        else
        begin
          RText := '';
          for j := 0 to SI.ChildNodes.Count - 1 do
            if SI.ChildNodes[j].LocalName = 'r' then
            begin
              var TNode: IXMLNode := nil;
              var k: Integer;
              for k := 0 to SI.ChildNodes[j].ChildNodes.Count - 1 do
                if SI.ChildNodes[j].ChildNodes[k].LocalName = 't' then
                begin
                  TNode := SI.ChildNodes[j].ChildNodes[k];
                  Break;
                end;
              if TNode <> nil then
                RText := RText + TNode.Text;
            end;
          Result[i] := RText;
        end;
      end;
    finally
      Doc.Free;
    end;
  except
    SetLength(Result, 0);
  end;
end;

// ── Column helpers ───────────────────────────────────────────────────────────

function TExcelTool.ColLetterToIndex(const Col: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(Col) do
    Result := Result * 26 + (Ord(UpCase(Col[i])) - Ord('A') + 1);
end;

function TExcelTool.IndexToColLetter(Col: Integer): string;
begin
  Result := '';
  while Col > 0 do
  begin
    Result := Chr(Ord('A') + (Col - 1) mod 26) + Result;
    Col    := (Col - 1) div 26;
  end;
end;

function TExcelTool.CellRefToColRow(const Ref: string; out Col, Row: Integer): Boolean;
var
  ColStr, RowStr: string;
  i: Integer;
begin
  ColStr := ''; RowStr := '';
  for i := 1 to Length(Ref) do
    if CharInSet(Ref[i], ['A'..'Z', 'a'..'z']) then
      ColStr := ColStr + Ref[i]
    else
      RowStr := RowStr + Ref[i];
  Row    := StrToIntDef(RowStr, 0);
  Col    := ColLetterToIndex(ColStr);
  Result := (Row > 0) and (Col > 0);
end;

function TExcelTool.NodeChildText(Node: IXMLNode; const ChildName: string): string;
var
  i: Integer;
begin
  Result := '';
  if Node = nil then Exit;
  for i := 0 to Node.ChildNodes.Count - 1 do
    if Node.ChildNodes[i].LocalName = ChildName then
    begin
      Result := Node.ChildNodes[i].Text;
      Exit;
    end;
end;

// ── Worksheet reader ─────────────────────────────────────────────────────────

function TExcelTool.ReadWorksheet(const ZF: TZipFile; const EntryPath: string;
  const SharedStrings: TArray<string>): TArray<TArray<string>>;
var
  WsXml:    string;
  Doc:      TXMLDocument;
  Root:     IXMLNode;
  SDNode:   IXMLNode;
  RowNode:  IXMLNode;
  CNode:    IXMLNode;
  IsNode:   IXMLNode;
  CRef:     string;
  CType:    string;
  CVal:     string;
  Col, Row: Integer;
  MaxCol:   Integer;
  MaxRow:   Integer;
  SIdx:     Integer;
  i, j, k:  Integer;
begin
  SetLength(Result, 0);
  if not ReadEntry(ZF, EntryPath, WsXml) then Exit;

  try
    Doc := TXMLDocument.Create(nil);
    try
      Doc.LoadFromXML(WsXml);
      Doc.Active := True;
      Root := Doc.DocumentElement;

      SDNode := nil;
      for i := 0 to Root.ChildNodes.Count - 1 do
        if Root.ChildNodes[i].LocalName = 'sheetData' then
        begin
          SDNode := Root.ChildNodes[i];
          Break;
        end;
      if SDNode = nil then Exit;

      // First pass: find dimensions
      MaxRow := 0; MaxCol := 0;
      for i := 0 to SDNode.ChildNodes.Count - 1 do
      begin
        RowNode := SDNode.ChildNodes[i];
        if RowNode.LocalName <> 'row' then Continue;
        Row := StrToIntDef(VarToStr(RowNode.Attributes['r']), 0);
        if Row > MaxRow then MaxRow := Row;
        for j := 0 to RowNode.ChildNodes.Count - 1 do
        begin
          CNode := RowNode.ChildNodes[j];
          if CNode.LocalName <> 'c' then Continue;
          CRef := VarToStr(CNode.Attributes['r']);
          if CellRefToColRow(CRef, Col, Row) then
            if Col > MaxCol then MaxCol := Col;
        end;
      end;

      if (MaxRow = 0) or (MaxCol = 0) then Exit;

      SetLength(Result, MaxRow);
      for i := 0 to MaxRow - 1 do
      begin
        SetLength(Result[i], MaxCol);
        for j := 0 to MaxCol - 1 do Result[i][j] := '';
      end;

      // Second pass: fill values
      for i := 0 to SDNode.ChildNodes.Count - 1 do
      begin
        RowNode := SDNode.ChildNodes[i];
        if RowNode.LocalName <> 'row' then Continue;
        for j := 0 to RowNode.ChildNodes.Count - 1 do
        begin
          CNode := RowNode.ChildNodes[j];
          if CNode.LocalName <> 'c' then Continue;
          CRef  := VarToStr(CNode.Attributes['r']);
          CType := VarToStr(CNode.Attributes['t']);
          if not CellRefToColRow(CRef, Col, Row) then Continue;

          if CType = 'inlineStr' then
          begin
            IsNode := nil;
            for k := 0 to CNode.ChildNodes.Count - 1 do
              if CNode.ChildNodes[k].LocalName = 'is' then
              begin
                IsNode := CNode.ChildNodes[k];
                Break;
              end;
            if IsNode <> nil then CVal := NodeChildText(IsNode, 't')
            else CVal := '';
          end
          else if CType = 's' then
          begin
            CVal := NodeChildText(CNode, 'v');
            SIdx := StrToIntDef(CVal, -1);
            if (SIdx >= 0) and (SIdx < Length(SharedStrings)) then
              CVal := SharedStrings[SIdx]
            else
              CVal := '';
          end
          else
            CVal := NodeChildText(CNode, 'v');

          if (Row >= 1) and (Row <= MaxRow) and (Col >= 1) and (Col <= MaxCol) then
            Result[Row - 1][Col - 1] := CVal;
        end;
      end;

    finally
      Doc.Free;
    end;
  except
    SetLength(Result, 0);
  end;
end;

// ── Range parsing ────────────────────────────────────────────────────────────

function TExcelTool.ParseRangeBounds(const ARange: string;
  out C1, R1, C2, R2: Integer): Boolean;
var
  Parts: TArray<string>;
begin
  Result := False;
  if ARange = '' then Exit;
  Parts := ARange.Split([':']);
  if Length(Parts) <> 2 then Exit;
  Result := CellRefToColRow(Parts[0], C1, R1) and
            CellRefToColRow(Parts[1], C2, R2);
end;

// ── XLSX writer ──────────────────────────────────────────────────────────────

function TExcelTool.XmlEscape(const S: string): string;
begin
  Result := S.Replace('&',  '&amp;')
             .Replace('<',  '&lt;')
             .Replace('>',  '&gt;')
             .Replace('"',  '&quot;')
             .Replace(#10, '&#10;')
             .Replace(#13, '&#13;');
end;

function TExcelTool.WriteXLSX(const FilePath: string;
  const SheetName: string; const Rows: TJSONArray): Boolean;
const
  ContentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
    '<Default Extension="xml" ContentType="application/xml"/>' +
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
    '</Types>';
  DotRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
    '</Relationships>';
  WbRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
    '</Relationships>';
var
  ZF:            TZipFile;
  WsSB:          TStringBuilder;
  RowArr:        TJSONArray;
  CellVal:       string;
  IsNum:         Boolean;
  DblVal:        Double;
  RowIdx:        Integer;
  ColIdx:        Integer;
  CellRef:       string;
  Workbook:      string;
  SafeSheetName: string;

  procedure AddEntry(const Entry, Content: string);
  var
    MS:    TMemoryStream;
    Bytes: TBytes;
  begin
    MS := TMemoryStream.Create;
    try
      Bytes := TEncoding.UTF8.GetBytes(Content);
      if Length(Bytes) > 0 then
        MS.WriteBuffer(Bytes[0], Length(Bytes));
      MS.Position := 0;
      ZF.Add(MS, Entry);
    finally
      MS.Free;
    end;
  end;

begin
  Result        := False;
  SafeSheetName := XmlEscape(SheetName);
  Workbook      :=
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' +
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
    '<sheets><sheet name="' + SafeSheetName + '" sheetId="1" r:id="rId1"/></sheets>' +
    '</workbook>';

  WsSB := TStringBuilder.Create;
  try
    WsSB.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    WsSB.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    WsSB.Append('<sheetData>');

    for RowIdx := 0 to Rows.Count - 1 do
    begin
      if not (Rows.Items[RowIdx] is TJSONArray) then Continue;
      RowArr := Rows.Items[RowIdx] as TJSONArray;
      WsSB.Append('<row r="');
      WsSB.Append(IntToStr(RowIdx + 1));
      WsSB.Append('">');

      for ColIdx := 0 to RowArr.Count - 1 do
      begin
        CellRef := IndexToColLetter(ColIdx + 1) + IntToStr(RowIdx + 1);
        CellVal := RowArr.Items[ColIdx].Value;
        IsNum   := (RowArr.Items[ColIdx] is TJSONNumber) or
                   ((CellVal <> '') and TryStrToFloat(CellVal, DblVal));

        if IsNum then
        begin
          WsSB.Append('<c r="');
          WsSB.Append(CellRef);
          WsSB.Append('"><v>');
          WsSB.Append(CellVal);
          WsSB.Append('</v></c>');
        end
        else
        begin
          WsSB.Append('<c r="');
          WsSB.Append(CellRef);
          WsSB.Append('" t="inlineStr"><is><t>');
          WsSB.Append(XmlEscape(CellVal));
          WsSB.Append('</t></is></c>');
        end;
      end;

      WsSB.Append('</row>');
    end;

    WsSB.Append('</sheetData></worksheet>');

    ZF := TZipFile.Create;
    try
      ZF.Open(FilePath, zmWrite);
      AddEntry('[Content_Types].xml',        ContentTypes);
      AddEntry('_rels/.rels',                DotRels);
      AddEntry('xl/workbook.xml',            Workbook);
      AddEntry('xl/_rels/workbook.xml.rels', WbRels);
      AddEntry('xl/worksheets/sheet1.xml',   WsSB.ToString);
      ZF.Close;
      Result := True;
    finally
      ZF.Free;
    end;
  finally
    WsSB.Free;
  end;
end;

// ── Operations ───────────────────────────────────────────────────────────────

function TExcelTool.DoListSheets(const P: TExcelParams): TJSONObject;
var
  ZF:         TZipFile;
  SheetNames: TArray<string>;
  SheetFiles: TArray<string>;
  Arr:        TJSONArray;
  i:          Integer;
begin
  if P.FilePath = '' then raise Exception.Create('"filePath" is required');
  if not FileExists(P.FilePath) then
    raise Exception.CreateFmt('File not found: %s', [P.FilePath]);

  ZF := TZipFile.Create;
  try
    ZF.Open(P.FilePath, zmRead);
    if not GetSheetList(ZF, SheetNames, SheetFiles) then
      raise Exception.Create('Could not read sheet list from workbook');
    Arr := TJSONArray.Create;
    for i := 0 to High(SheetNames) do
      Arr.Add(SheetNames[i]);
  finally
    ZF.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('file',   P.FilePath);
  Result.AddPair('sheets', Arr);
  Result.AddPair('count',  TJSONNumber.Create(Arr.Count));
end;

function TExcelTool.DoReadSheet(const P: TExcelParams): TJSONObject;
var
  ZF:         TZipFile;
  SheetNames: TArray<string>;
  SheetFiles: TArray<string>;
  SharedStr:  TArray<string>;
  Grid:       TArray<TArray<string>>;
  SheetIdx:   Integer;
  Headers:    TArray<string>;
  RowObj:     TJSONObject;
  RowArr:     TJSONArray;
  DataArr:    TJSONArray;
  i, j:      Integer;
  Limit:      Integer;
begin
  if P.FilePath = '' then raise Exception.Create('"filePath" is required');
  if not FileExists(P.FilePath) then
    raise Exception.CreateFmt('File not found: %s', [P.FilePath]);

  Limit := P.MaxRows;
  if Limit <= 0 then Limit := 1000;

  ZF := TZipFile.Create;
  try
    ZF.Open(P.FilePath, zmRead);
    if not GetSheetList(ZF, SheetNames, SheetFiles) then
      raise Exception.Create('Could not read workbook sheets');
    if Length(SheetNames) = 0 then
      raise Exception.Create('Workbook has no sheets');

    SheetIdx := 0;
    if P.Sheet <> '' then
    begin
      SheetIdx := -1;
      for i := 0 to High(SheetNames) do
        if SameText(SheetNames[i], P.Sheet) then
        begin
          SheetIdx := i;
          Break;
        end;
      if SheetIdx = -1 then
        raise Exception.CreateFmt('Sheet not found: %s', [P.Sheet]);
    end;

    SharedStr := LoadSharedStrings(ZF);
    Grid      := ReadWorksheet(ZF, SheetFiles[SheetIdx], SharedStr);
  finally
    ZF.Free;
  end;

  DataArr := TJSONArray.Create;

  if (Length(Grid) > 0) and P.HasHeader then
  begin
    SetLength(Headers, Length(Grid[0]));
    for j := 0 to High(Grid[0]) do
      Headers[j] := Grid[0][j];

    for i := 1 to Min(High(Grid), Limit) do
    begin
      RowObj := TJSONObject.Create;
      for j := 0 to High(Headers) do
      begin
        var Val := '';
        if j < Length(Grid[i]) then Val := Grid[i][j];
        RowObj.AddPair(Headers[j], Val);
      end;
      DataArr.AddElement(RowObj);
    end;
  end
  else
  begin
    for i := 0 to Min(High(Grid), Limit - 1) do
    begin
      RowArr := TJSONArray.Create;
      for j := 0 to High(Grid[i]) do
        RowArr.Add(Grid[i][j]);
      DataArr.AddElement(RowArr);
    end;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('file',       P.FilePath);
  Result.AddPair('sheet',      SheetNames[SheetIdx]);
  Result.AddPair('has_header', TJSONBool.Create(P.HasHeader));
  Result.AddPair('rows',       DataArr);
  Result.AddPair('count',      TJSONNumber.Create(DataArr.Count));
end;

function TExcelTool.DoReadRange(const P: TExcelParams): TJSONObject;
var
  ZF:           TZipFile;
  SheetNames:   TArray<string>;
  SheetFiles:   TArray<string>;
  SharedStr:    TArray<string>;
  Grid:         TArray<TArray<string>>;
  SheetIdx:     Integer;
  C1,R1,C2,R2:  Integer;
  DataArr:      TJSONArray;
  RowArr:       TJSONArray;
  i, j:        Integer;
begin
  if P.FilePath = '' then raise Exception.Create('"filePath" is required');
  if not FileExists(P.FilePath) then
    raise Exception.CreateFmt('File not found: %s', [P.FilePath]);

  ZF := TZipFile.Create;
  try
    ZF.Open(P.FilePath, zmRead);
    if not GetSheetList(ZF, SheetNames, SheetFiles) then
      raise Exception.Create('Could not read workbook sheets');

    SheetIdx := 0;
    if P.Sheet <> '' then
      for i := 0 to High(SheetNames) do
        if SameText(SheetNames[i], P.Sheet) then
        begin
          SheetIdx := i;
          Break;
        end;

    SharedStr := LoadSharedStrings(ZF);
    Grid      := ReadWorksheet(ZF, SheetFiles[SheetIdx], SharedStr);
  finally
    ZF.Free;
  end;

  if not ParseRangeBounds(P.Range, C1, R1, C2, R2) then
  begin
    R1 := 1; C1 := 1;
    R2 := Length(Grid);
    if R2 > 0 then C2 := Length(Grid[0]) else C2 := 0;
  end;

  DataArr := TJSONArray.Create;
  for i := R1 - 1 to Min(R2 - 1, High(Grid)) do
  begin
    RowArr := TJSONArray.Create;
    for j := C1 - 1 to C2 - 1 do
    begin
      var Val := '';
      if (i >= 0) and (i < Length(Grid)) and
         (j >= 0) and (j < Length(Grid[i])) then
        Val := Grid[i][j];
      RowArr.Add(Val);
    end;
    DataArr.AddElement(RowArr);
  end;

  Result := TJSONObject.Create;
  Result.AddPair('file',  P.FilePath);
  Result.AddPair('sheet', SheetNames[SheetIdx]);
  if P.Range <> '' then Result.AddPair('range', P.Range);
  Result.AddPair('rows',  DataArr);
  Result.AddPair('count', TJSONNumber.Create(DataArr.Count));
end;

function TExcelTool.DoWriteSheet(const P: TExcelParams): TJSONObject;
var
  DataArr:   TJSONArray;
  Parsed:    TJSONValue;
  SheetName: string;
begin
  if P.FilePath = '' then raise Exception.Create('"filePath" is required');
  if P.Data     = '' then
    raise Exception.Create('"data" is required for write_sheet (JSON array of arrays)');

  SheetName := P.Sheet;
  if SheetName = '' then SheetName := 'Sheet1';

  Parsed := TJSONObject.ParseJSONValue(P.Data);
  if not (Parsed is TJSONArray) then
  begin
    Parsed.Free;
    raise Exception.Create('"data" must be a JSON array of arrays');
  end;

  DataArr := Parsed as TJSONArray;
  try
    if not WriteXLSX(P.FilePath, SheetName, DataArr) then
      raise Exception.Create('Failed to write XLSX file');
  finally
    DataArr.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('file',  P.FilePath);
  Result.AddPair('sheet', SheetName);
  Result.AddPair('ok',    TJSONBool.Create(True));
end;

// ── Main dispatch ────────────────────────────────────────────────────────────

function TExcelTool.ExecuteWithParams(const AParams: TExcelParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list_sheets' then R := DoListSheets(AParams)
    else if Op = 'read_sheet'  then R := DoReadSheet(AParams)
    else if Op = 'read_range'  then R := DoReadRange(AParams)
    else if Op = 'write_sheet' then R := DoWriteSheet(AParams)
    else raise Exception.CreateFmt(
      'Unknown operation: "%s". Valid: list_sheets, read_sheet, read_range, write_sheet', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-excel]: ' + E.Message)
        .Build;
  end;
end;

constructor TExcelTool.Create;
begin
  inherited;
  FName        := 'mcp-excel';
  FDescription :=
    'Read and write Excel .xlsx files natively (no Excel or COM required). ' +
    'list_sheets: list all sheet names (param: filePath). ' +
    'read_sheet: read sheet as JSON; hasHeader=true returns objects keyed by header, ' +
    'false returns arrays; params: filePath, sheet?, hasHeader?, maxRows?. ' +
    'read_range: read A1:D10 range as JSON arrays; params: filePath, sheet?, range?. ' +
    'write_sheet: create .xlsx from JSON array of arrays; params: filePath, data, sheet?. ' +
    'data format: [["Name","Age"],["Alice",30]].';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-excel',
    function: IAiMCPTool
    begin
      Result := TExcelTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-excel] registered.');
end;

end.
