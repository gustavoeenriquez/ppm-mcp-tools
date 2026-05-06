unit MCPTool.GCS;

(*
  MCPTool.GCS  ·  mcp-gcs  (port 8643)
  Google Cloud Storage JSON API v1.

  Auth: OAuth2 Access Token (Bearer).
  Obtain via: gcloud auth print-access-token  or  service account token exchange.

  Operations:
    list_buckets         - GET  https://storage.googleapis.com/storage/v1/b?project={ProjectId}
    list_objects         - GET  https://storage.googleapis.com/storage/v1/b/{Bucket}/o
    get_object           - GET  https://storage.googleapis.com/storage/v1/b/{Bucket}/o/{Object}?alt=media
    get_object_metadata  - GET  https://storage.googleapis.com/storage/v1/b/{Bucket}/o/{Object}
    upload_object        - POST https://storage.googleapis.com/upload/storage/v1/b/{Bucket}/o?uploadType=media&name={ObjectName}
    delete_object        - DELETE https://storage.googleapis.com/storage/v1/b/{Bucket}/o/{Object}
    copy_object          - POST https://storage.googleapis.com/storage/v1/b/{SourceBucket}/o/{SourceObject}/copyTo/b/{DestBucket}/o/{DestObject}
    create_bucket        - POST https://storage.googleapis.com/storage/v1/b?project={ProjectId}
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type

  TGCSParams = class
  private
    FOperation   : string;
    FAccessToken : string;
    FProjectId   : string;
    FBucket      : string;
    FObjectName  : string;
    FContent     : string;
    FContentType : string;
    FSourceBucket: string;
    FSourceObject: string;
    FDestBucket  : string;
    FDestObject  : string;
    FPrefix      : string;
  public
    [AiMCPSchemaDescription('Operation: list_buckets, list_objects, get_object, get_object_metadata, upload_object, delete_object, copy_object, create_bucket')]
    property Operation   : string read FOperation    write FOperation;

    [AiMCPSchemaDescription('OAuth2 access token (Bearer). Obtain via: gcloud auth print-access-token')]
    property AccessToken : string read FAccessToken  write FAccessToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('GCP project ID (required for list_buckets, create_bucket)')]
    property ProjectId   : string read FProjectId    write FProjectId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Bucket name (required for most operations)')]
    property Bucket      : string read FBucket       write FBucket;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Object name / path within the bucket (e.g. folder/file.txt)')]
    property ObjectName  : string read FObjectName   write FObjectName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Object content string for upload_object')]
    property Content     : string read FContent      write FContent;

    [AiMCPOptional]
    [AiMCPSchemaDescription('MIME type for upload_object (default: application/octet-stream)')]
    property ContentType : string read FContentType  write FContentType;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Source bucket for copy_object')]
    property SourceBucket: string read FSourceBucket write FSourceBucket;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Source object name for copy_object')]
    property SourceObject: string read FSourceObject write FSourceObject;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Destination bucket for copy_object')]
    property DestBucket  : string read FDestBucket   write FDestBucket;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Destination object name for copy_object')]
    property DestObject  : string read FDestObject   write FDestObject;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Filter prefix for list_objects')]
    property Prefix      : string read FPrefix       write FPrefix;
  end;

  TGCSTool = class(TAiMCPToolBase<TGCSParams>)
  private
    function ApiGet(const URL, AccessToken: string): string;
    function ApiPost(const URL, AccessToken, Body, BodyContentType: string): string;
    function ApiDelete(const URL, AccessToken: string): Integer;
    function EncodeObjectName(const ObjName: string): string;

    function DoListBuckets(const P: TGCSParams): TJSONObject;
    function DoListObjects(const P: TGCSParams): TJSONObject;
    function DoGetObject(const P: TGCSParams): TJSONObject;
    function DoGetObjectMetadata(const P: TGCSParams): TJSONObject;
    function DoUploadObject(const P: TGCSParams): TJSONObject;
    function DoDeleteObject(const P: TGCSParams): TJSONObject;
    function DoCopyObject(const P: TGCSParams): TJSONObject;
    function DoCreateBucket(const P: TGCSParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TGCSParams;
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
  System.Net.URLClient,
  System.NetEncoding;

const
  GCS_BASE        = 'https://storage.googleapis.com/storage/v1';
  GCS_UPLOAD_BASE = 'https://storage.googleapis.com/upload/storage/v1';

{ TGCSTool }

constructor TGCSTool.Create;
begin
  inherited;
  FName        := 'mcp-gcs';
  FDescription :=
    'Google Cloud Storage JSON API v1 — buckets and objects. ' +
    'Auth: OAuth2 Access Token (gcloud auth print-access-token or service account). ' +
    'Operations: ' +
    'list_buckets (params: projectId), ' +
    'list_objects (params: bucket, prefix?), ' +
    'get_object (params: bucket, objectName) — downloads content, ' +
    'get_object_metadata (params: bucket, objectName), ' +
    'upload_object (params: bucket, objectName, content, contentType?), ' +
    'delete_object (params: bucket, objectName), ' +
    'copy_object (params: sourceBucket, sourceObject, destBucket, destObject), ' +
    'create_bucket (params: projectId, bucket). ' +
    'All operations require accessToken.';
end;

function TGCSTool.EncodeObjectName(const ObjName: string): string;
begin
  Result := TNetEncoding.URL.Encode(ObjName);
end;

function TGCSTool.ApiGet(const URL, AccessToken: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 60000;
    Resp := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + AccessToken)]);
    Result := Resp.ContentAsString;
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('GCS API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 300)]);
  finally
    HTTP.Free;
  end;
end;

function TGCSTool.ApiPost(const URL, AccessToken, Body, BodyContentType: string): string;
var
  HTTP  : THTTPClient;
  Resp  : IHTTPResponse;
  Stream: TStringStream;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 60000;
    Resp := HTTP.Post(URL, Stream, nil, [
      TNameValuePair.Create('Authorization', 'Bearer ' + AccessToken),
      TNameValuePair.Create('Content-Type',  BodyContentType)
    ]);
    Result := Resp.ContentAsString;
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('GCS API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 300)]);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TGCSTool.ApiDelete(const URL, AccessToken: string): Integer;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Delete(URL, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + AccessToken)]);
    Result := Resp.StatusCode;
    if (Resp.StatusCode >= 400) and (Resp.StatusCode <> 404) then
      raise Exception.CreateFmt('GCS API HTTP %d: %s',
        [Resp.StatusCode, Resp.ContentAsString.Substring(0, 300)]);
  finally
    HTTP.Free;
  end;
end;

function TGCSTool.DoListBuckets(const P: TGCSParams): TJSONObject;
var
  URL     : string;
  RespStr : string;
  Parsed  : TJSONValue;
begin
  if Trim(P.ProjectId) = '' then
    raise Exception.Create('"projectId" is required for list_buckets');
  URL     := Format('%s/b?project=%s', [GCS_BASE, TNetEncoding.URL.EncodeQuery(Trim(P.ProjectId))]);
  RespStr := ApiGet(URL, P.AccessToken);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
      Result.AddPair('result', Parsed.Clone as TJSONObject)
    else
      Result.AddPair('result', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGCSTool.DoListObjects(const P: TGCSParams): TJSONObject;
var
  URL     : string;
  RespStr : string;
  Parsed  : TJSONValue;
begin
  if Trim(P.Bucket) = '' then
    raise Exception.Create('"bucket" is required for list_objects');
  URL := Format('%s/b/%s/o', [GCS_BASE, TNetEncoding.URL.EncodeQuery(Trim(P.Bucket))]);
  if Trim(P.Prefix) <> '' then
    URL := URL + '?prefix=' + TNetEncoding.URL.EncodeQuery(Trim(P.Prefix));
  RespStr := ApiGet(URL, P.AccessToken);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
      Result.AddPair('result', Parsed.Clone as TJSONObject)
    else
      Result.AddPair('result', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGCSTool.DoGetObject(const P: TGCSParams): TJSONObject;
var
  URL     : string;
  Content : string;
begin
  if Trim(P.Bucket)     = '' then raise Exception.Create('"bucket" is required for get_object');
  if Trim(P.ObjectName) = '' then raise Exception.Create('"objectName" is required for get_object');
  URL     := Format('%s/b/%s/o/%s?alt=media',
    [GCS_BASE,
     TNetEncoding.URL.EncodeQuery(Trim(P.Bucket)),
     EncodeObjectName(Trim(P.ObjectName))]);
  Content := ApiGet(URL, P.AccessToken);
  Result  := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('content', Content);
  Result.AddPair('length',  TJSONNumber.Create(Length(Content)));
end;

function TGCSTool.DoGetObjectMetadata(const P: TGCSParams): TJSONObject;
var
  URL     : string;
  RespStr : string;
  Parsed  : TJSONValue;
begin
  if Trim(P.Bucket)     = '' then raise Exception.Create('"bucket" is required for get_object_metadata');
  if Trim(P.ObjectName) = '' then raise Exception.Create('"objectName" is required for get_object_metadata');
  URL     := Format('%s/b/%s/o/%s',
    [GCS_BASE,
     TNetEncoding.URL.EncodeQuery(Trim(P.Bucket)),
     EncodeObjectName(Trim(P.ObjectName))]);
  RespStr := ApiGet(URL, P.AccessToken);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
      Result.AddPair('metadata', Parsed.Clone as TJSONObject)
    else
      Result.AddPair('metadata', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGCSTool.DoUploadObject(const P: TGCSParams): TJSONObject;
var
  URL      : string;
  CT       : string;
  RespStr  : string;
  Parsed   : TJSONValue;
begin
  if Trim(P.Bucket)     = '' then raise Exception.Create('"bucket" is required for upload_object');
  if Trim(P.ObjectName) = '' then raise Exception.Create('"objectName" is required for upload_object');
  CT := Trim(P.ContentType);
  if CT = '' then CT := 'application/octet-stream';
  URL := Format('%s/b/%s/o?uploadType=media&name=%s',
    [GCS_UPLOAD_BASE,
     TNetEncoding.URL.EncodeQuery(Trim(P.Bucket)),
     TNetEncoding.URL.EncodeQuery(Trim(P.ObjectName))]);
  RespStr := ApiPost(URL, P.AccessToken, P.Content, CT);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
      Result.AddPair('object', Parsed.Clone as TJSONObject)
    else
      Result.AddPair('object', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGCSTool.DoDeleteObject(const P: TGCSParams): TJSONObject;
var
  URL    : string;
  Status : Integer;
begin
  if Trim(P.Bucket)     = '' then raise Exception.Create('"bucket" is required for delete_object');
  if Trim(P.ObjectName) = '' then raise Exception.Create('"objectName" is required for delete_object');
  URL    := Format('%s/b/%s/o/%s',
    [GCS_BASE,
     TNetEncoding.URL.EncodeQuery(Trim(P.Bucket)),
     EncodeObjectName(Trim(P.ObjectName))]);
  Status := ApiDelete(URL, P.AccessToken);
  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('deleted', Trim(P.ObjectName));
  Result.AddPair('status',  TJSONNumber.Create(Status));
end;

function TGCSTool.DoCopyObject(const P: TGCSParams): TJSONObject;
var
  URL     : string;
  RespStr : string;
  Parsed  : TJSONValue;
begin
  if Trim(P.SourceBucket) = '' then raise Exception.Create('"sourceBucket" is required for copy_object');
  if Trim(P.SourceObject) = '' then raise Exception.Create('"sourceObject" is required for copy_object');
  if Trim(P.DestBucket)   = '' then raise Exception.Create('"destBucket" is required for copy_object');
  if Trim(P.DestObject)   = '' then raise Exception.Create('"destObject" is required for copy_object');
  URL := Format('%s/b/%s/o/%s/copyTo/b/%s/o/%s',
    [GCS_BASE,
     TNetEncoding.URL.EncodeQuery(Trim(P.SourceBucket)),
     EncodeObjectName(Trim(P.SourceObject)),
     TNetEncoding.URL.EncodeQuery(Trim(P.DestBucket)),
     EncodeObjectName(Trim(P.DestObject))]);
  RespStr := ApiPost(URL, P.AccessToken, '{}', 'application/json');
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
      Result.AddPair('object', Parsed.Clone as TJSONObject)
    else
      Result.AddPair('object', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGCSTool.DoCreateBucket(const P: TGCSParams): TJSONObject;
var
  URL     : string;
  Body    : string;
  RespStr : string;
  Parsed  : TJSONValue;
begin
  if Trim(P.ProjectId) = '' then raise Exception.Create('"projectId" is required for create_bucket');
  if Trim(P.Bucket)    = '' then raise Exception.Create('"bucket" is required for create_bucket');
  URL     := Format('%s/b?project=%s',
    [GCS_BASE, TNetEncoding.URL.EncodeQuery(Trim(P.ProjectId))]);
  Body    := Format('{"name":"%s"}', [Trim(P.Bucket)]);
  RespStr := ApiPost(URL, P.AccessToken, Body, 'application/json');
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
      Result.AddPair('bucket', Parsed.Clone as TJSONObject)
    else
      Result.AddPair('bucket', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGCSTool.ExecuteWithParams(const AParams: TGCSParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    if Trim(AParams.AccessToken) = '' then
      raise Exception.Create('"accessToken" (OAuth2 Bearer token) is required');
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list_buckets'        then R := DoListBuckets(AParams)
    else if Op = 'list_objects'        then R := DoListObjects(AParams)
    else if Op = 'get_object'          then R := DoGetObject(AParams)
    else if Op = 'get_object_metadata' then R := DoGetObjectMetadata(AParams)
    else if Op = 'upload_object'       then R := DoUploadObject(AParams)
    else if Op = 'delete_object'       then R := DoDeleteObject(AParams)
    else if Op = 'copy_object'         then R := DoCopyObject(AParams)
    else if Op = 'create_bucket'       then R := DoCreateBucket(AParams)
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

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-gcs',
    function: IAiMCPTool
    begin
      Result := TGCSTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-gcs');
end;

end.
