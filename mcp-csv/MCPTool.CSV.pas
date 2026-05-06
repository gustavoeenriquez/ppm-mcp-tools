unit MCPTool.CSV;

(*
  MCPTool.CSV
  MCP tool: mcp-csv

  Pure Delphi RTL — no external dependencies.

  Operations:
    read   - parse CSV, return headers and rows as JSON
    write  - write JSON rows array to CSV file
    filter - filter rows by column condition, return or save result
    stats  - numeric statistics for a column (or all columns)
    head   - return first N rows
    tail   - return last N rows
    sort   - sort rows by a column, return or save result

  Parameters:
    operation  (required) - read, write, filter, stats, head, tail, sort
    filePath   - input CSV file path
    outputPath - output CSV file path (write, filter, sort)
    delimiter  - field separator character (default comma)
    hasHeader  - send true when first row is a header (default false)
    rows       - JSON array of row-arrays for write: [["h1","h2"],["v1","v2"]]
    column     - column name (requires hasHeader=true) or 0-based integer index
    value      - comparison value for filter
    filterOp   - filter condition: eq, ne, lt, gt, le, ge, contains (default eq)
    limit      - max rows to return for read/filter/head/tail (default 100)
    descending - sort descending (default false = ascending)
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

type

  // ── Parameters ──────────────────────────────────────────────────────────────

  TCSVParams = class
  private
    FOperation:  string;
    FFilePath:   string;
    FOutputPath: string;
    FDelimiter:  string;
    FHasHeader:  Boolean;
    FRows:       string;
    FColumn:     string;
    FValue:      string;
    FFilterOp:   string;
    FLimit:      Integer;
    FDescending: Boolean;
  public
    [AiMCPSchemaDescription('Operation: read, write, filter, stats, head, tail, sort')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Input CSV file path')]
    property FilePath:   string  read FFilePath   write FFilePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Output CSV file path (write, filter, sort)')]
    property OutputPath: string  read FOutputPath write FOutputPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Field separator character (default: comma)')]
    property Delimiter:  string  read FDelimiter  write FDelimiter;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Send true when first row is a header row (default false)')]
    property HasHeader:  Boolean read FHasHeader  write FHasHeader;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON array of row-arrays for write: [["h1","h2"],["v1","v2"]]')]
    property Rows:       string  read FRows       write FRows;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Column name (with hasHeader=true) or 0-based index (filter/stats/sort)')]
    property Column:     string  read FColumn     write FColumn;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Comparison value for filter')]
    property Value:      string  read FValue      write FValue;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Filter condition: eq, ne, lt, gt, le, ge, contains (default eq)')]
    property FilterOp:   string  read FFilterOp   write FFilterOp;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max rows to return for read/filter/head/tail (default 100)')]
    property Limit:      Integer read FLimit      write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Sort descending (default false = ascending)')]
    property Descending: Boolean read FDescending write FDescending;
  end;

  // ── Tool ────────────────────────────────────────────────────────────────────

  TCSVTool = class(TAiMCPToolBase<TCSVParams>)
  private
    function GetDelim(const S: string): Char;
    function ParseLine(const ALine: string; ADelim: Char): TArray<string>;
    function QuoteField(const S: string; ADelim: Char): string;
    function BuildLine(const ARow: TArray<string>; ADelim: Char): string;
    procedure ReadFile(const APath: string; ADelim: Char; AHasHeader: Boolean;
      out AHeaders: TArray<string>; out ARows: TArray<TArray<string>>);
    procedure WriteFile(const APath: string; ADelim: Char;
      const AHeaders: TArray<string>; const ARows: TArray<TArray<string>>);
    function ColIndex(const AHeaders: TArray<string>; const ACol: string): Integer;
    function MakeResult(const AHeaders: TArray<string>; const ARows: TArray<TArray<string>>;
      ATotal, AReturned: Integer): TJSONObject;

    function OpRead(const P: TCSVParams): TJSONObject;
    function OpWrite(const P: TCSVParams): TJSONObject;
    function OpFilter(const P: TCSVParams): TJSONObject;
    function OpStats(const P: TCSVParams): TJSONObject;
    function OpHead(const P: TCSVParams): TJSONObject;
    function OpTail(const P: TCSVParams): TJSONObject;
    function OpSort(const P: TCSVParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TCSVParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── CSV helpers ──────────────────────────────────────────────────────────────

function TCSVTool.GetDelim(const S: string): Char;
begin
  if S = '' then Result := ','
  else if S = '\t' then Result := #9
  else Result := S[1];
end;

function TCSVTool.ParseLine(const ALine: string; ADelim: Char): TArray<string>;
var
  Fields: TList<string>;
  Sb:     TStringBuilder;
  i, Len: Integer;
  InQ:    Boolean;
  Ch:     Char;
begin
  Fields := TList<string>.Create;
  Sb     := TStringBuilder.Create;
  try
    InQ := False;
    i   := 1;
    Len := Length(ALine);
    while i <= Len do
    begin
      Ch := ALine[i];
      if InQ then
      begin
        if (Ch = '"') and (i < Len) and (ALine[i + 1] = '"') then
        begin
          Sb.Append('"');
          Inc(i);
        end
        else if Ch = '"' then
          InQ := False
        else
          Sb.Append(Ch);
      end
      else
      begin
        if Ch = '"' then
          InQ := True
        else if Ch = ADelim then
        begin
          Fields.Add(Sb.ToString);
          Sb.Clear;
        end
        else
          Sb.Append(Ch);
      end;
      Inc(i);
    end;
    Fields.Add(Sb.ToString);
    Result := Fields.ToArray;
  finally
    Sb.Free;
    Fields.Free;
  end;
end;

function TCSVTool.QuoteField(const S: string; ADelim: Char): string;
var
  NeedsQuote: Boolean;
begin
  NeedsQuote := (Pos(ADelim, S) > 0) or (Pos('"', S) > 0) or
                (Pos(#10, S) > 0) or (Pos(#13, S) > 0);
  if NeedsQuote then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

function TCSVTool.BuildLine(const ARow: TArray<string>; ADelim: Char): string;
var
  Sb: TStringBuilder;
  i:  Integer;
begin
  Sb := TStringBuilder.Create;
  try
    for i := 0 to High(ARow) do
    begin
      if i > 0 then Sb.Append(ADelim);
      Sb.Append(QuoteField(ARow[i], ADelim));
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

procedure TCSVTool.ReadFile(const APath: string; ADelim: Char; AHasHeader: Boolean;
  out AHeaders: TArray<string>; out ARows: TArray<TArray<string>>);
var
  Lines:   TStringList;
  RowList: TList<TArray<string>>;
  i:       Integer;
  Line:    string;
  Row:     TArray<string>;
begin
  if APath = '' then raise Exception.Create('"filePath" is required');
  if not TFile.Exists(APath) then
    raise Exception.CreateFmt('File not found: "%s"', [APath]);

  Lines   := TStringList.Create;
  RowList := TList<TArray<string>>.Create;
  try
    Lines.LoadFromFile(APath, TEncoding.UTF8);
    i := 0;

    // Header row
    AHeaders := nil;
    if AHasHeader and (Lines.Count > 0) then
    begin
      Line := Lines[0];
      if Line <> '' then AHeaders := ParseLine(Line, ADelim);
      i := 1;
    end;

    // Data rows
    while i < Lines.Count do
    begin
      Line := Lines[i];
      if Line <> '' then
      begin
        Row := ParseLine(Line, ADelim);
        RowList.Add(Row);
      end;
      Inc(i);
    end;

    ARows := RowList.ToArray;
  finally
    RowList.Free;
    Lines.Free;
  end;
end;

procedure TCSVTool.WriteFile(const APath: string; ADelim: Char;
  const AHeaders: TArray<string>; const ARows: TArray<TArray<string>>);
var
  Lines: TStringList;
  i:     Integer;
begin
  Lines := TStringList.Create;
  try
    if Length(AHeaders) > 0 then
      Lines.Add(BuildLine(AHeaders, ADelim));
    for i := 0 to High(ARows) do
      Lines.Add(BuildLine(ARows[i], ADelim));
    Lines.SaveToFile(APath, TEncoding.UTF8);
  finally
    Lines.Free;
  end;
end;

function TCSVTool.ColIndex(const AHeaders: TArray<string>; const ACol: string): Integer;
var
  i: Integer;
begin
  if ACol = '' then
    raise Exception.Create('"column" is required for this operation');

  // Try numeric index first
  if TryStrToInt(ACol, Result) then
  begin
    if (Result < 0) then
      raise Exception.CreateFmt('Column index %d is negative', [Result]);
    Exit;
  end;

  // Search by name in headers
  for i := 0 to High(AHeaders) do
    if SameText(AHeaders[i], ACol) then Exit(i);

  raise Exception.CreateFmt('Column "%s" not found. Available: %s',
    [ACol, String.Join(', ', AHeaders)]);
end;

function TCSVTool.MakeResult(const AHeaders: TArray<string>; const ARows: TArray<TArray<string>>;
  ATotal, AReturned: Integer): TJSONObject;
var
  HeaderArr: TJSONArray;
  RowsArr:   TJSONArray;
  RowArr:    TJSONArray;
  i, j:      Integer;
begin
  HeaderArr := TJSONArray.Create;
  for i := 0 to High(AHeaders) do
    HeaderArr.Add(AHeaders[i]);

  RowsArr := TJSONArray.Create;
  for i := 0 to AReturned - 1 do
  begin
    RowArr := TJSONArray.Create;
    for j := 0 to High(ARows[i]) do
      RowArr.Add(ARows[i][j]);
    RowsArr.AddElement(RowArr);
  end;

  Result := TJSONObject.Create;
  Result.AddPair('headers',    HeaderArr);
  Result.AddPair('row_count',  TJSONNumber.Create(ATotal));
  Result.AddPair('returned',   TJSONNumber.Create(AReturned));
  Result.AddPair('truncated',  TJSONBool.Create(AReturned < ATotal));
  Result.AddPair('rows',       RowsArr);
end;

// ── Operations ───────────────────────────────────────────────────────────────

function TCSVTool.OpRead(const P: TCSVParams): TJSONObject;
var
  D:      Char;
  H:      TArray<string>;
  R:      TArray<TArray<string>>;
  Lim:    Integer;
begin
  D   := GetDelim(P.Delimiter);
  Lim := P.Limit;
  if Lim <= 0 then Lim := 100;

  ReadFile(P.FilePath, D, P.HasHeader, H, R);

  Result := MakeResult(H, R, Length(R), Min(Lim, Length(R)));
  Result.AddPair('file', P.FilePath);
end;

function TCSVTool.OpWrite(const P: TCSVParams): TJSONObject;
var
  D:       Char;
  JV:      TJSONValue;
  JArr:    TJSONArray;
  JRow:    TJSONArray;
  Headers: TArray<string>;
  Rows:    TArray<TArray<string>>;
  Row:     TArray<string>;
  i, j:   Integer;
  StartRow: Integer;
begin
  if P.OutputPath = '' then raise Exception.Create('"outputPath" is required for write');
  if P.Rows = '' then raise Exception.Create('"rows" is required for write (JSON array of arrays)');

  D  := GetDelim(P.Delimiter);
  JV := TJSONObject.ParseJSONValue(P.Rows);
  if not (JV is TJSONArray) then
    raise Exception.Create('"rows" must be a JSON array of arrays');
  try
    JArr := TJSONArray(JV);
    if JArr.Count = 0 then
      raise Exception.Create('"rows" is empty');

    // Validate all rows are arrays
    for i := 0 to JArr.Count - 1 do
      if not (JArr.Items[i] is TJSONArray) then
        raise Exception.CreateFmt('Row %d is not an array', [i]);

    StartRow := 0;

    // Extract headers from first row if hasHeader=true
    if P.HasHeader and (JArr.Count > 0) then
    begin
      JRow := TJSONArray(JArr.Items[0]);
      SetLength(Headers, JRow.Count);
      for j := 0 to JRow.Count - 1 do
        Headers[j] := JRow.Items[j].Value;
      StartRow := 1;
    end;

    // Extract data rows
    SetLength(Rows, JArr.Count - StartRow);
    for i := StartRow to JArr.Count - 1 do
    begin
      JRow := TJSONArray(JArr.Items[i]);
      SetLength(Row, JRow.Count);
      for j := 0 to JRow.Count - 1 do
        Row[j] := JRow.Items[j].Value;
      Rows[i - StartRow] := Row;
    end;

    WriteFile(P.OutputPath, D, Headers, Rows);
  finally
    JV.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('output',     P.OutputPath);
  Result.AddPair('rows_written', TJSONNumber.Create(Length(Rows)));
  Result.AddPair('file_size',  TJSONNumber.Create(TFile.GetSize(P.OutputPath)));
end;

function TCSVTool.OpFilter(const P: TCSVParams): TJSONObject;
var
  D:       Char;
  H:       TArray<string>;
  R:       TArray<TArray<string>>;
  ColIdx:  Integer;
  Op:      string;
  Val:     string;
  Matched: TList<TArray<string>>;
  Row:     TArray<string>;
  Field:   string;
  FNum, VNum: Double;
  Keep:    Boolean;
  Lim:     Integer;
begin
  D   := GetDelim(P.Delimiter);
  Op  := LowerCase(Trim(P.FilterOp));
  Val := P.Value;
  Lim := P.Limit;
  if Lim <= 0 then Lim := 100;
  if Op = '' then Op := 'eq';

  ReadFile(P.FilePath, D, P.HasHeader, H, R);
  ColIdx := ColIndex(H, P.Column);

  Matched := TList<TArray<string>>.Create;
  try
    for Row in R do
    begin
      if ColIdx >= Length(Row) then Continue;
      Field := Row[ColIdx];

      Keep := False;
      if      Op = 'eq'       then Keep := SameText(Field, Val)
      else if Op = 'ne'       then Keep := not SameText(Field, Val)
      else if Op = 'contains' then Keep := Pos(LowerCase(Val), LowerCase(Field)) > 0
      else if (Op = 'lt') or (Op = 'gt') or (Op = 'le') or (Op = 'ge') then
      begin
        if TryStrToFloat(Field, FNum) and TryStrToFloat(Val, VNum) then
        begin
          if      Op = 'lt' then Keep := FNum < VNum
          else if Op = 'gt' then Keep := FNum > VNum
          else if Op = 'le' then Keep := FNum <= VNum
          else                    Keep := FNum >= VNum;
        end;
      end
      else
        raise Exception.CreateFmt('Unknown filterOp: "%s". Valid: eq,ne,lt,gt,le,ge,contains', [Op]);

      if Keep then Matched.Add(Row);
    end;

    // Optionally save to file
    if P.OutputPath <> '' then
    begin
      WriteFile(P.OutputPath, D, H, Matched.ToArray);
      Result := TJSONObject.Create;
      Result.AddPair('output',         P.OutputPath);
      Result.AddPair('total_matched',  TJSONNumber.Create(Matched.Count));
      Result.AddPair('file_size',      TJSONNumber.Create(TFile.GetSize(P.OutputPath)));
    end
    else
    begin
      var MatchedArr := Matched.ToArray;
      Result := MakeResult(H, MatchedArr, Length(MatchedArr), Min(Lim, Length(MatchedArr)));
      Result.AddPair('filter_op',    Op);
      Result.AddPair('filter_value', Val);
    end;
  finally
    Matched.Free;
  end;
end;

function TCSVTool.OpStats(const P: TCSVParams): TJSONObject;
var
  D:         Char;
  H:         TArray<string>;
  R:         TArray<TArray<string>>;
  ColIdx:    Integer;
  i:         Integer;
  Field:     string;
  FNum:      Double;
  N:         Int64;
  Sum, Min_, Max_: Double;
  First:     Boolean;
  Stats:     TJSONObject;
  AllStats:  TJSONArray;
  ColName:   string;

  procedure ComputeColStats(AColIdx: Integer; const AName: string);
  begin
    N := 0; Sum := 0; First := True; Min_ := 0; Max_ := 0;
    for var Row in R do
    begin
      if AColIdx >= Length(Row) then Continue;
      Field := Row[AColIdx];
      if Field = '' then Continue;
      if TryStrToFloat(Field, FNum) then
      begin
        Inc(N);
        Sum := Sum + FNum;
        if First then begin Min_ := FNum; Max_ := FNum; First := False; end
        else begin
          if FNum < Min_ then Min_ := FNum;
          if FNum > Max_ then Max_ := FNum;
        end;
      end;
    end;

    Stats := TJSONObject.Create;
    Stats.AddPair('column',  AName);
    Stats.AddPair('count',   TJSONNumber.Create(N));
    Stats.AddPair('total_rows', TJSONNumber.Create(Length(R)));
    if N > 0 then
    begin
      Stats.AddPair('min',  TJSONNumber.Create(Min_));
      Stats.AddPair('max',  TJSONNumber.Create(Max_));
      Stats.AddPair('sum',  TJSONNumber.Create(Sum));
      Stats.AddPair('mean', TJSONNumber.Create(Sum / N));
    end;
  end;

begin
  D := GetDelim(P.Delimiter);
  ReadFile(P.FilePath, D, P.HasHeader, H, R);

  if P.Column <> '' then
  begin
    // Single column
    ColIdx  := ColIndex(H, P.Column);
    ColName := IfThen(ColIdx < Length(H), H[ColIdx], 'col_' + IntToStr(ColIdx));
    ComputeColStats(ColIdx, ColName);
    Stats.AddPair('file', P.FilePath);
    Result := Stats;
  end
  else
  begin
    // All columns
    var ColCount := 0;
    for var Row in R do
      if Length(Row) > ColCount then ColCount := Length(Row);
    if (ColCount = 0) and (Length(H) > 0) then ColCount := Length(H);

    AllStats := TJSONArray.Create;
    for i := 0 to ColCount - 1 do
    begin
      ColName := IfThen(i < Length(H), H[i], 'col_' + IntToStr(i));
      ComputeColStats(i, ColName);
      AllStats.AddElement(Stats);
    end;

    Result := TJSONObject.Create;
    Result.AddPair('file',       P.FilePath);
    Result.AddPair('row_count',  TJSONNumber.Create(Length(R)));
    Result.AddPair('columns',    AllStats);
  end;
end;

function TCSVTool.OpHead(const P: TCSVParams): TJSONObject;
var
  D:   Char;
  H:   TArray<string>;
  R:   TArray<TArray<string>>;
  Lim: Integer;
begin
  D   := GetDelim(P.Delimiter);
  Lim := P.Limit;
  if Lim <= 0 then Lim := 10;
  ReadFile(P.FilePath, D, P.HasHeader, H, R);
  Result := MakeResult(H, R, Length(R), Min(Lim, Length(R)));
  Result.AddPair('file', P.FilePath);
end;

function TCSVTool.OpTail(const P: TCSVParams): TJSONObject;
var
  D:     Char;
  H:     TArray<string>;
  R:     TArray<TArray<string>>;
  Lim:   Integer;
  Start: Integer;
  Tail:  TArray<TArray<string>>;
  i:     Integer;
begin
  D   := GetDelim(P.Delimiter);
  Lim := P.Limit;
  if Lim <= 0 then Lim := 10;
  ReadFile(P.FilePath, D, P.HasHeader, H, R);
  Start := Max(0, Length(R) - Lim);
  SetLength(Tail, Length(R) - Start);
  for i := Start to High(R) do
    Tail[i - Start] := R[i];
  Result := MakeResult(H, Tail, Length(R), Length(Tail));
  Result.AddPair('file', P.FilePath);
end;

function TCSVTool.OpSort(const P: TCSVParams): TJSONObject;
var
  D:      Char;
  H:      TArray<string>;
  R:      TArray<TArray<string>>;
  ColIdx: Integer;
  Lim:    Integer;
  Desc:   Boolean;
  FNum1, FNum2: Double;
  IsNum:  Boolean;
begin
  D    := GetDelim(P.Delimiter);
  Desc := P.Descending;
  Lim  := P.Limit;
  if Lim <= 0 then Lim := 100;

  ReadFile(P.FilePath, D, P.HasHeader, H, R);
  ColIdx := ColIndex(H, P.Column);

  // Detect numeric column (check first non-empty value)
  IsNum := False;
  for var Row in R do
    if (ColIdx < Length(Row)) and (Row[ColIdx] <> '') then
    begin
      IsNum := TryStrToFloat(Row[ColIdx], FNum1);
      Break;
    end;

  TArray.Sort<TArray<string>>(R,
    TComparer<TArray<string>>.Construct(
      function(const A, B: TArray<string>): Integer
      var
        FA, FB: string;
      begin
        FA := IfThen(ColIdx < Length(A), A[ColIdx], '');
        FB := IfThen(ColIdx < Length(B), B[ColIdx], '');
        if IsNum and TryStrToFloat(FA, FNum1) and TryStrToFloat(FB, FNum2) then
          Result := CompareValue(FNum1, FNum2)
        else
          Result := CompareText(FA, FB);
        if Desc then Result := -Result;
      end));

  if P.OutputPath <> '' then
  begin
    WriteFile(P.OutputPath, D, H, R);
    Result := TJSONObject.Create;
    Result.AddPair('output',     P.OutputPath);
    Result.AddPair('row_count',  TJSONNumber.Create(Length(R)));
    Result.AddPair('file_size',  TJSONNumber.Create(TFile.GetSize(P.OutputPath)));
  end
  else
    Result := MakeResult(H, R, Length(R), Min(Lim, Length(R)));
end;

// ── Main dispatch ────────────────────────────────────────────────────────────

function TCSVTool.ExecuteWithParams(const AParams: TCSVParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Data: TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));

    if      Op = 'read'   then Data := OpRead(AParams)
    else if Op = 'write'  then Data := OpWrite(AParams)
    else if Op = 'filter' then Data := OpFilter(AParams)
    else if Op = 'stats'  then Data := OpStats(AParams)
    else if Op = 'head'   then Data := OpHead(AParams)
    else if Op = 'tail'   then Data := OpTail(AParams)
    else if Op = 'sort'   then Data := OpSort(AParams)
    else raise Exception.CreateFmt(
      'Unknown operation: "%s". Valid: read, write, filter, stats, head, tail, sort', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(Data.ToJSON).Build;
    Data.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-csv]: ' + E.Message)
        .Build;
  end;
end;

constructor TCSVTool.Create;
begin
  inherited;
  FName        := 'mcp-csv';
  FDescription :=
    'Parse and manipulate CSV files. Pure Delphi, no external dependencies. ' +
    'read: parse CSV into JSON (headers + rows). ' +
    'write: write JSON rows to CSV file. ' +
    'filter: filter rows by column condition (eq/ne/lt/gt/le/ge/contains). ' +
    'stats: numeric statistics per column (count/min/max/sum/mean). ' +
    'head: return first N rows. ' +
    'tail: return last N rows. ' +
    'sort: sort rows by column (numeric or string, ascending/descending).';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-csv',
    function: IAiMCPTool
    begin
      Result := TCSVTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-csv] registered.');
end;

end.
