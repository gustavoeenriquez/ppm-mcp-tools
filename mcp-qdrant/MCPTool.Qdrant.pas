unit MCPTool.Qdrant;

{
  MCPTool.Qdrant  ·  mcp-qdrant  (port 8616)
  Qdrant vector database via REST API.

  Operations:
    list_collections  - list all collections
    create_collection - create a new collection with vector config
    delete_collection - delete a collection
    count             - count points in a collection
    upsert            - insert or update points
    search            - vector similarity search
    get_point         - retrieve a single point by ID
    delete_points     - delete points by IDs or filter
    scroll            - scroll through points with optional filter
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TQdrantParams = class
  private
    FOperation:      string;
    FHost:           string;
    FPort:           Integer;
    FApiKey:         string;
    FCollection:     string;
    FPoints:         string;
    FVector:         string;
    FPointId:        string;
    FIds:            string;
    FFilter:         string;
    FLimit:          Integer;
    FVectorSize:     Integer;
    FDistance:       string;
    FWithPayload:    Boolean;
    FWithVector:     Boolean;
    FScoreThreshold: Double;
    FOffset:         Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_collections, create_collection, delete_collection, count, upsert, search, get_point, delete_points, scroll')]
    property Operation:      string  read FOperation      write FOperation;

    [AiMCPSchemaDescription('Qdrant host (default: localhost)')]
    property Host:           string  read FHost           write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Qdrant REST port (default: 6333)')]
    property Port:           Integer read FPort           write FPort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('API key for secured Qdrant deployments')]
    property ApiKey:         string  read FApiKey         write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Collection name')]
    property Collection:     string  read FCollection     write FCollection;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Points as JSON array: [{"id":"uuid-or-int","vector":[0.1,...],"payload":{...}},...] (for upsert)')]
    property Points:         string  read FPoints         write FPoints;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Query vector as JSON float array: [0.1, 0.2, ...] (for search)')]
    property Vector:         string  read FVector         write FVector;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Point ID (string UUID or integer) for get_point')]
    property PointId:        string  read FPointId        write FPointId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Point IDs to delete as JSON array: ["id1","id2"] or [1,2,3]')]
    property Ids:            string  read FIds            write FIds;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Qdrant filter as JSON: {"must":[{"key":"field","match":{"value":"val"}}]}')]
    property Filter:         string  read FFilter         write FFilter;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max results to return (default: 10)')]
    property Limit:          Integer read FLimit          write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Vector dimensions for create_collection')]
    property VectorSize:     Integer read FVectorSize     write FVectorSize;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Distance metric: Cosine, Euclid, Dot, Manhattan (default: Cosine)')]
    property Distance:       string  read FDistance       write FDistance;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Include payload in results (default: true)')]
    property WithPayload:    Boolean read FWithPayload    write FWithPayload;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Include vector in results (default: false)')]
    property WithVector:     Boolean read FWithVector     write FWithVector;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Minimum score threshold for search results (0 = disabled)')]
    property ScoreThreshold: Double  read FScoreThreshold write FScoreThreshold;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Scroll offset for scroll operation')]
    property Offset:         Integer read FOffset         write FOffset;
  end;

  TQdrantTool = class(TAiMCPToolBase<TQdrantParams>)
  private
    function BaseURL(const P: TQdrantParams): string;
    function BuildHeaders(const P: TQdrantParams): string;
    function ApiGet(const URL, ApiKey: string): string;
    function ApiPost(const URL, Body, ApiKey: string): string;
    function ApiPut(const URL, Body, ApiKey: string): string;
    function ApiDelete(const URL, ApiKey: string): string;
    function DoListCollections(const P: TQdrantParams): TJSONObject;
    function DoCreateCollection(const P: TQdrantParams): TJSONObject;
    function DoDeleteCollection(const P: TQdrantParams): TJSONObject;
    function DoCount(const P: TQdrantParams): TJSONObject;
    function DoUpsert(const P: TQdrantParams): TJSONObject;
    function DoSearch(const P: TQdrantParams): TJSONObject;
    function DoGetPoint(const P: TQdrantParams): TJSONObject;
    function DoDeletePoints(const P: TQdrantParams): TJSONObject;
    function DoScroll(const P: TQdrantParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TQdrantParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient;

{ TQdrantParams }

constructor TQdrantParams.Create;
begin
  inherited;
  FHost        := 'localhost';
  FPort        := 6333;
  FLimit       := 10;
  FDistance    := 'Cosine';
  FWithPayload := True;
  FWithVector  := False;
end;

{ TQdrantTool }

function TQdrantTool.BaseURL(const P: TQdrantParams): string;
var
  Port: Integer;
begin
  Port := P.Port;
  if Port <= 0 then Port := 6333;
  Result := Format('http://%s:%d', [Trim(P.Host), Port]);
end;

function TQdrantTool.BuildHeaders(const P: TQdrantParams): string;
begin
  Result := Trim(P.ApiKey);
end;

function TQdrantTool.ApiGet(const URL, ApiKey: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    if ApiKey <> '' then
      Resp := HTTP.Get(URL, nil, [TNameValuePair.Create('api-key', ApiKey)])
    else
      Resp := HTTP.Get(URL);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TQdrantTool.ApiPost(const URL, Body, ApiKey: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    if ApiKey <> '' then
      Resp := HTTP.Post(URL, Stream, nil,
        [TNameValuePair.Create('Content-Type', 'application/json'),
         TNameValuePair.Create('api-key', ApiKey)])
    else
      Resp := HTTP.Post(URL, Stream, nil,
        [TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TQdrantTool.ApiPut(const URL, Body, ApiKey: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    if ApiKey <> '' then
      Resp := HTTP.Put(URL, Stream, nil,
        [TNameValuePair.Create('Content-Type', 'application/json'),
         TNameValuePair.Create('api-key', ApiKey)])
    else
      Resp := HTTP.Put(URL, Stream, nil,
        [TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TQdrantTool.ApiDelete(const URL, ApiKey: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    if ApiKey <> '' then
      Resp := HTTP.Delete(URL, nil,
        [TNameValuePair.Create('api-key', ApiKey)])
    else
      Resp := HTTP.Delete(URL);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TQdrantTool.DoListCollections(const P: TQdrantParams): TJSONObject;
var
  Raw: string;
  J:   TJSONValue;
begin
  Raw := ApiGet(BaseURL(P) + '/collections', BuildHeaders(P));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
    begin
      var Res := J.FindValue('result.collections');
      if Assigned(Res) then
        Result.AddPair('collections', Res.Clone as TJSONValue)
      else
        Result.AddPair('collections', TJSONArray.Create);
    end
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TQdrantTool.DoCreateCollection(const P: TQdrantParams): TJSONObject;
var
  Size:     Integer;
  Dist:     string;
  Body, Raw: string;
begin
  if Trim(P.Collection) = '' then
    raise Exception.Create('"collection" required for create_collection');
  Size := P.VectorSize;
  if Size <= 0 then raise Exception.Create('"vectorSize" required for create_collection');
  Dist := Trim(P.Distance);
  if Dist = '' then Dist := 'Cosine';

  Body := Format('{"vectors":{"size":%d,"distance":"%s"}}', [Size, Dist]);
  Raw  := ApiPut(BaseURL(P) + '/collections/' + Trim(P.Collection), Body, BuildHeaders(P));

  Result := TJSONObject.Create;
  Result.AddPair('collection', P.Collection);
  Result.AddPair('vectorSize', TJSONNumber.Create(Size));
  Result.AddPair('distance',   Dist);
  Result.AddPair('response',   Raw);
  Result.AddPair('ok',         TJSONTrue.Create);
end;

function TQdrantTool.DoDeleteCollection(const P: TQdrantParams): TJSONObject;
var
  Raw: string;
begin
  if Trim(P.Collection) = '' then
    raise Exception.Create('"collection" required for delete_collection');
  Raw := ApiDelete(BaseURL(P) + '/collections/' + Trim(P.Collection), BuildHeaders(P));
  Result := TJSONObject.Create;
  Result.AddPair('collection', P.Collection);
  Result.AddPair('response',   Raw);
  Result.AddPair('ok',         TJSONTrue.Create);
end;

function TQdrantTool.DoCount(const P: TQdrantParams): TJSONObject;
var
  Raw: string;
  J:   TJSONValue;
  N:   TJSONValue;
begin
  if Trim(P.Collection) = '' then
    raise Exception.Create('"collection" required for count');
  Raw := ApiGet(BaseURL(P) + '/collections/' + Trim(P.Collection) + '/points/count',
                BuildHeaders(P));
  J := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
    begin
      N := J.FindValue('result.count');
      if Assigned(N) then
        Result.AddPair('count', N.Clone as TJSONValue)
      else
        Result.AddPair('count', TJSONNumber.Create(0));
    end
    else
      Result.AddPair('count', TJSONNumber.Create(0));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TQdrantTool.DoUpsert(const P: TQdrantParams): TJSONObject;
var
  Pts, Body, Raw: string;
begin
  if Trim(P.Collection) = '' then
    raise Exception.Create('"collection" required for upsert');
  Pts := Trim(P.Points);
  if Pts = '' then
    raise Exception.Create('"points" required: JSON array of {id, vector, payload?}');
  Body := '{"points":' + Pts + '}';
  Raw  := ApiPut(BaseURL(P) + '/collections/' + Trim(P.Collection) + '/points',
                 Body, BuildHeaders(P));
  Result := TJSONObject.Create;
  Result.AddPair('collection', P.Collection);
  Result.AddPair('response',   Raw);
  Result.AddPair('ok',         TJSONTrue.Create);
end;

function TQdrantTool.DoSearch(const P: TQdrantParams): TJSONObject;
var
  Vec, Filt, Body, WP, WV, Raw: string;
  Lim: Integer;
  J:   TJSONValue;
begin
  if Trim(P.Collection) = '' then
    raise Exception.Create('"collection" required for search');
  Vec := Trim(P.Vector);
  if Vec = '' then
    raise Exception.Create('"vector" required: JSON float array');

  Lim := P.Limit;
  if Lim <= 0 then Lim := 10;

  if P.WithPayload then WP := 'true' else WP := 'false';
  if P.WithVector  then WV := 'true' else WV := 'false';

  Body := Format('{"vector":%s,"limit":%d,"with_payload":%s,"with_vector":%s',
                 [Vec, Lim, WP, WV]);

  Filt := Trim(P.Filter);
  if Filt <> '' then
    Body := Body + ',"filter":' + Filt;

  if P.ScoreThreshold > 0 then
    Body := Body + Format(',"score_threshold":%g', [P.ScoreThreshold]);

  Body := Body + '}';

  Raw := ApiPost(BaseURL(P) + '/collections/' + Trim(P.Collection) + '/points/search',
                 Body, BuildHeaders(P));
  J := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
    begin
      var Res := J.FindValue('result');
      if Assigned(Res) then
        Result.AddPair('results', Res.Clone as TJSONValue)
      else
        Result.AddPair('results', TJSONArray.Create);
    end
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TQdrantTool.DoGetPoint(const P: TQdrantParams): TJSONObject;
var
  Raw: string;
  J:   TJSONValue;
begin
  if Trim(P.Collection) = '' then
    raise Exception.Create('"collection" required for get_point');
  if Trim(P.PointId) = '' then
    raise Exception.Create('"pointId" required for get_point');
  Raw := ApiGet(BaseURL(P) + '/collections/' + Trim(P.Collection) +
                '/points/' + Trim(P.PointId), BuildHeaders(P));
  J := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
    begin
      var Res := J.FindValue('result');
      if Assigned(Res) then
        Result.AddPair('point', Res.Clone as TJSONValue)
      else
        Result.AddPair('raw', TJSONString.Create(Raw));
    end
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TQdrantTool.DoDeletePoints(const P: TQdrantParams): TJSONObject;
var
  Body, Raw: string;
  Ids, Filt: string;
begin
  if Trim(P.Collection) = '' then
    raise Exception.Create('"collection" required for delete_points');
  Ids  := Trim(P.Ids);
  Filt := Trim(P.Filter);
  if (Ids = '') and (Filt = '') then
    raise Exception.Create('"ids" or "filter" required for delete_points');

  if Ids <> '' then
    Body := '{"points":' + Ids + '}'
  else
    Body := '{"filter":' + Filt + '}';

  Raw := ApiPost(BaseURL(P) + '/collections/' + Trim(P.Collection) + '/points/delete',
                 Body, BuildHeaders(P));
  Result := TJSONObject.Create;
  Result.AddPair('collection', P.Collection);
  Result.AddPair('response',   Raw);
  Result.AddPair('ok',         TJSONTrue.Create);
end;

function TQdrantTool.DoScroll(const P: TQdrantParams): TJSONObject;
var
  Lim: Integer;
  WP, WV, Body, Raw: string;
  Filt: string;
  J:    TJSONValue;
begin
  if Trim(P.Collection) = '' then
    raise Exception.Create('"collection" required for scroll');
  Lim := P.Limit;
  if Lim <= 0 then Lim := 10;
  if P.WithPayload then WP := 'true' else WP := 'false';
  if P.WithVector  then WV := 'true' else WV := 'false';

  Body := Format('{"limit":%d,"with_payload":%s,"with_vector":%s', [Lim, WP, WV]);
  Filt := Trim(P.Filter);
  if Filt <> '' then
    Body := Body + ',"filter":' + Filt;
  if P.Offset > 0 then
    Body := Body + Format(',"offset":%d', [P.Offset]);
  Body := Body + '}';

  Raw := ApiPost(BaseURL(P) + '/collections/' + Trim(P.Collection) + '/points/scroll',
                 Body, BuildHeaders(P));
  J := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
    begin
      var Res := J.FindValue('result.points');
      if Assigned(Res) then
        Result.AddPair('points', Res.Clone as TJSONValue)
      else
        Result.AddPair('raw', TJSONString.Create(Raw));
    end
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TQdrantTool.ExecuteWithParams(const AParams: TQdrantParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list_collections'  then R := DoListCollections(AParams)
    else if Op = 'create_collection' then R := DoCreateCollection(AParams)
    else if Op = 'delete_collection' then R := DoDeleteCollection(AParams)
    else if Op = 'count'             then R := DoCount(AParams)
    else if Op = 'upsert'            then R := DoUpsert(AParams)
    else if Op = 'search'            then R := DoSearch(AParams)
    else if Op = 'get_point'         then R := DoGetPoint(AParams)
    else if Op = 'delete_points'     then R := DoDeletePoints(AParams)
    else if Op = 'scroll'            then R := DoScroll(AParams)
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

constructor TQdrantTool.Create;
begin
  inherited;
  FName        := 'mcp-qdrant';
  FDescription :=
    'Qdrant vector database access via REST API. ' +
    'Operations: list_collections, create_collection (params: collection, vectorSize, distance?), ' +
    'delete_collection (params: collection), count (params: collection), ' +
    'upsert (params: collection, points=JSON array of {id,vector,payload?}), ' +
    'search (params: collection, vector=float array, limit?, filter?, scoreThreshold?, withPayload?, withVector?), ' +
    'get_point (params: collection, pointId), ' +
    'delete_points (params: collection, ids=JSON array OR filter=JSON), ' +
    'scroll (params: collection, limit?, filter?, offset?, withPayload?, withVector?). ' +
    'Required: host. Optional: port (default 6333), apiKey.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-qdrant',
    function: IAiMCPTool
    begin
      Result := TQdrantTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-qdrant');
end;

end.
