unit MCPTool.S3;

(*
  MCPTool.S3  *  mcp-s3  (port 8645)

  Amazon S3 / S3-compatible REST API client.

  Two authentication modes:
    1. PresignedUrl mode  — caller provides a pre-signed URL that already contains
                            auth query parameters; the tool makes the HTTP request
                            directly without adding any auth headers.
    2. Basic auth mode    — for MinIO / S3-compatible endpoints; the tool sends
                            AccessKeyId:SecretAccessKey as an HTTP Basic auth header.

  Operations:
    list_buckets   - GET {EndpointUrl}/                                   (returns XML)
    list_objects   - GET {EndpointUrl}/{Bucket}?list-type=2&prefix=&max-keys=
    get_object     - GET {EndpointUrl}/{Bucket}/{Key}
    put_object     - PUT {EndpointUrl}/{Bucket}/{Key}   with Content body
    delete_object  - DELETE {EndpointUrl}/{Bucket}/{Key}
    create_bucket  - PUT {EndpointUrl}/{Bucket}
    head_object    - GET {EndpointUrl}/{Bucket}/{Key}   returns headers only

  Note: AWS Signature V4 is not implemented here. For AWS S3, supply pre-signed
  URLs. For MinIO / S3-compatible servers, supply AccessKeyId + SecretAccessKey
  which are forwarded as HTTP Basic authentication.
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type

  // -- Parameters -------------------------------------------------------------

  TS3Params = class
  private
    FOperation:      string;
    FEndpointUrl:    string;
    FBucket:         string;
    FKey:            string;
    FAccessKeyId:    string;
    FSecretAccessKey: string;
    FPresignedUrl:   string;
    FContent:        string;
    FContentType:    string;
    FPrefix:         string;
    FMaxKeys:        Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_buckets, list_objects, get_object, put_object, delete_object, create_bucket, head_object')]
    property Operation:       string  read FOperation       write FOperation;

    [AiMCPSchemaDescription('S3 endpoint URL, e.g. https://s3.amazonaws.com or http://minio:9000')]
    property EndpointUrl:     string  read FEndpointUrl     write FEndpointUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Bucket name (required for all operations except list_buckets)')]
    property Bucket:          string  read FBucket          write FBucket;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Object key / path within the bucket (required for object operations)')]
    property Key:             string  read FKey             write FKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('AWS Access Key ID or MinIO username — used as Basic auth username')]
    property AccessKeyId:     string  read FAccessKeyId     write FAccessKeyId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('AWS Secret Access Key or MinIO password — used as Basic auth password')]
    property SecretAccessKey: string  read FSecretAccessKey write FSecretAccessKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Pre-signed URL (already contains auth query params). When set, EndpointUrl/Bucket/Key are ignored and no auth headers are added')]
    property PresignedUrl:    string  read FPresignedUrl    write FPresignedUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Object content string for put_object')]
    property Content:         string  read FContent         write FContent;

    [AiMCPOptional]
    [AiMCPSchemaDescription('MIME content type for put_object (default: application/octet-stream)')]
    property ContentType:     string  read FContentType     write FContentType;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Key prefix filter for list_objects')]
    property Prefix:          string  read FPrefix          write FPrefix;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum number of keys to return for list_objects (default: 1000)')]
    property MaxKeys:         Integer read FMaxKeys         write FMaxKeys;
  end;

  // -- Tool -------------------------------------------------------------------

  TS3Tool = class(TAiMCPToolBase<TS3Params>)
  private
    function BuildURL(const P: TS3Params; const Path: string): string;
    function BasicAuthHeader(const AccessKeyId, SecretAccessKey: string): string;

    function HttpGetWithAuth(const P: TS3Params; const URL: string): string;
    function HttpGetWithAuthResp(const P: TS3Params; const URL: string;
      out StatusCode: Integer; out ContentType: string; out ContentLen: Int64): string;
    function HttpPutWithAuth(const P: TS3Params; const URL, Body, ContentType: string): Integer;
    function HttpDeleteWithAuth(const P: TS3Params; const URL: string): Integer;

    function DoListBuckets(const P: TS3Params): TJSONObject;
    function DoListObjects(const P: TS3Params): TJSONObject;
    function DoGetObject(const P: TS3Params): TJSONObject;
    function DoPutObject(const P: TS3Params): TJSONObject;
    function DoDeleteObject(const P: TS3Params): TJSONObject;
    function DoCreateBucket(const P: TS3Params): TJSONObject;
    function DoHeadObject(const P: TS3Params): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TS3Params;
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

// -- TS3Params ----------------------------------------------------------------

constructor TS3Params.Create;
begin
  inherited;
  FMaxKeys := 1000;
end;

// -- TS3Tool helpers ----------------------------------------------------------

