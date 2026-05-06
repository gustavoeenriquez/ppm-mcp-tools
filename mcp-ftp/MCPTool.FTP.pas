unit MCPTool.FTP;

{
  MCPTool.FTP  ·  mcp-ftp

  FTP client operations using Indy TIdFTP.

  Operations:
    list   - list files and directories in a remote path
    get    - download a file from the server
    put    - upload a file to the server
    delete - delete a remote file
    mkdir  - create a remote directory
    rename - rename/move a remote file
    exists - check if a remote file or directory exists
    info   - get size and date of a remote file
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  IdFTP,
  IdFTPList,
  IdTCPClient,
  IdBaseComponent,
  IdComponent,
  IdTCPConnection,
  IdExplicitTLSClientServerBase,
  IdFTPCommon;

type

  TFTPParams = class
  private
    FOperation:  string;
    FHost:       string;
    FPort:       Integer;
    FUsername:   string;
    FPassword:   string;
    FRemotePath: string;
    FLocalPath:  string;
    FNewName:    string;
    FPassive:    Boolean;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list, get, put, delete, mkdir, rename, exists, info')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPSchemaDescription('FTP server hostname or IP')]
    property Host:       string  read FHost       write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('FTP port (default: 21)')]
    property Port:       Integer read FPort       write FPort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Username (default: anonymous)')]
    property Username:   string  read FUsername   write FUsername;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Password')]
    property Password:   string  read FPassword   write FPassword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Remote file or directory path')]
    property RemotePath: string  read FRemotePath write FRemotePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Local file path (for get/put)')]
    property LocalPath:  string  read FLocalPath  write FLocalPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('New remote name/path (for rename)')]
    property NewName:    string  read FNewName    write FNewName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Use passive mode (default: true)')]
    property Passive:    Boolean read FPassive    write FPassive;
  end;

  TFTPTool = class(TAiMCPToolBase<TFTPParams>)
  private
    function CreateFTP(const P: TFTPParams): TIdFTP;
    function DoList(const P: TFTPParams): TJSONObject;
    function DoGet(const P: TFTPParams): TJSONObject;
    function DoPut(const P: TFTPParams): TJSONObject;
    function DoDelete(const P: TFTPParams): TJSONObject;
    function DoMkDir(const P: TFTPParams): TJSONObject;
    function DoRename(const P: TFTPParams): TJSONObject;
    function DoExists(const P: TFTPParams): TJSONObject;
    function DoInfo(const P: TFTPParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TFTPParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ TFTPParams }

constructor TFTPParams.Create;
begin
  inherited;
  FPort     := 21;
  FUsername := 'anonymous';
  FPassive  := True;
end;

{ TFTPTool }

function TFTPTool.CreateFTP(const P: TFTPParams): TIdFTP;
begin
  if P.Host = '' then raise Exception.Create('"host" is required');

  Result          := TIdFTP.Create(nil);
  Result.Host     := P.Host;
  Result.Port     := P.Port;
  Result.Username := P.Username;
  Result.Password := P.Password;
  Result.Passive  := P.Passive;
  Result.Connect;
  Result.Login;
end;

function TFTPTool.DoList(const P: TFTPParams): TJSONObject;
var
  FTP:  TIdFTP;
  Arr:  TJSONArray;
  Item: TIdFTPListItem;
  Obj:  TJSONObject;
  Path: string;
  i:    Integer;
begin
  Path := P.RemotePath;

  FTP := CreateFTP(P);
  try
    FTP.List(nil, Path);
    Arr := TJSONArray.Create;
    for i := 0 to FTP.DirectoryListing.Count - 1 do
    begin
      Item := FTP.DirectoryListing[i];
      Obj  := TJSONObject.Create;
      Obj.AddPair('name',      Item.FileName);
      Obj.AddPair('size',      TJSONNumber.Create(Item.Size));
      Obj.AddPair('modified',  FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.ModifiedDate));
      case Item.ItemType of
        ditDirectory:   Obj.AddPair('type', 'directory');
        ditSymbolicLink: Obj.AddPair('type', 'symlink');
        else             Obj.AddPair('type', 'file');
      end;
      Arr.AddElement(Obj);
    end;
  finally
    FTP.Disconnect;
    FTP.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host',  P.Host);
  Result.AddPair('path',  Path);
  Result.AddPair('items', Arr);
  Result.AddPair('count', TJSONNumber.Create(Arr.Count));
  Result.AddPair('ok',    TJSONTrue.Create);
end;

function TFTPTool.DoGet(const P: TFTPParams): TJSONObject;
var
  FTP: TIdFTP;
begin
  if P.RemotePath = '' then raise Exception.Create('"remote_path" required for get');
  if P.LocalPath  = '' then raise Exception.Create('"local_path" required for get');

  FTP := CreateFTP(P);
  try
    FTP.Get(P.RemotePath, P.LocalPath, True);
  finally
    FTP.Disconnect;
    FTP.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host',        P.Host);
  Result.AddPair('remote_path', P.RemotePath);
  Result.AddPair('local_path',  P.LocalPath);
  Result.AddPair('ok',          TJSONTrue.Create);
end;

function TFTPTool.DoPut(const P: TFTPParams): TJSONObject;
var
  FTP: TIdFTP;
