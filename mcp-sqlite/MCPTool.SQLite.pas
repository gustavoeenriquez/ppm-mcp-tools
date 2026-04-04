// Nombre: Gustavo Enríquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit MCPTool.SQLite;

{
  MCPTool.SQLite
  MCP tool: mcp-sqlite

  Operations:
    query   - execute a SELECT and return rows as JSON
    execute - execute INSERT / UPDATE / DELETE / CREATE / DROP (no result set)
    tables  - list all tables and views in the database
    schema  - column info and DDL for a specific table
    info    - database statistics (page size, page count, table count)

  The database file is created automatically if it does not exist.
  One SQL statement per call; FireDAC/SQLite does not support multi-statement batches.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Phys.SQLite,
  FireDAC.ConsoleUI.Wait,
  FireDAC.DApt;

type

  // ── Parameters ─────────────────────────────────────────────────────────────

  TSQLiteParams = class
  private
    FOperation: string;
    FDatabase:  string;
    FSql:       string;
    FTable:     string;
  public
    [AiMCPSchemaDescription('Operation: query, execute, tables, schema, info')]
    property Operation: string read FOperation write FOperation;

    [AiMCPSchemaDescription('Path to the SQLite database file (.db or .sqlite)')]
    property Database: string read FDatabase write FDatabase;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SQL statement (required for query and execute)')]
    property Sql: string read FSql write FSql;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Table name (required for schema)')]
    property Table: string read FTable write FTable;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TSQLiteTool = class(TAiMCPToolBase<TSQLiteParams>)
  private
    function OpenConnection(const DBPath: string): TFDConnection;
    function QueryToJSON(Conn: TFDConnection; const SQL: string): TJSONObject;
    function ScalarInt(Conn: TFDConnection; const SQL: string): Integer;
  protected
    function ExecuteWithParams(const AParams: TSQLiteParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Helpers ─────────────────────────────────────────────────────────────────

function TSQLiteTool.OpenConnection(const DBPath: string): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.Params.DriverID := 'SQLite';
    Result.Params.Database := DBPath;
    Result.LoginPrompt     := False;
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function TSQLiteTool.QueryToJSON(Conn: TFDConnection; const SQL: string): TJSONObject;
var
  Q:    TFDQuery;
  Rows: TJSONArray;
  Cols: TJSONArray;
  Row:  TJSONObject;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text   := SQL;
    Q.Open;

    Cols := TJSONArray.Create;
    for var i := 0 to Q.FieldCount - 1 do
      Cols.Add(Q.Fields[i].FieldName);

    Rows := TJSONArray.Create;
    while not Q.Eof do
    begin
      Row := TJSONObject.Create;
      for var i := 0 to Q.FieldCount - 1 do
      begin
        var F := Q.Fields[i];
        if F.IsNull then
          Row.AddPair(F.FieldName, TJSONNull.Create)
        else
          case F.DataType of
            ftInteger, ftSmallInt, ftWord, ftAutoInc:
              Row.AddPair(F.FieldName, TJSONNumber.Create(F.AsInteger));
            ftLargeInt:
              Row.AddPair(F.FieldName, TJSONNumber.Create(F.AsFloat));
            ftFloat, ftSingle, ftExtended, ftCurrency, ftBCD, ftFMTBcd:
              Row.AddPair(F.FieldName, TJSONNumber.Create(F.AsFloat));
            ftBoolean:
              Row.AddPair(F.FieldName, TJSONBool.Create(F.AsBoolean));
          else
            Row.AddPair(F.FieldName, F.AsString);
          end;
      end;
      Rows.AddElement(Row);
      Q.Next;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('fields',  Cols);
    Result.AddPair('columns', TJSONNumber.Create(Q.FieldCount));
    Result.AddPair('rows',    TJSONNumber.Create(Rows.Count));
    Result.AddPair('data',    Rows);
  finally
    Q.Free;
  end;
end;

function TSQLiteTool.ScalarInt(Conn: TFDConnection; const SQL: string): Integer;
var
  Q: TFDQuery;
begin
  Result := 0;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text   := SQL;
    Q.Open;
    if not Q.Eof then
      Result := Q.Fields[0].AsInteger;
  finally
    Q.Free;
  end;
end;

// ── Main execution ──────────────────────────────────────────────────────────

function TSQLiteTool.ExecuteWithParams(const AParams: TSQLiteParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Conn: TFDConnection;
  R:    TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));

    if AParams.Database = '' then
      raise Exception.Create('"database" path is required');

    Conn := OpenConnection(AParams.Database);
    try

      // ── query ────────────────────────────────────────────────────────────
      if Op = 'query' then
      begin
        if AParams.Sql = '' then
          raise Exception.Create('"sql" is required for query');
        R := QueryToJSON(Conn, AParams.Sql);
        R.AddPair('database', AParams.Database);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      // ── execute ──────────────────────────────────────────────────────────
      else if Op = 'execute' then
      begin
        if AParams.Sql = '' then
          raise Exception.Create('"sql" is required for execute');
        var Q := TFDQuery.Create(nil);
        try
          Q.Connection := Conn;
          Q.SQL.Text   := AParams.Sql;
          Q.ExecSQL;
          R := TJSONObject.Create;
          R.AddPair('ok',           TJSONBool.Create(True));
          R.AddPair('rows_affected', TJSONNumber.Create(Q.RowsAffected));
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Q.Free;
        end;
      end

      // ── tables ───────────────────────────────────────────────────────────
      else if Op = 'tables' then
      begin
        R := QueryToJSON(Conn,
          'SELECT name, type FROM sqlite_master ' +
          'WHERE type IN (''table'',''view'') ORDER BY type, name');
        R.AddPair('database', AParams.Database);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      // ── schema ───────────────────────────────────────────────────────────
      else if Op = 'schema' then
      begin
        if AParams.Table = '' then
          raise Exception.Create('"table" is required for schema');

        R := QueryToJSON(Conn,
          Format('PRAGMA table_info(%s)', [AParams.Table]));
        R.AddPair('table', AParams.Table);

        // DDL
        var Q := TFDQuery.Create(nil);
        try
          Q.Connection := Conn;
          Q.SQL.Text   := Format(
            'SELECT sql FROM sqlite_master WHERE name = ''%s''',
            [AParams.Table]);
          Q.Open;
          if not Q.Eof then
            R.AddPair('ddl', Q.Fields[0].AsString)
          else
            R.AddPair('ddl', '');
        finally
          Q.Free;
        end;

        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      // ── info ─────────────────────────────────────────────────────────────
      else if Op = 'info' then
      begin
        var PageSize  := ScalarInt(Conn, 'PRAGMA page_size');
        var PageCount := ScalarInt(Conn, 'PRAGMA page_count');
        var UserVer   := ScalarInt(Conn, 'PRAGMA user_version');
        var TblCount  := ScalarInt(Conn,
          'SELECT COUNT(*) FROM sqlite_master WHERE type=''table''');
        var ViewCount := ScalarInt(Conn,
          'SELECT COUNT(*) FROM sqlite_master WHERE type=''view''');

        R := TJSONObject.Create;
        R.AddPair('database',    AParams.Database);
        R.AddPair('page_size',   TJSONNumber.Create(PageSize));
        R.AddPair('page_count',  TJSONNumber.Create(PageCount));
        R.AddPair('size_bytes',  TJSONNumber.Create(Int64(PageSize) * PageCount));
        R.AddPair('user_version',TJSONNumber.Create(UserVer));
        R.AddPair('tables',      TJSONNumber.Create(TblCount));
        R.AddPair('views',       TJSONNumber.Create(ViewCount));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else
        raise Exception.CreateFmt(
          'Unknown operation: "%s". Valid: query, execute, tables, schema, info',
          [Op]);

    finally
      Conn.Free;
    end;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-sqlite]: ' + E.Message)
        .Build;
  end;
end;

constructor TSQLiteTool.Create;
begin
  inherited;
  FName        := 'mcp-sqlite';
  FDescription :=
    'SQLite database operations. The database file is created if it does not exist. ' +
    'query: execute a SELECT and return rows as JSON. ' +
    'execute: run INSERT/UPDATE/DELETE/CREATE/DROP (returns rows_affected). ' +
    'tables: list all tables and views. ' +
    'schema: column info (PRAGMA table_info) and DDL for a table. ' +
    'info: database statistics (page size, file size, table/view counts).';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-sqlite',
    function: IAiMCPTool
    begin
      Result := TSQLiteTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-sqlite');
end;

end.