function TS3Tool.BuildURL(const P: TS3Params; const Path: string): string;
var
  Base: string;
begin
  if P.PresignedUrl <> '' then
  begin
    Result := P.PresignedUrl;
  end
  else
  begin
    Base := P.EndpointUrl;
    if Base.EndsWith('/') then
      Base := Base.Substring(0, Length(Base) - 1);
    Result := Base + Path;
  end;
end;

function TS3Tool.BasicAuthHeader(const AccessKeyId, SecretAccessKey: string): string;
var
  Raw:     string;
  Encoded: string;
begin
  Raw     := AccessKeyId + ':' + SecretAccessKey;
  Encoded := TNetEncoding.Base64.Encode(Raw);
  Result  := 'Basic ' + Encoded;
end;

function TS3Tool.HttpGetWithAuth(const P: TS3Params; const URL: string): string;
var
  HTTP:    THTTPClient;
  Resp:    IHTTPResponse;
  Headers: TArray<TNameValuePair>;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 60000;

    if (P.PresignedUrl <> '') then
    begin
      // Pre-signed URL mode: no auth header
      Resp := HTTP.Get(URL);
    end
    else if (P.AccessKeyId <> '') then
    begin
      // Basic auth mode (MinIO / S3-compatible)
      SetLength(Headers, 1);
      Headers[0] := TNameValuePair.Create('Authorization',
        BasicAuthHeader(P.AccessKeyId, P.SecretAccessKey));
      Resp := HTTP.Get(URL, nil, Headers);
    end
    else
    begin
      // No auth
      Resp := HTTP.Get(URL);
    end;

    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('S3 HTTP %d: %s',
        [Resp.StatusCode, Resp.ContentAsString(TEncoding.UTF8).Substring(0, 500)]);

    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TS3Tool.HttpGetWithAuthResp(const P: TS3Params; const URL: string;
  out StatusCode: Integer; out ContentType: string; out ContentLen: Int64): string;
var
  HTTP:    THTTPClient;
  Resp:    IHTTPResponse;
  Headers: TArray<TNameValuePair>;
  i:       Integer;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 60000;

    if (P.PresignedUrl <> '') then
    begin
      Resp := HTTP.Get(URL);
    end
    else if (P.AccessKeyId <> '') then
    begin
      SetLength(Headers, 1);
      Headers[0] := TNameValuePair.Create('Authorization',
        BasicAuthHeader(P.AccessKeyId, P.SecretAccessKey));
      Resp := HTTP.Get(URL, nil, Headers);
    end
    else
    begin
      Resp := HTTP.Get(URL);
    end;

    StatusCode  := Resp.StatusCode;
    ContentType := '';
    ContentLen  := -1;

    for i := 0 to Length(Resp.Headers) - 1 do
    begin
      if SameText(Resp.Headers[i].Name, 'Content-Type') then
        ContentType := Resp.Headers[i].Value;
      if SameText(Resp.Headers[i].Name, 'Content-Length') then
        ContentLen := StrToInt64Def(Resp.Headers[i].Value, -1);
    end;

    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TS3Tool.HttpPutWithAuth(const P: TS3Params; const URL, Body,
  ContentType: string): Integer;
var
  HTTP:    THTTPClient;
  Resp:    IHTTPResponse;
  Stream:  TStringStream;
  Headers: TArray<TNameValuePair>;
  CT:      string;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 60000;

    CT := ContentType;
    if CT = '' then
      CT := 'application/octet-stream';

    if (P.PresignedUrl <> '') then
    begin
      SetLength(Headers, 1);
      Headers[0] := TNameValuePair.Create('Content-Type', CT);
      Resp := HTTP.Put(URL, Stream, nil, Headers);
    end
    else if (P.AccessKeyId <> '') then
    begin
      SetLength(Headers, 2);
      Headers[0] := TNameValuePair.Create('Authorization',
        BasicAuthHeader(P.AccessKeyId, P.SecretAccessKey));
      Headers[1] := TNameValuePair.Create('Content-Type', CT);
      Resp := HTTP.Put(URL, Stream, nil, Headers);
    end
    else
    begin
      SetLength(Headers, 1);
      Headers[0] := TNameValuePair.Create('Content-Type', CT);
      Resp := HTTP.Put(URL, Stream, nil, Headers);
    end;

    Result := Resp.StatusCode;
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TS3Tool.HttpDeleteWithAuth(const P: TS3Params; const URL: string): Integer;
var
  HTTP:    THTTPClient;
  Resp:    IHTTPResponse;
  Headers: TArray<TNameValuePair>;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;

    if (P.PresignedUrl <> '') then
    begin
      Resp := HTTP.Delete(URL);
    end
    else if (P.AccessKeyId <> '') then
    begin
      SetLength(Headers, 1);
      Headers[0] := TNameValuePair.Create('Authorization',
        BasicAuthHeader(P.AccessKeyId, P.SecretAccessKey));
      Resp := HTTP.Delete(URL, nil, Headers);
    end
    else
    begin
      Resp := HTTP.Delete(URL);
    end;

    Result := Resp.StatusCode;
  finally
    HTTP.Free;
  end;
