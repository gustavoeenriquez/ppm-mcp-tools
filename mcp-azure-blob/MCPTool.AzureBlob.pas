unit MCPTool.AzureBlob;

(*
  MCPTool.AzureBlob  *  mcp-azure-blob  (port 8641)

  Wraps the Azure Blob Storage REST API using SAS token authentication.

  URL pattern: https://{AccountName}.blob.core.windows.net/{container}/{blob}?{SasToken}

  Operations:
    list_containers    - GET https://{account}.blob.core.windows.net/?comp=list
    list_blobs         - GET https://{account}.blob.core.windows.net/{container}?restype=container&comp=list
    get_blob           - GET https://{account}.blob.core.windows.net/{container}/{blob}
    put_blob           - PUT with body content to   https://{account}.blob.core.windows.net/{container}/{blob}
    delete_blob        - DELETE https://{account}.blob.core.windows.net/{container}/{blob}
    create_container   - PUT https://{account}.blob.core.windows.net/{container}?restype=container
    delete_container   - DELETE https://{account}.blob.core.windows.net/{container}?restype=container
    get_blob_properties - GET (returns content-length + content-type as JSON)

  Auth: SAS token only. Append ?{sasToken} or &{sasToken} to URL as appropriate.
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type

  // -- Parameters -------------------------------------------------------------

  TAzureBlobParams = class
  private
    FOperation:   string;
    FAccountName: string;
    FSasToken:    string;
    FContainer:   string;
    FBlobName:    string;
    FContent:     string;
    FContentType: string;
  public
    [AiMCPSchemaDescription('Operation: list_containers, list_blobs, get_blob, put_blob, delete_blob, create_container, delete_container, get_blob_properties')]
    property Operation:   string read FOperation   write FOperation;

    [AiMCPSchemaDescription('Azure storage account name (e.g. mystorageaccount)')]
    property AccountName: string read FAccountName write FAccountName;

    [AiMCPSchemaDescription('SAS token query string without leading ? (e.g. sv=2021-06-08&ss=b&srt=co&sp=rwdlacx&se=...&sig=...)')]
    property SasToken:    string read FSasToken    write FSasToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Container name (required for operations that target a container or blob)')]
    property Container:   string read FContainer   write FContainer;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Blob name / path within the container (required for blob operations)')]
    property BlobName:    string read FBlobName    write FBlobName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Blob content string (required for put_blob)')]
    property Content:     string read FContent     write FContent;

    [AiMCPOptional]
    [AiMCPSchemaDescription('MIME content type for put_blob (default: application/octet-stream)')]
    property ContentType: string read FContentType write FContentType;
  end;

  // -- Tool -------------------------------------------------------------------

  TAzureBlobTool = class(TAiMCPToolBase<TAzureBlobParams>)
  private
    function BuildBaseURL(const AccountName: string): string;
    function AppendSas(const URL, SasToken: string): string;

    function DoListContainers(const P: TAzureBlobParams): TJSONObject;
    function DoListBlobs(const P: TAzureBlobParams): TJSONObject;
    function DoGetBlob(const P: TAzureBlobParams): TJSONObject;
    function DoPutBlob(const P: TAzureBlobParams): TJSONObject;
    function DoDeleteBlob(const P: TAzureBlobParams): TJSONObject;
    function DoCreateContainer(const P: TAzureBlobParams): TJSONObject;
    function DoDeleteContainer(const P: TAzureBlobParams): TJSONObject;
    function DoGetBlobProperties(const P: TAzureBlobParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TAzureBlobParams;
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

// -- Helpers ------------------------------------------------------------------

function TAzureBlobTool.BuildBaseURL(const AccountName: string): string;
begin
  Result := 'https://' + AccountName + '.blob.core.windows.net';
end;

function TAzureBlobTool.AppendSas(const URL, SasToken: string): string;
begin
  if Pos('?', URL) > 0 then
    Result := URL + '&' + SasToken
  else
    Result := URL + '?' + SasToken;
end;

// -- Operations ---------------------------------------------------------------

function TAzureBlobTool.DoListContainers(const P: TAzureBlobParams): TJSONObject;
var
  HTTP:    THTTPClient;
  Resp:    IHTTPResponse;
  URL:     string;
  RawXML:  string;
begin
  URL  := BuildBaseURL(P.AccountName) + '/?comp=list';
  URL  := AppendSas(URL, P.SasToken);

  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Get(URL, nil, [TNameValuePair.Create('Accept', 'application/xml')]);
    RawXML := Resp.ContentAsString(TEncoding.UTF8);
    Result := TJSONObject.Create;
    Result.AddPair('ok',     TJSONTrue.Create);
    Result.AddPair('status', TJSONNumber.Create(Resp.StatusCode));
    Result.AddPair('raw',    RawXML);
  finally
    HTTP.Free;
  end;
end;

function TAzureBlobTool.DoListBlobs(const P: TAzureBlobParams): TJSONObject;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  URL:    string;
  RawXML: string;
begin
  if P.Container = '' then
    raise Exception.Create('"container" is required for list_blobs');

  URL  := BuildBaseURL(P.AccountName) + '/' + P.Container + '?restype=container&comp=list';
  URL  := AppendSas(URL, P.SasToken);

  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Get(URL, nil, [TNameValuePair.Create('Accept', 'application/xml')]);
    RawXML := Resp.ContentAsString(TEncoding.UTF8);
    Result := TJSONObject.Create;
    Result.AddPair('ok',        TJSONTrue.Create);
    Result.AddPair('status',    TJSONNumber.Create(Resp.StatusCode));
    Result.AddPair('container', P.Container);
    Result.AddPair('raw',       RawXML);
  finally
    HTTP.Free;
  end;
end;

function TAzureBlobTool.DoGetBlob(const P: TAzureBlobParams): TJSONObject;
var
  HTTP:    THTTPClient;
  Resp:    IHTTPResponse;
  URL:     string;
  Content: string;
begin
  if P.Container = '' then
    raise Exception.Create('"container" is required for get_blob');
  if P.BlobName = '' then
    raise Exception.Create('"blob_name" is required for get_blob');

  URL  := BuildBaseURL(P.AccountName) + '/' + P.Container + '/' + P.BlobName;
  URL  := AppendSas(URL, P.SasToken);

  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 60000;
    Resp    := HTTP.Get(URL);
    Content := Resp.ContentAsString(TEncoding.UTF8);
    Result  := TJSONObject.Create;
    Result.AddPair('ok',      TJSONTrue.Create);
    Result.AddPair('status',  TJSONNumber.Create(Resp.StatusCode));
    Result.AddPair('content', Content);
    Result.AddPair('length',  TJSONNumber.Create(Length(Content)));
  finally
    HTTP.Free;
  end;
end;

function TAzureBlobTool.DoPutBlob(const P: TAzureBlobParams): TJSONObject;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  URL:    string;
  CT:     string;
  Stream: TStringStream;
  Status: Integer;
begin
  if P.Container = '' then
    raise Exception.Create('"container" is required for put_blob');
  if P.BlobName = '' then
    raise Exception.Create('"blob_name" is required for put_blob');

  CT := P.ContentType;
  if CT = '' then
    CT := 'application/octet-stream';

  URL  := BuildBaseURL(P.AccountName) + '/' + P.Container + '/' + P.BlobName;
  URL  := AppendSas(URL, P.SasToken);

  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(P.Content, TEncoding.UTF8);
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 60000;
    Resp   := HTTP.Put(URL, Stream, nil,
      [TNameValuePair.Create('Content-Type',    CT),
       TNameValuePair.Create('x-ms-blob-type',  'BlockBlob')]);
    Status := Resp.StatusCode;
    Result := TJSONObject.Create;
    if (Status >= 200) and (Status < 300) then
      Result.AddPair('ok', TJSONTrue.Create)
    else
      Result.AddPair('ok', TJSONFalse.Create);
    Result.AddPair('status',    TJSONNumber.Create(Status));
    Result.AddPair('container', P.Container);
    Result.AddPair('blob',      P.BlobName);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TAzureBlobTool.DoDeleteBlob(const P: TAzureBlobParams): TJSONObject;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  URL:    string;
  Status: Integer;
begin
  if P.Container = '' then
    raise Exception.Create('"container" is required for delete_blob');
  if P.BlobName = '' then
    raise Exception.Create('"blob_name" is required for delete_blob');

  URL  := BuildBaseURL(P.AccountName) + '/' + P.Container + '/' + P.BlobName;
  URL  := AppendSas(URL, P.SasToken);

  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;
    Resp   := HTTP.Delete(URL, nil, [TNameValuePair.Create('Accept', 'application/xml')]);
    Status := Resp.StatusCode;
    Result := TJSONObject.Create;
    if (Status >= 200) and (Status < 300) then
      Result.AddPair('ok', TJSONTrue.Create)
    else
      Result.AddPair('ok', TJSONFalse.Create);
    Result.AddPair('status',  TJSONNumber.Create(Status));
    Result.AddPair('deleted', P.Container + '/' + P.BlobName);
  finally
    HTTP.Free;
  end;
end;

function TAzureBlobTool.DoCreateContainer(const P: TAzureBlobParams): TJSONObject;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  URL:    string;
  Stream: TStringStream;
  Status: Integer;
begin
  if P.Container = '' then
    raise Exception.Create('"container" is required for create_container');

  URL  := BuildBaseURL(P.AccountName) + '/' + P.Container + '?restype=container';
  URL  := AppendSas(URL, P.SasToken);

  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create('', TEncoding.UTF8);
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;
    Resp   := HTTP.Put(URL, Stream, nil,
      [TNameValuePair.Create('Content-Length', '0')]);
    Status := Resp.StatusCode;
    Result := TJSONObject.Create;
    if (Status >= 200) and (Status < 300) then
      Result.AddPair('ok', TJSONTrue.Create)
    else
      Result.AddPair('ok', TJSONFalse.Create);
    Result.AddPair('status',  TJSONNumber.Create(Status));
    Result.AddPair('created', P.Container);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TAzureBlobTool.DoDeleteContainer(const P: TAzureBlobParams): TJSONObject;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  URL:    string;
  Status: Integer;
begin
  if P.Container = '' then
    raise Exception.Create('"container" is required for delete_container');

  URL  := BuildBaseURL(P.AccountName) + '/' + P.Container + '?restype=container';
  URL  := AppendSas(URL, P.SasToken);

  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;
    Resp   := HTTP.Delete(URL, nil, [TNameValuePair.Create('Accept', 'application/xml')]);
    Status := Resp.StatusCode;
    Result := TJSONObject.Create;
    if (Status >= 200) and (Status < 300) then
      Result.AddPair('ok', TJSONTrue.Create)
    else
      Result.AddPair('ok', TJSONFalse.Create);
    Result.AddPair('status',  TJSONNumber.Create(Status));
    Result.AddPair('deleted', P.Container);
  finally
    HTTP.Free;
  end;
end;

function TAzureBlobTool.DoGetBlobProperties(const P: TAzureBlobParams): TJSONObject;
var
  HTTP:        THTTPClient;
  Resp:        IHTTPResponse;
  URL:         string;
  HeadersObj:  TJSONObject;
  i:           Integer;
  HName:       string;
  HValue:      string;
begin
  if P.Container = '' then
    raise Exception.Create('"container" is required for get_blob_properties');
  if P.BlobName = '' then
    raise Exception.Create('"blob_name" is required for get_blob_properties');

  URL  := BuildBaseURL(P.AccountName) + '/' + P.Container + '/' + P.BlobName;
  URL  := AppendSas(URL, P.SasToken);

  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Get(URL);

    HeadersObj := TJSONObject.Create;
    for i := 0 to Length(Resp.Headers) - 1 do
    begin
      HName  := Resp.Headers[i].Name;
      HValue := Resp.Headers[i].Value;
      HeadersObj.AddPair(HName, HValue);
    end;

    Result := TJSONObject.Create;
    Result.AddPair('ok',         TJSONTrue.Create);
    Result.AddPair('status',     TJSONNumber.Create(Resp.StatusCode));
    Result.AddPair('container',  P.Container);
    Result.AddPair('blob',       P.BlobName);
    Result.AddPair('headers',    HeadersObj);
  finally
    HTTP.Free;
  end;
end;

// -- Main execution -----------------------------------------------------------

function TAzureBlobTool.ExecuteWithParams(const AParams: TAzureBlobParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    if AParams.AccountName = '' then
      raise Exception.Create('"account_name" is required');
    if AParams.SasToken = '' then
      raise Exception.Create('"sas_token" is required');

    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then
      raise Exception.Create('"operation" is required');

    if      Op = 'list_containers'    then R := DoListContainers(AParams)
    else if Op = 'list_blobs'         then R := DoListBlobs(AParams)
    else if Op = 'get_blob'           then R := DoGetBlob(AParams)
    else if Op = 'put_blob'           then R := DoPutBlob(AParams)
    else if Op = 'delete_blob'        then R := DoDeleteBlob(AParams)
    else if Op = 'create_container'   then R := DoCreateContainer(AParams)
    else if Op = 'delete_container'   then R := DoDeleteContainer(AParams)
    else if Op = 'get_blob_properties' then R := DoGetBlobProperties(AParams)
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

constructor TAzureBlobTool.Create;
begin
  inherited;
  FName        := 'mcp-azure-blob';
  FDescription :=
    'Azure Blob Storage REST API client using SAS token authentication. ' +
    'Operations: ' +
    'list_containers (list all containers; params: account_name, sas_token), ' +
    'list_blobs (list blobs in a container; params: account_name, sas_token, container), ' +
    'get_blob (download blob content; params: account_name, sas_token, container, blob_name), ' +
    'put_blob (upload blob content; params: account_name, sas_token, container, blob_name, content, content_type?), ' +
    'delete_blob (delete a blob; params: account_name, sas_token, container, blob_name), ' +
    'create_container (create a container; params: account_name, sas_token, container), ' +
    'delete_container (delete a container; params: account_name, sas_token, container), ' +
    'get_blob_properties (get blob headers/metadata; params: account_name, sas_token, container, blob_name). ' +
    'sas_token: SAS query string without leading ? (e.g. sv=2021-06-08&ss=b&srt=co&sp=rwdlacx&se=...&sig=...).';
end;

// -- Registration -------------------------------------------------------------

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-azure-blob',
    function: IAiMCPTool
    begin
      Result := TAzureBlobTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-azure-blob');
end;

end.
