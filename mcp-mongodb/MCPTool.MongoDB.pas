unit MCPTool.MongoDB;

{
  MCPTool.MongoDB  ·  mcp-mongodb

  MongoDB access via FireDAC.Phys.MongoDB (libmongoc-1.0.dll).
  Direct connection to any MongoDB server — no Atlas, no REST required.

  Operations:
    find        - find documents in a collection
    find_one    - find a single document
    insert_one  - insert a document
    insert_many - insert multiple documents
    update_one  - update a single document
    update_many - update multiple documents
    delete_one  - delete a single document
    delete_many - delete multiple documents
    aggregate   - run an aggregation pipeline
    count       - count documents matching a filter

  Connection: host (default localhost), port (default 27017),
              database, username?, password?.
  All filter/document/update/pipeline values are JSON strings.

  Requires libmongoc-1.0.dll at runtime (shipped in package bin/win64/).
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  // FireDAC MongoDB
  FireDAC.Stan.Util,
  FireDAC.Phys.MongoDBWrapper,
  FireDAC.Phys.MongoDBCli,
  FireDAC.Phys.MongoDB;

type

  TMongoFDParams = class
  private
    FOperation:  string;
    FHost:       string;
    FPort:       Integer;
    FDatabase:   string;
    FUsername:   string;
    FPassword:   string;
    FCollection: string;
    FFilter:     string;
    FDocument:   string;
    FDocuments:  string;
    FUpdate:     string;
    FPipeline:   string;
    FProjection: string;
    FSort:       string;
    FLimit:      Integer;
    FSkip:       Integer;
    FUpsert:     Boolean;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: find, find_one, insert_one, insert_many, update_one, update_many, delete_one, delete_many, aggregate, count')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('MongoDB server host (default: localhost)')]
    property Host:       string  read FHost       write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('MongoDB server port (default: 27017)')]
    property Port:       Integer read FPort       write FPort;

    [AiMCPSchemaDescription('Database name')]
    property Database:   string  read FDatabase   write FDatabase;

    [AiMCPOptional]
    [AiMCPSchemaDescription('MongoDB username (omit for no-auth)')]
    property Username:   string  read FUsername   write FUsername;

    [AiMCPOptional]
    [AiMCPSchemaDescription('MongoDB password')]
    property Password:   string  read FPassword   write FPassword;

    [AiMCPSchemaDescription('Collection name')]
    property Collection: string  read FCollection write FCollection;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Filter as JSON string (e.g. "{\"status\":\"active\"}"). Default: {} (all documents).')]
    property Filter:     string  read FFilter     write FFilter;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Document to insert as JSON string. Required for insert_one.')]
    property Document:   string  read FDocument   write FDocument;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Array of documents as JSON string for insert_many (e.g. "[{\"a\":1},{\"b\":2}]").')]
    property Documents:  string  read FDocuments  write FDocuments;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Update operators as JSON string for update_one/update_many (e.g. "{\"$set\":{\"status\":\"done\"}}").')]
    property Update:     string  read FUpdate     write FUpdate;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Aggregation pipeline as JSON array string for aggregate (e.g. "[{\"$match\":{\"active\":true}}]").')]
    property Pipeline:   string  read FPipeline   write FPipeline;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Fields to return as JSON string for find/find_one (e.g. "{\"name\":1,\"_id\":0}").')]
    property Projection: string  read FProjection write FProjection;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Sort specification as JSON string for find (e.g. "{\"createdAt\":-1}").')]
    property Sort:       string  read FSort       write FSort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum documents to return for find (default: 20).')]
    property Limit:      Integer read FLimit      write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of documents to skip for find (pagination). Default: 0.')]
    property Skip:       Integer read FSkip       write FSkip;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Upsert flag for update_one/update_many (default: false).')]
    property Upsert:     Boolean read FUpsert     write FUpsert;
  end;

  TMongoContext = class
  public
    CLib: TMongoClientLib;
    BLib: TMongoBSONLib;
    Env:  TMongoEnv;
    Conn: TMongoConnection;
    constructor Create(AOwner: TObject; const AURI: string);
    destructor  Destroy; override;
  end;

  TMongoFDTool = class(TAiMCPToolBase<TMongoFDParams>)
  private
    function  BuildURI(const P: TMongoFDParams): string;
    function  DoFind(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams): TJSONObject;
    function  DoFindOne(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams): TJSONObject;
    function  DoInsertOne(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams): TJSONObject;
    function  DoInsertMany(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams): TJSONObject;
    function  DoUpdateOp(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams; AMulti: Boolean): TJSONObject;
    function  DoDeleteOp(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams; AMulti: Boolean): TJSONObject;
    function  DoAggregate(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams): TJSONObject;
    function  DoCount(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TMongoFDParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ TMongoFDParams }