end;

// -- Operations ---------------------------------------------------------------

function TS3Tool.DoListBuckets(const P: TS3Params): TJSONObject;
var
  URL:    string;
  RawXML: string;
begin
  URL    := BuildURL(P, '/');
  RawXML := HttpGetWithAuth(P, URL);

  Result := TJSONObject.Create;
  Result.AddPair('ok',        TJSONTrue.Create);
  Result.AddPair('operation', 'list_buckets');
  Result.AddPair('raw',       RawXML);
end;

function TS3Tool.DoListObjects(const P: TS3Params): TJSONObject;
var
  URL:     string;
  Path:    string;
  Query:   string;
  MaxK:    Integer;
  RawXML:  string;
begin
  if P.Bucket = '' then
    raise Exception.Create('"bucket" is required for list_objects');

  MaxK  := P.MaxKeys;
  if MaxK <= 0 then
    MaxK := 1000;

  Path  := '/' + P.Bucket;
  Query := 'list-type=2&max-keys=' + IntToStr(MaxK);

  if P.Prefix <> '' then
    Query := Query + '&prefix=' + TNetEncoding.URL.EncodeQuery(P.Prefix);

  URL    := BuildURL(P, Path + '?' + Query);
  RawXML := HttpGetWithAuth(P, URL);

  Result := TJSONObject.Create;
  Result.AddPair('ok',        TJSONTrue.Create);
  Result.AddPair('operation', 'list_objects');
  Result.AddPair('bucket',    P.Bucket);
  if P.Prefix <> '' then
    Result.AddPair('prefix', P.Prefix);
  Result.AddPair('max_keys',  TJSONNumber.Create(MaxK));
  Result.AddPair('raw',       RawXML);
end;

function TS3Tool.DoGetObject(const P: TS3Params): TJSONObject;
var
  URL:         string;
  Path:        string;
  BodyContent: string;
  StatusCode:  Integer;
  CT:          string;
  CL:          Int64;
begin
  if P.Bucket = '' then
    raise Exception.Create('"bucket" is required for get_object');
  if P.Key = '' then
    raise Exception.Create('"key" is required for get_object');

  Path        := '/' + P.Bucket + '/' + P.Key;
  URL         := BuildURL(P, Path);
  BodyContent := HttpGetWithAuthResp(P, URL, StatusCode, CT, CL);

  Result := TJSONObject.Create;
  if (StatusCode >= 200) and (StatusCode < 300) then
    Result.AddPair('ok', TJSONTrue.Create)
  else
    Result.AddPair('ok', TJSONFalse.Create);
  Result.AddPair('status',       TJSONNumber.Create(StatusCode));
  Result.AddPair('bucket',       P.Bucket);
  Result.AddPair('key',          P.Key);
  Result.AddPair('content_type', CT);
  Result.AddPair('length',       TJSONNumber.Create(CL));
  Result.AddPair('content',      BodyContent);
end;

function TS3Tool.DoPutObject(const P: TS3Params): TJSONObject;
var
  URL:    string;
  Path:   string;
  CT:     string;
  Status: Integer;
begin
  if P.Bucket = '' then
    raise Exception.Create('"bucket" is required for put_object');
  if P.Key = '' then
    raise Exception.Create('"key" is required for put_object');

  CT   := P.ContentType;
  if CT = '' then
    CT := 'application/octet-stream';

  Path   := '/' + P.Bucket + '/' + P.Key;
  URL    := BuildURL(P, Path);
  Status := HttpPutWithAuth(P, URL, P.Content, CT);

  Result := TJSONObject.Create;
  if (Status >= 200) and (Status < 300) then
    Result.AddPair('ok', TJSONTrue.Create)
  else
    Result.AddPair('ok', TJSONFalse.Create);
  Result.AddPair('status',       TJSONNumber.Create(Status));
  Result.AddPair('bucket',       P.Bucket);
  Result.AddPair('key',          P.Key);
  Result.AddPair('content_type', CT);
end;

function TS3Tool.DoDeleteObject(const P: TS3Params): TJSONObject;
var
  URL:    string;
  Path:   string;
  Status: Integer;
