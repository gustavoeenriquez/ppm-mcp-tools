// Nombre: Gustavo Enríquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit MCPTool.Postgres;

{
  MCPTool.Postgres
  MCP tool: mcp-postgres

  PostgreSQL via FireDAC (FireDAC.Phys.PG).
  Credentials can be passed as params or set via environment variables:
    PG_HOST, PG_PORT, PG_DATABASE, PG_USER, PG_PASSWORD

  Operations:
    query     - execute a SELECT and return rows as JSON
    execute   - execute INSERT/UPDATE/DELETE/DDL, returns affected rows
    databases - list all databases on the server
    schemas   - list schemas in the current database
    tables    - list tables in the current database/schema
    schema    - describe columns of a table
    indexes   - list indexes of a table
    explain   - show query execution plan (analyze=true for EXPLAIN ANALYZE)
    info      - server version, database, connected user
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  Data.DB,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.Intf,
  FireDAC.Comp.Client,
  FireDAC.Phys.PG,
  FireDAC.ConsoleUI.Wait,
  FireDAC.DApt;

type

  TPostgresParams = class
  private
    FOperation: string;
    FHost:      string;
    FPort:      Integer;
    FDatabase:  string;
    FUser:      string;
    FPassword:  string;
    FSchema:    string;
    FSql:       string;
    FTable:     string;
    FLimit:     Integer;
    FAnalyze:   Boolean;
  public
    [AiMCPSchemaDescription('Operation: query, execute, tables, schema, info')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('PostgreSQL host (default: localhost or PG_HOST env var)')]
    property Host: string read FHost write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('PostgreSQL port (default: 5432 or PG_PORT env var)')]
    property Port: Integer read FPort write FPort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Database name (or PG_DATABASE env var)')]
    property Database: string read FDatabase write FDatabase;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Username (or PG_USER env var)')]
    property User: string read FUser write FUser;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Password (or PG_PASSWORD env var)')]
    property Password: string read FPassword write FPassword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Schema name for tables/schema operations (default: public)')]
    property Schema: string read FSchema write FSchema;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SQL statement for query or execute')]
    property Sql: string read FSql write FSql;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Table name for schema operation')]
    property Table: string read FTable write FTable;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max rows to return for query (default: 100, max: 1000)')]
    property Limit: Integer read FLimit write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('If true, runs EXPLAIN ANALYZE instead of plain EXPLAIN (explain operation)')]
    property Analyze: Boolean read FAnalyze write FAnalyze;
  end;

  TPostgresTool = class(TAiMCPToolBase<TPostgresParams>)
  private
    function OpenConnection(const AParams: TPostgresParams): TFDConnection;
    function QueryToJSON(Q: TFDQuery; Limit: Integer): TJSONObject;
    function Env(const Key, Default: string): string;
    function EnvInt(const Key: string; Default: Integer): Integer;
  protected
    function ExecuteWithParams(const AParams: TPostgresParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

function TPostgresTool.Env(const Key, Default: string): string;
begin
  Result := GetEnvironmentVariable(Key);
  if Result = '' then Result := Default;
end;

function TPostgresTool.EnvInt(const Key: string; Default: Integer): Integer;
var S: string;
begin
  S := GetEnvironmentVariable(Key);
  if S = '' then Result := Default
  else            Result := StrToIntDef(S, Default);
end;

function TPostgresTool.OpenConnection(const AParams: TPostgresParams): TFDConnection;
var
  Host, DB, User, Pass: string;
  Port: Integer;
begin
  Host := AParams.Host;     if Host = '' then Host := Env('PG_HOST', 'localhost');
  Port := AParams.Port;     if Port = 0  then Port := EnvInt('PG_PORT', 5432);
  DB   := AParams.Database; if DB   = '' then DB   := Env('PG_DATABASE', '');
  User := AParams.User;     if User = '' then User := Env('PG_USER', '');
  Pass := AParams.Password; if Pass = '' then Pass := Env('PG_PASSWORD', '');

  if DB   = '' then raise Exception.Create('database is required (param or PG_DATABASE env var)');
  if User = '' then raise Exception.Create('user is required (param or PG_USER env var)');

  Result := TFDConnection.Create(nil);
  try
    Result.DriverName                        := 'PG';
    Result.Params.Values['Server']           := Host;
    Result.Params.Values['Port']             := IntToStr(Port);
    Result.Params.Values['Database']         := DB;
    Result.Params.Values['User_Name']        := User;
    Result.Params.Values['Password']         := Pass;
    Result.Params.Values['ApplicationName']  := 'MCPService';
    Result.LoginPrompt                       := False;
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function TPostgresTool.QueryToJSON(Q: TFDQuery; Limit: Integer): TJSONObject;
var
  Fields:  TJSONArray;
  Rows:    TJSONArray;
  RowCount: Integer;
begin
  Fields := TJSONArray.Create;
  for var i := 0 to Q.FieldCount - 1 do
    Fields.Add(Q.Fields[i].FieldName);

  Rows     := TJSONArray.Create;
  RowCount := 0;
  Q.First;
  while not Q.EOF and (RowCount < Limit) do
  begin
    var Row := TJSONArray.Create;
    for var i := 0 to Q.FieldCount - 1 do
    begin
      if Q.Fields[i].IsNull then
        Row.AddElement(TJSONNull.Create)
      else
        case Q.Fields[i].DataType of
          ftInteger, ftSmallint, ftWord,
          ftLargeint, ftAutoInc:
            Row.Add(Q.Fields[i].AsInteger);
          ftFloat, ftCurrency, ftBCD,
          ftSingle, ftExtended, ftFMTBcd:
            Row.Add(Q.Fields[i].AsFloat);
          ftBoolean:
            Row.Add(Q.Fields[i].AsBoolean);
        else
          Row.Add(Q.Fields[i].AsString);
        end;
    end;
    Rows.AddElement(Row);
    Inc(RowCount);
    Q.Next;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('columns',   Fields);
  Result.AddPair('rows',      Rows);
  Result.AddPair('count',     TJSONNumber.Create(RowCount));
  Result.AddPair('truncated', TJSONBool.Create(not Q.EOF));
end;

function TPostgresTool.ExecuteWithParams(const AParams: TPostgresParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Conn: TFDConnection;
  R:    TJSONObject;
begin
  try
    Op   := LowerCase(Trim(AParams.Operation));
    Conn := OpenConnection(AParams);
    try
      var Schema := AParams.Schema;
      if Schema = '' then Schema := 'public';
      var Lim := AParams.Limit;
      if Lim <= 0   then Lim := 100;
      if Lim > 1000 then Lim := 1000;

      // ── query ──────────────────────────────────────────────────────────
      if Op = 'query' then
      begin
        if AParams.Sql = '' then raise Exception.Create('"sql" is required');
        var Q := TFDQuery.Create(nil);
        try
          Q.Connection := Conn;
          Q.SQL.Text   := AParams.Sql;
          Q.Open;
          R := QueryToJSON(Q, Lim);
          R.AddPair('sql', AParams.Sql);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Q.Free;
        end;
      end

      // ── execute ────────────────────────────────────────────────────────
      else if Op = 'execute' then
      begin
        if AParams.Sql = '' then raise Exception.Create('"sql" is required');
        var Q := TFDQuery.Create(nil);
        try
          Q.Connection := Conn;
          Q.SQL.Text   := AParams.Sql;
          Q.ExecSQL;
          R := TJSONObject.Create;
          R.AddPair('ok',            TJSONBool.Create(True));
          R.AddPair('rows_affected', TJSONNumber.Create(Q.RowsAffected));
          R.AddPair('sql',           AParams.Sql);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Q.Free;
        end;
      end

      // ── tables ─────────────────────────────────────────────────────────
      else if Op = 'tables' then
      begin
        var Q := TFDQuery.Create(nil);
        try
          Q.Connection := Conn;
          Q.SQL.Text   :=
            'SELECT table_name, table_type ' +
            'FROM information_schema.tables ' +
            'WHERE table_schema = :schema ' +
            'ORDER BY table_name';
          Q.ParamByName('schema').AsString := Schema;
          Q.Open;
          var Tables := TJSONArray.Create;
          while not Q.EOF do
          begin
            var Item := TJSONObject.Create;
            Item.AddPair('name', Q.FieldByName('table_name').AsString);
            Item.AddPair('type', Q.FieldByName('table_type').AsString);
            Tables.AddElement(Item);
            Q.Next;
          end;
          R := TJSONObject.Create;
          R.AddPair('schema', Schema);
          R.AddPair('count',  TJSONNumber.Create(Tables.Count));
          R.AddPair('tables', Tables);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Q.Free;
        end;
      end

      // ── schema ─────────────────────────────────────────────────────────
      else if Op = 'schema' then
      begin
        if AParams.Table = '' then raise Exception.Create('"table" is required');
        var Q := TFDQuery.Create(nil);
        try
          Q.Connection := Conn;
          Q.SQL.Text   :=
            'SELECT column_name, data_type, is_nullable, ' +
            '       column_default, character_maximum_length, ' +
            '       numeric_precision, numeric_scale ' +
            'FROM information_schema.columns ' +
            'WHERE table_schema = :schema AND table_name = :tbl ' +
            'ORDER BY ordinal_position';
          Q.ParamByName('schema').AsString := Schema;
          Q.ParamByName('tbl').AsString    := AParams.Table;
          Q.Open;
          var Cols := TJSONArray.Create;
          while not Q.EOF do
          begin
            var Col := TJSONObject.Create;
            Col.AddPair('name',     Q.FieldByName('column_name').AsString);
            Col.AddPair('type',     Q.FieldByName('data_type').AsString);
            Col.AddPair('nullable', Q.FieldByName('is_nullable').AsString = 'YES');
            var Def := Q.FieldByName('column_default').AsString;
            if Def <> '' then Col.AddPair('default', Def);
            Cols.AddElement(Col);
            Q.Next;
          end;
          R := TJSONObject.Create;
          R.AddPair('schema',  Schema);
          R.AddPair('table',   AParams.Table);
          R.AddPair('columns', Cols);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Q.Free;
        end;
      end

      // ── info ───────────────────────────────────────────────────────────
      else if Op = 'info' then
      begin
        var Q := TFDQuery.Create(nil);
        try
          Q.Connection := Conn;
          Q.SQL.Text   :=
            'SELECT version() AS version, ' +
            '       current_database() AS db, ' +
            '       current_user AS usr, ' +
            '       pg_size_pretty(pg_database_size(current_database())) AS db_size, ' +
            '       (SELECT COUNT(*) FROM information_schema.tables ' +
            '        WHERE table_schema = ''public'') AS table_count';
          Q.Open;
          R := TJSONObject.Create;
          R.AddPair('version',     Q.FieldByName('version').AsString);
          R.AddPair('database',    Q.FieldByName('db').AsString);
          R.AddPair('user',        Q.FieldByName('usr').AsString);
          R.AddPair('db_size',     Q.FieldByName('db_size').AsString);
          R.AddPair('table_count', TJSONNumber.Create(Q.FieldByName('table_count').AsInteger));
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Q.Free;
        end;
      end

      // ── databases ──────────────────────────────────────────────────────
      else if Op = 'databases' then
      begin
        var Q := TFDQuery.Create(nil);
        try
          Q.Connection := Conn;
          Q.SQL.Text   :=
            'SELECT datname AS name, ' +
            '       pg_size_pretty(pg_database_size(datname)) AS size, ' +
            '       datcollate AS collation, ' +
            '       datistemplate AS is_template ' +
            'FROM pg_database ' +
            'ORDER BY datname';
          Q.Open;
          var Databases := TJSONArray.Create;
          while not Q.EOF do
          begin
            var Item := TJSONObject.Create;
            Item.AddPair('name',        Q.FieldByName('name').AsString);
            Item.AddPair('size',        Q.FieldByName('size').AsString);
            Item.AddPair('collation',   Q.FieldByName('collation').AsString);
            Item.AddPair('is_template', TJSONBool.Create(Q.FieldByName('is_template').AsBoolean));
            Databases.AddElement(Item);
            Q.Next;
          end;
          R := TJSONObject.Create;
          R.AddPair('count',     TJSONNumber.Create(Databases.Count));
          R.AddPair('databases', Databases);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Q.Free;
        end;
      end

      // ── schemas ────────────────────────────────────────────────────────
      else if Op = 'schemas' then
      begin
        var Q := TFDQuery.Create(nil);
        try
          Q.Connection := Conn;
          Q.SQL.Text   :=
            'SELECT schema_name, schema_owner ' +
            'FROM information_schema.schemata ' +
            'ORDER BY schema_name';
          Q.Open;
          var Schemas := TJSONArray.Create;
          while not Q.EOF do
          begin
            var Item := TJSONObject.Create;
            Item.AddPair('name',  Q.FieldByName('schema_name').AsString);
            Item.AddPair('owner', Q.FieldByName('schema_owner').AsString);
            Schemas.AddElement(Item);
            Q.Next;
          end;
          R := TJSONObject.Create;
          R.AddPair('database', AParams.Database);
          R.AddPair('count',    TJSONNumber.Create(Schemas.Count));
          R.AddPair('schemas',  Schemas);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Q.Free;
        end;
      end

      // ── indexes ────────────────────────────────────────────────────────
      else if Op = 'indexes' then
      begin
        if AParams.Table = '' then raise Exception.Create('"table" is required');
        var Q := TFDQuery.Create(nil);
        try
          Q.Connection := Conn;
          Q.SQL.Text   :=
            'SELECT i.relname AS index_name, ' +
            '       ix.indisprimary AS is_primary, ' +
            '       ix.indisunique  AS is_unique, ' +
            '       string_agg(a.attname, '', '' ORDER BY k.n) AS columns, ' +
            '       am.amname AS index_type ' +
            'FROM pg_class t ' +
            'JOIN pg_index ix    ON t.oid = ix.indrelid ' +
            'JOIN pg_class i     ON i.oid = ix.indexrelid ' +
            'JOIN pg_am am       ON am.oid = i.relam ' +
            'JOIN pg_namespace n ON n.oid = t.relnamespace ' +
            'JOIN LATERAL unnest(ix.indkey) WITH ORDINALITY AS k(attnum, n) ON true ' +
            'JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum ' +
            'WHERE t.relname = :tbl AND n.nspname = :schema ' +
            'GROUP BY i.relname, ix.indisprimary, ix.indisunique, am.amname ' +
            'ORDER BY ix.indisprimary DESC, i.relname';
          Q.ParamByName('tbl').AsString    := AParams.Table;
          Q.ParamByName('schema').AsString := Schema;
          Q.Open;
          var Indexes := TJSONArray.Create;
          while not Q.EOF do
          begin
            var Item := TJSONObject.Create;
            Item.AddPair('name',       Q.FieldByName('index_name').AsString);
            Item.AddPair('type',       Q.FieldByName('index_type').AsString);
            Item.AddPair('columns',    Q.FieldByName('columns').AsString);
            Item.AddPair('primary',    TJSONBool.Create(Q.FieldByName('is_primary').AsBoolean));
            Item.AddPair('unique',     TJSONBool.Create(Q.FieldByName('is_unique').AsBoolean));
            Indexes.AddElement(Item);
            Q.Next;
          end;
          R := TJSONObject.Create;
          R.AddPair('schema',  Schema);
          R.AddPair('table',   AParams.Table);
          R.AddPair('count',   TJSONNumber.Create(Indexes.Count));
          R.AddPair('indexes', Indexes);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Q.Free;
        end;
      end

      // ── explain ────────────────────────────────────────────────────────
      else if Op = 'explain' then
      begin
        if AParams.Sql = '' then raise Exception.Create('"sql" is required');
        var Q := TFDQuery.Create(nil);
        try
          Q.Connection := Conn;
          var Prefix := 'EXPLAIN ';
          if AParams.Analyze then
            Prefix := 'EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) '
          else
            Prefix := 'EXPLAIN (FORMAT TEXT) ';
          Q.SQL.Text := Prefix + AParams.Sql;
          Q.Open;
          var Plan := TStringBuilder.Create;
          try
            while not Q.EOF do
            begin
              Plan.AppendLine(Q.Fields[0].AsString);
              Q.Next;
            end;
            R := TJSONObject.Create;
            R.AddPair('sql',     AParams.Sql);
            R.AddPair('analyze', TJSONBool.Create(AParams.Analyze));
            R.AddPair('plan',    Plan.ToString.TrimRight);
            Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
            R.Free;
          finally
            Plan.Free;
          end;
        finally
          Q.Free;
        end;
      end

      else
        raise Exception.CreateFmt(
          'Unknown operation: "%s". Valid: query, execute, tables, schema, indexes, explain, databases, schemas, info', [Op]);

    finally
      Conn.Free;
    end;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-postgres]: ' + E.Message)
        .Build;
  end;
end;

constructor TPostgresTool.Create;
begin
  inherited;
  FName        := 'mcp-postgres';
  FDescription :=
    'PostgreSQL via FireDAC. Credentials via params (host, port, database, user, password) ' +
    'or env vars PG_HOST/PG_PORT/PG_DATABASE/PG_USER/PG_PASSWORD. ' +
    'query: run SELECT and return rows (sql, limit). ' +
    'execute: run INSERT/UPDATE/DELETE/DDL (sql). ' +
    'databases: list all databases on the server (connects to ''postgres'' db by default). ' +
    'schemas: list schemas in the current database. ' +
    'tables: list tables in schema (schema=public). ' +
    'schema: describe columns of a table (table, schema). ' +
    'indexes: list indexes of a table (table, schema). ' +
    'explain: show query execution plan (sql, analyze=false). ' +
    'info: server version, database size, table count.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-postgres',
    function: IAiMCPTool
    begin
      Result := TPostgresTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-postgres');
end;

end.