constructor TMongoFDParams.Create;
begin
  inherited;
  FHost   := 'localhost';
  FPort   := 27017;
  FFilter := '{}';
  FLimit  := 20;
  FSkip   := 0;
  FUpsert := False;
end;

{ TMongoContext }

constructor TMongoContext.Create(AOwner: TObject; const AURI: string);
begin
  inherited Create;
  CLib := TMongoClientLib.Create(nil);
  BLib := TMongoBSONLib.Create(CLib);
  Env  := TMongoEnv.Create(CLib, BLib, AOwner);
  Conn := TMongoConnection.Create(Env, AOwner);
  Conn.Open(AURI);
end;

destructor TMongoContext.Destroy;
begin
  FDFreeAndNil(Conn);
  FDFreeAndNil(Env);
  FDFreeAndNil(BLib);
  FDFreeAndNil(CLib);
  inherited;
end;

{ TMongoFDTool }

constructor TMongoFDTool.Create;
begin
  inherited;
  FName        := 'mcp-mongodb';
  FDescription :=
    'MongoDB access via FireDAC native driver (libmongoc-1.0.dll). ' +
    'Direct connection to any MongoDB server — no Atlas, no REST. ' +
    'Operations: ' +
    'find (query documents; params: filter?, projection?, sort?, limit?, skip?), ' +
    'find_one (single document; params: filter?, projection?), ' +
    'insert_one (insert; params: document), ' +
    'insert_many (insert multiple; params: documents array), ' +
    'update_one/update_many (update; params: filter?, update operators, upsert?), ' +
    'delete_one/delete_many (delete; params: filter?), ' +
    'aggregate (pipeline; params: pipeline stages array), ' +
    'count (count matching; params: filter?). ' +
    'Required for all: database, collection. ' +
    'Connection: host (default localhost), port (default 27017), username?, password?. ' +
    'All filter/document/update/pipeline values are JSON strings.';
end;

function TMongoFDTool.BuildURI(const P: TMongoFDParams): string;
var
  Host: string;
  Port: Integer;
begin
  Host := Trim(P.Host);
  if Host = '' then Host := 'localhost';
  Port := P.Port;
  if Port <= 0 then Port := 27017;

  if (Trim(P.Username) <> '') and (Trim(P.Password) <> '') then
    Result := Format('mongodb://%s:%s@%s:%d/%s',
      [P.Username, P.Password, Host, Port, P.Database])
  else if Trim(P.Username) <> '' then
    Result := Format('mongodb://%s@%s:%d/%s',
      [P.Username, Host, Port, P.Database])
  else
    Result := Format('mongodb://%s:%d/%s', [Host, Port, P.Database]);
end;

function TMongoFDTool.DoFind(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams): TJSONObject;
var
  Query:  TMongoQuery;
  Cursor: IMongoCursor;
  Doc:    TMongoDocument;
  Arr:    TJSONArray;
  Item:   TJSONValue;
  Limit:  Integer;
begin
  Limit := P.Limit;
  if Limit <= 0 then Limit := 20;

  Query := TMongoQuery.Create(Ctx.Env);
  Query.Match(P.Filter).&End;
  if Trim(P.Projection) <> '' then
    Query.Project(P.Projection).&End;
  if Trim(P.Sort) <> '' then
    Query.Sort(P.Sort).&End;
  Query.Limit(Limit);
  if P.Skip > 0 then Query.Skip(P.Skip);

  Cursor := Coll.Find(Query);
  Doc    := TMongoDocument.Create(Ctx.Env);
  Arr    := TJSONArray.Create;
  try
    while Cursor.Next(Doc) do
    begin
      Item := TJSONObject.ParseJSONValue(Doc.AsJSON);
      if Item <> nil then
        Arr.AddElement(Item)
      else
        Arr.AddElement(TJSONObject.Create);
      Doc.Clear;
    end;
  finally
    Doc.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('documents', Arr);
  Result.AddPair('count', TJSONNumber.Create(Arr.Count));
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TMongoFDTool.DoFindOne(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams): TJSONObject;
var
  Query:  TMongoQuery;
  Cursor: IMongoCursor;
  Doc:    TMongoDocument;
  Item:   TJSONValue;