begin
  if P.Bucket = '' then
    raise Exception.Create('"bucket" is required for delete_object');
  if P.Key = '' then
    raise Exception.Create('"key" is required for delete_object');

  Path   := '/' + P.Bucket + '/' + P.Key;
  URL    := BuildURL(P, Path);
  Status := HttpDeleteWithAuth(P, URL);

  Result := TJSONObject.Create;
  if (Status >= 200) and (Status < 300) then
    Result.AddPair('ok', TJSONTrue.Create)
  else
    Result.AddPair('ok', TJSONFalse.Create);
  Result.AddPair('status',  TJSONNumber.Create(Status));
  Result.AddPair('bucket',  P.Bucket);
  Result.AddPair('key',     P.Key);
  Result.AddPair('deleted', P.Bucket + '/' + P.Key);
end;

function TS3Tool.DoCreateBucket(const P: TS3Params): TJSONObject;
var
  URL:    string;
  Path:   string;
  Status: Integer;
begin
  if P.Bucket = '' then
    raise Exception.Create('"bucket" is required for create_bucket');

  Path   := '/' + P.Bucket;
  URL    := BuildURL(P, Path);
  Status := HttpPutWithAuth(P, URL, '', 'application/xml');

  Result := TJSONObject.Create;
  if (Status >= 200) and (Status < 300) then
    Result.AddPair('ok', TJSONTrue.Create)
  else
    Result.AddPair('ok', TJSONFalse.Create);
  Result.AddPair('status',  TJSONNumber.Create(Status));
  Result.AddPair('created', P.Bucket);
end;

function TS3Tool.DoHeadObject(const P: TS3Params): TJSONObject;
var
  URL:         string;
  Path:        string;
  StatusCode:  Integer;
  CT:          string;
  CL:          Int64;
begin
  if P.Bucket = '' then
    raise Exception.Create('"bucket" is required for head_object');
  if P.Key = '' then
    raise Exception.Create('"key" is required for head_object');

  // S3 HEAD via GET — we read the response headers and discard the body
  Path := '/' + P.Bucket + '/' + P.Key;
  URL  := BuildURL(P, Path);
  HttpGetWithAuthResp(P, URL, StatusCode, CT, CL);

  Result := TJSONObject.Create;
  if (StatusCode >= 200) and (StatusCode < 300) then
    Result.AddPair('ok', TJSONTrue.Create)
  else
    Result.AddPair('ok', TJSONFalse.Create);
  Result.AddPair('status',         TJSONNumber.Create(StatusCode));
  Result.AddPair('bucket',         P.Bucket);
  Result.AddPair('key',            P.Key);
  Result.AddPair('content_type',   CT);
  Result.AddPair('content_length', TJSONNumber.Create(CL));
end;

// -- Main execution -----------------------------------------------------------

function TS3Tool.ExecuteWithParams(const AParams: TS3Params;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then
      raise Exception.Create('"operation" is required');

    if AParams.PresignedUrl = '' then
    begin
      if AParams.EndpointUrl = '' then
        raise Exception.Create('"endpoint_url" is required when presigned_url is not provided');
    end;

    if      Op = 'list_buckets'  then R := DoListBuckets(AParams)
    else if Op = 'list_objects'  then R := DoListObjects(AParams)
    else if Op = 'get_object'    then R := DoGetObject(AParams)
    else if Op = 'put_object'    then R := DoPutObject(AParams)
    else if Op = 'delete_object' then R := DoDeleteObject(AParams)
    else if Op = 'create_bucket' then R := DoCreateBucket(AParams)
    else if Op = 'head_object'   then R := DoHeadObject(AParams)
    else
      raise Exception.CreateFmt('Unknown operation "%s"', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message.Replace('\', '\\').Replace('"', '\"')
                   .Replace(#10, '\n').Replace(#13, '') + '"}')
        .Build;
  end;
end;

constructor TS3Tool.Create;
begin
  inherited;
  FName        := 'mcp-s3';
  FDescription :=
    'Amazon S3 / S3-compatible (MinIO) REST API client. ' +
    'Auth modes: (1) presigned_url — pre-signed URL used directly, no auth headers added; ' +
    '(2) Basic auth — access_key_id + secret_access_key sent as HTTP Basic auth (for MinIO). ' +
    'Operations: ' +
    'list_buckets (GET /; params: endpoint_url + auth), ' +
    'list_objects (list objects in bucket; params: endpoint_url, bucket, prefix?, max_keys?), ' +
    'get_object (download object; params: endpoint_url, bucket, key), ' +
    'put_object (upload object; params: endpoint_url, bucket, key, content?, content_type?), ' +
    'delete_object (delete object; params: endpoint_url, bucket, key), ' +
    'create_bucket (create bucket; params: endpoint_url, bucket), ' +
    'head_object (get object metadata; params: endpoint_url, bucket, key). ' +
    'For AWS S3, use presigned_url. For MinIO, supply endpoint_url + access_key_id + secret_access_key.';
end;

// -- Registration -------------------------------------------------------------

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-s3',
    function: IAiMCPTool
    begin
      Result := TS3Tool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-s3');
end;

end.