begin
  if P.LocalPath  = '' then raise Exception.Create('"local_path" required for put');
  if P.RemotePath = '' then raise Exception.Create('"remote_path" required for put');
  if not FileExists(P.LocalPath) then
    raise Exception.CreateFmt('Local file not found: %s', [P.LocalPath]);

  FTP := CreateFTP(P);
  try
    FTP.Put(P.LocalPath, P.RemotePath);
  finally
    FTP.Disconnect;
    FTP.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host',        P.Host);
  Result.AddPair('local_path',  P.LocalPath);
  Result.AddPair('remote_path', P.RemotePath);
  Result.AddPair('ok',          TJSONTrue.Create);
end;

function TFTPTool.DoDelete(const P: TFTPParams): TJSONObject;
var
  FTP: TIdFTP;
begin
  if P.RemotePath = '' then raise Exception.Create('"remote_path" required for delete');

  FTP := CreateFTP(P);
  try
    FTP.Delete(P.RemotePath);
  finally
    FTP.Disconnect;
    FTP.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host',        P.Host);
  Result.AddPair('remote_path', P.RemotePath);
  Result.AddPair('ok',          TJSONTrue.Create);
end;

function TFTPTool.DoMkDir(const P: TFTPParams): TJSONObject;
var
  FTP: TIdFTP;
begin
  if P.RemotePath = '' then raise Exception.Create('"remote_path" required for mkdir');

  FTP := CreateFTP(P);
  try
    FTP.MakeDir(P.RemotePath);
  finally
    FTP.Disconnect;
    FTP.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host',        P.Host);
  Result.AddPair('remote_path', P.RemotePath);
  Result.AddPair('ok',          TJSONTrue.Create);
end;

function TFTPTool.DoRename(const P: TFTPParams): TJSONObject;
var
  FTP: TIdFTP;
begin
  if P.RemotePath = '' then raise Exception.Create('"remote_path" required for rename');
  if P.NewName    = '' then raise Exception.Create('"new_name" required for rename');

  FTP := CreateFTP(P);
  try
    FTP.Rename(P.RemotePath, P.NewName);
  finally
    FTP.Disconnect;
    FTP.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host',        P.Host);
  Result.AddPair('remote_path', P.RemotePath);
  Result.AddPair('new_name',    P.NewName);
  Result.AddPair('ok',          TJSONTrue.Create);
end;

function TFTPTool.DoExists(const P: TFTPParams): TJSONObject;
var
  FTP:    TIdFTP;
  Exists: Boolean;
  Size:   Int64;
begin
  if P.RemotePath = '' then raise Exception.Create('"remote_path" required for exists');

  FTP := CreateFTP(P);
  try
    try
      Size   := FTP.Size(P.RemotePath);
      Exists := Size >= 0;
    except
      Exists := False;
    end;
  finally
    FTP.Disconnect;
    FTP.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host',        P.Host);
  Result.AddPair('remote_path', P.RemotePath);
  Result.AddPair('exists',      TJSONBool.Create(Exists));
  Result.AddPair('ok',          TJSONTrue.Create);
end;

function TFTPTool.DoInfo(const P: TFTPParams): TJSONObject;
var
  FTP:     TIdFTP;
  Size:    Int64;
  ModDate: TDateTime;
begin
  if P.RemotePath = '' then raise Exception.Create('"remote_path" required for info');

  FTP := CreateFTP(P);
  try
    Size    := FTP.Size(P.RemotePath);
    ModDate := 0;
    try
      ModDate := FTP.FileDate(P.RemotePath);
    except
    end;
  finally
    FTP.Disconnect;
    FTP.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host',        P.Host);
  Result.AddPair('remote_path', P.RemotePath);
  Result.AddPair('size',        TJSONNumber.Create(Size));
  if ModDate > 0 then
    Result.AddPair('modified', FormatDateTime('yyyy-mm-dd hh:nn:ss', ModDate));
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TFTPTool.ExecuteWithParams(const AParams: TFTPParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list'   then R := DoList(AParams)
    else if Op = 'get'    then R := DoGet(AParams)
    else if Op = 'put'    then R := DoPut(AParams)
    else if Op = 'delete' then R := DoDelete(AParams)
    else if Op = 'mkdir'  then R := DoMkDir(AParams)
    else if Op = 'rename' then R := DoRename(AParams)
    else if Op = 'exists' then R := DoExists(AParams)
    else if Op = 'info'   then R := DoInfo(AParams)
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

constructor TFTPTool.Create;
begin
  inherited;
  FName        := 'mcp-ftp';
  FDescription :=
    'FTP client file operations. ' +
    'Operations: ' +
    'list (list remote directory; params: host, remote_path?), ' +
    'get (download file; params: host, remote_path, local_path), ' +
    'put (upload file; params: host, local_path, remote_path), ' +
    'delete (delete remote file; params: host, remote_path), ' +
    'mkdir (create remote directory; params: host, remote_path), ' +
    'rename (rename/move remote file; params: host, remote_path, new_name), ' +
    'exists (check if file exists; params: host, remote_path), ' +
    'info (file size and date; params: host, remote_path). ' +
    'Optional params: port (21), username (anonymous), password, passive (true).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-ftp',
    function: IAiMCPTool
    begin
      Result := TFTPTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-ftp] registered');
end;

end.