begin
  Query := TMongoQuery.Create(Ctx.Env);
  Query.Match(P.Filter).&End;
  if Trim(P.Projection) <> '' then
    Query.Project(P.Projection).&End;
  Query.Limit(1);

  Cursor := Coll.Find(Query);
  Doc    := TMongoDocument.Create(Ctx.Env);
  try
    Result := TJSONObject.Create;
    if Cursor.Next(Doc) then
    begin
      Item := TJSONObject.ParseJSONValue(Doc.AsJSON);
      if Item <> nil then
        Result.AddPair('document', Item)
      else
        Result.AddPair('document', TJSONNull.Create);
    end
    else
      Result.AddPair('document', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Doc.Free;
  end;
end;

function TMongoFDTool.DoInsertOne(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams): TJSONObject;
var
  Doc: TMongoDocument;
begin
  if Trim(P.Document) = '' then
    raise Exception.Create('"document" required for insert_one');

  Doc := TMongoDocument.Create(Ctx.Env);
  try
    Doc.AsJSON := P.Document;
    Coll.Insert(Doc);
  finally
    Doc.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('insertedCount', TJSONNumber.Create(Coll.DocsInserted));
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TMongoFDTool.DoInsertMany(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams): TJSONObject;
var
  DocsVal: TJSONValue;
  DocsArr: TJSONArray;
  Doc:     TMongoDocument;
  i:       Integer;
  Total:   Int64;
begin
  if Trim(P.Documents) = '' then
    raise Exception.Create('"documents" required for insert_many');

  DocsVal := TJSONObject.ParseJSONValue(P.Documents);
  if not (DocsVal is TJSONArray) then
  begin
    DocsVal.Free;
    raise Exception.Create('"documents" must be a JSON array');
  end;

  DocsArr := DocsVal as TJSONArray;
  Total   := 0;
  try
    Coll.BeginBulk;
    try
      for i := 0 to DocsArr.Count - 1 do
      begin
        Doc := TMongoDocument.Create(Ctx.Env);
        try
          Doc.AsJSON := DocsArr.Items[i].ToJSON;
          Coll.Insert(Doc);
        finally
          Doc.Free;
        end;
      end;
      Coll.EndBulk;
      Total := Coll.DocsInserted;
    except
      Coll.CancelBulk;
      raise;
    end;
  finally
    DocsArr.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('insertedCount', TJSONNumber.Create(Total));
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TMongoFDTool.DoUpdateOp(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams; AMulti: Boolean): TJSONObject;
var
  UpdOp: TMongoUpdate;
  Flags: TMongoCollection.TUpdateFlags;
begin
  if Trim(P.Update) = '' then
    raise Exception.Create('"update" required for update operation');

  Flags := [];
  if AMulti   then Include(Flags, TMongoCollection.TUpdateFlag.MultiUpdate);
  if P.Upsert then Include(Flags, TMongoCollection.TUpdateFlag.Upsert);

  UpdOp := TMongoUpdate.Create(Ctx.Env);
  UpdOp.Match(P.Filter).&End;
  UpdOp.Modify(P.Update).&End;
  Coll.Update(UpdOp, Flags);

  Result := TJSONObject.Create;
  Result.AddPair('matchedCount',  TJSONNumber.Create(Coll.DocsMatched));
  Result.AddPair('modifiedCount', TJSONNumber.Create(Coll.DocsModified));
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TMongoFDTool.DoDeleteOp(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams; AMulti: Boolean): TJSONObject;
var
  Sel:   TMongoSelector;
  Flags: TMongoCollection.TRemoveFlags;
begin
  Flags := [];
  if not AMulti then Include(Flags, TMongoCollection.TRemoveFlag.SingleRemove);

  Sel := TMongoSelector.Create(Ctx.Env);
  Sel.Match(P.Filter).&End;
  Coll.Remove(Sel, Flags);

  Result := TJSONObject.Create;
  Result.AddPair('deletedCount', TJSONNumber.Create(Coll.DocsRemoved));
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TMongoFDTool.DoAggregate(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams): TJSONObject;
var
  PipelineVal: TJSONValue;
  PipeArr:     TJSONArray;
  Pipeline:    TMongoPipeline;
  Cursor:      IMongoCursor;
  Doc:         TMongoDocument;
  Arr:         TJSONArray;
  Item:        TJSONValue;
  i:           Integer;
  Stage:       TJSONObject;
  StageName:   string;
  StageValStr: string;
begin
  if Trim(P.Pipeline) = '' then
    raise Exception.Create('"pipeline" required for aggregate');

  PipelineVal := TJSONObject.ParseJSONValue(P.Pipeline);
  if not (PipelineVal is TJSONArray) then
  begin
    PipelineVal.Free;
    raise Exception.Create('"pipeline" must be a JSON array');
  end;

  PipeArr  := PipelineVal as TJSONArray;
  Pipeline := Coll.Aggregate;
  try
    for i := 0 to PipeArr.Count - 1 do
    begin
      if PipeArr.Items[i] is TJSONObject then
      begin
        Stage := PipeArr.Items[i] as TJSONObject;
        if Stage.Count > 0 then
        begin
          // Extract stage operator ($match, $group, $sort, etc.) and its value JSON
          StageName   := Stage.Pairs[0].JsonString.Value;       // e.g. "$match"
          StageValStr := Stage.Pairs[0].JsonValue.ToJSON;       // e.g. {"active":true}
          Pipeline.Stage(StageName, StageValStr).&End;
        end;
      end;
    end;

    Cursor := Pipeline.Open;
    Doc    := TMongoDocument.Create(Ctx.Env);
    Arr    := TJSONArray.Create;
    try
      while Cursor.Next(Doc) do
      begin
        Item := TJSONObject.ParseJSONValue(Doc.AsJSON);
        if Item <> nil then
          Arr.AddElement(Item)
        else
          Arr.AddElement(TJSONObject.Create);
        Doc.Clear;
      end;
    finally
      Doc.Free;
    end;
  finally
    PipeArr.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('documents', Arr);
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TMongoFDTool.DoCount(Ctx: TMongoContext; Coll: TMongoCollection; const P: TMongoFDParams): TJSONObject;
var
  Query: TMongoQuery;
  N:     Int64;
begin
  Query := TMongoQuery.Create(Ctx.Env);
  Query.Match(P.Filter).&End;
  N := Coll.Count(Query);

  Result := TJSONObject.Create;
  Result.AddPair('count', TJSONNumber.Create(N));
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TMongoFDTool.ExecuteWithParams(const AParams: TMongoFDParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Ctx:  TMongoContext;
  Coll: TMongoCollection;
  R:    TJSONObject;
begin
  try
    if Trim(AParams.Database) = '' then
      raise Exception.Create('"database" is required');
    if Trim(AParams.Collection) = '' then
      raise Exception.Create('"collection" is required');

    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    Ctx := TMongoContext.Create(Self, BuildURI(AParams));
    try
      Coll := Ctx.Conn.GetCollection(AParams.Database, AParams.Collection);
      try
        if      Op = 'find'        then R := DoFind(Ctx, Coll, AParams)
        else if Op = 'find_one'    then R := DoFindOne(Ctx, Coll, AParams)
        else if Op = 'insert_one'  then R := DoInsertOne(Ctx, Coll, AParams)
        else if Op = 'insert_many' then R := DoInsertMany(Ctx, Coll, AParams)
        else if Op = 'update_one'  then R := DoUpdateOp(Ctx, Coll, AParams, False)
        else if Op = 'update_many' then R := DoUpdateOp(Ctx, Coll, AParams, True)
        else if Op = 'delete_one'  then R := DoDeleteOp(Ctx, Coll, AParams, False)
        else if Op = 'delete_many' then R := DoDeleteOp(Ctx, Coll, AParams, True)
        else if Op = 'aggregate'   then R := DoAggregate(Ctx, Coll, AParams)
        else if Op = 'count'       then R := DoCount(Ctx, Coll, AParams)
        else raise Exception.CreateFmt('Unknown operation "%s"', [Op]);
      finally
        Coll.Free;
      end;
    finally
      Ctx.Free;
    end;

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

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-mongodb',
    function: IAiMCPTool
    begin
      Result := TMongoFDTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-mongodb');
end;

end.
