unit MCPTool.Registry;

{
  MCPTool.Registry  ·  mcp-registry

  Windows Registry access using System.Win.Registry.

  Operations:
    read         - read a registry value (returns string, number or type info)
    write        - write a registry value
    list_keys    - list subkeys under a path
    list_values  - list value names under a path
    delete_value - delete a named value
    delete_key   - delete a key and all its contents
    exists       - check if a key or value exists
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Win.Registry,
  Winapi.Windows;

type

  TRegistryParams = class
  private
    FOperation: string;
    FRoot:      string;
    FPath:      string;
    FName:      string;
    FValue:     string;
    FValueType: string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: read, write, list_keys, list_values, delete_value, delete_key, exists')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Root hive: HKCU (default), HKLM, HKCR, HKU, HKCC')]
    property Root:      string read FRoot      write FRoot;

    [AiMCPSchemaDescription('Registry path, e.g. "Software\MyApp\Settings"')]
    property Path:      string read FPath      write FPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Value name (empty string = default value)')]
    property Name:      string read FName      write FName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Value to write (for write)')]
    property Value:     string read FValue     write FValue;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Value type for write: string (default), expandstr, dword, qword, multistr')]
    property ValueType: string read FValueType write FValueType;
  end;

  TRegistryTool = class(TAiMCPToolBase<TRegistryParams>)
  private
    function ResolveRoot(const Root: string): HKEY;
    function RootName(HKey: HKEY): string;
    function DoRead(const P: TRegistryParams): TJSONObject;
    function DoWrite(const P: TRegistryParams): TJSONObject;
    function DoListKeys(const P: TRegistryParams): TJSONObject;
    function DoListValues(const P: TRegistryParams): TJSONObject;
    function DoDeleteValue(const P: TRegistryParams): TJSONObject;
    function DoDeleteKey(const P: TRegistryParams): TJSONObject;
    function DoExists(const P: TRegistryParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TRegistryParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ TRegistryParams }

constructor TRegistryParams.Create;
begin
  inherited;
  FRoot      := 'HKCU';
  FValueType := 'string';
end;

{ TRegistryTool }

function TRegistryTool.ResolveRoot(const Root: string): HKEY;
var
  U: string;
begin
  U := UpperCase(Trim(Root));
  if (U = 'HKLM') or (U = 'HKEY_LOCAL_MACHINE')  then Result := HKEY_LOCAL_MACHINE
  else if (U = 'HKCR') or (U = 'HKEY_CLASSES_ROOT')   then Result := HKEY_CLASSES_ROOT
  else if (U = 'HKCC') or (U = 'HKEY_CURRENT_CONFIG') then Result := HKEY_CURRENT_CONFIG
  else if (U = 'HKU')  or (U = 'HKEY_USERS')          then Result := HKEY_USERS
  else Result := HKEY_CURRENT_USER; // HKCU default
end;

function TRegistryTool.RootName(HKey: HKEY): string;
begin
  case HKey of
    HKEY_LOCAL_MACHINE:  Result := 'HKLM';
    HKEY_CLASSES_ROOT:   Result := 'HKCR';
    HKEY_CURRENT_CONFIG: Result := 'HKCC';
    HKEY_USERS:          Result := 'HKU';
    else                 Result := 'HKCU';
  end;
end;

function TRegistryTool.DoRead(const P: TRegistryParams): TJSONObject;
var
  Reg:      TRegistry;
  RootKey:  HKEY;
  DataType: TRegDataType;
  StrVal:   string;
  IntVal:   Integer;
  Int64Val: Int64;
begin
  if P.Path = '' then raise Exception.Create('"path" required for read');

  RootKey := ResolveRoot(P.Root);
  Reg     := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := RootKey;
    if not Reg.OpenKeyReadOnly(P.Path) then
      raise Exception.CreateFmt('Cannot open key: %s\%s', [RootName(RootKey), P.Path]);

    if not Reg.ValueExists(P.Name) then
    begin
      Result := TJSONObject.Create;
      Result.AddPair('found', TJSONFalse.Create);
      Result.AddPair('path',  P.Path);
      Result.AddPair('name',  P.Name);
      Result.AddPair('ok',    TJSONTrue.Create);
      Exit;
    end;

    DataType := Reg.GetDataType(P.Name);

    Result := TJSONObject.Create;
    Result.AddPair('found', TJSONTrue.Create);
    Result.AddPair('root',  RootName(RootKey));
    Result.AddPair('path',  P.Path);
    Result.AddPair('name',  P.Name);

    case DataType of
      rdString, rdExpandString:
      begin
        StrVal := Reg.ReadString(P.Name);
        Result.AddPair('value',      StrVal);
        Result.AddPair('value_type', 'string');
      end;
      rdInteger:
      begin
        IntVal := Reg.ReadInteger(P.Name);
        Result.AddPair('value',      TJSONNumber.Create(IntVal));
        Result.AddPair('value_type', 'dword');
      end;
      rdInt64:
      begin
        Int64Val := 0;
        Reg.ReadBinaryData(P.Name, Int64Val, SizeOf(Int64Val));
        Result.AddPair('value',      TJSONNumber.Create(Int64Val));
        Result.AddPair('value_type', 'qword');
      end;
      else
      begin
        Result.AddPair('value',      '<binary>');
        Result.AddPair('value_type', 'binary');
      end;
    end;

    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Reg.Free;
  end;
end;

function TRegistryTool.DoWrite(const P: TRegistryParams): TJSONObject;
var
  Reg:     TRegistry;
  RootKey: HKEY;
  VType:   string;
begin
  if P.Path = '' then raise Exception.Create('"path" required for write');

  RootKey := ResolveRoot(P.Root);
  VType   := LowerCase(Trim(P.ValueType));
  if VType = '' then VType := 'string';

  Reg := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := RootKey;
    if not Reg.OpenKey(P.Path, True) then
      raise Exception.CreateFmt('Cannot open/create key: %s\%s', [RootName(RootKey), P.Path]);

    if VType = 'dword' then
      Reg.WriteInteger(P.Name, StrToIntDef(P.Value, 0))
    else if VType = 'qword' then
    begin
      var Q: Int64 := StrToInt64Def(P.Value, 0);
      Reg.WriteBinaryData(P.Name, Q, SizeOf(Q));
    end
    else if VType = 'expandstr' then
      Reg.WriteExpandString(P.Name, P.Value)
    else if VType = 'multistr' then
    begin
      var Parts := P.Value.Split(['|']);
      Reg.WriteMultiString(P.Name, Parts);
    end
    else
      Reg.WriteString(P.Name, P.Value);

  finally
    Reg.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('root',       RootName(RootKey));
  Result.AddPair('path',       P.Path);
  Result.AddPair('name',       P.Name);
  Result.AddPair('value',      P.Value);
  Result.AddPair('value_type', VType);
  Result.AddPair('ok',         TJSONTrue.Create);
end;

function TRegistryTool.DoListKeys(const P: TRegistryParams): TJSONObject;
var
  Reg:     TRegistry;
  RootKey: HKEY;
  Keys:    TStringList;
  Arr:     TJSONArray;
  K:       string;
begin
  if P.Path = '' then raise Exception.Create('"path" required for list_keys');

  RootKey := ResolveRoot(P.Root);
  Reg     := TRegistry.Create(KEY_READ);
  Keys    := TStringList.Create;
  try
    Reg.RootKey := RootKey;
    if not Reg.OpenKeyReadOnly(P.Path) then
      raise Exception.CreateFmt('Cannot open key: %s\%s', [RootName(RootKey), P.Path]);
    Reg.GetKeyNames(Keys);
    Arr := TJSONArray.Create;
    for K in Keys do
      Arr.Add(K);
  finally
    Keys.Free;
    Reg.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('root',  RootName(RootKey));
  Result.AddPair('path',  P.Path);
  Result.AddPair('keys',  Arr);
  Result.AddPair('count', TJSONNumber.Create(Arr.Count));
  Result.AddPair('ok',    TJSONTrue.Create);
end;

function TRegistryTool.DoListValues(const P: TRegistryParams): TJSONObject;
var
  Reg:     TRegistry;
  RootKey: HKEY;
  Names:   TStringList;
  Arr:     TJSONArray;
  N:       string;
begin
  if P.Path = '' then raise Exception.Create('"path" required for list_values');

  RootKey := ResolveRoot(P.Root);
  Reg     := TRegistry.Create(KEY_READ);
  Names   := TStringList.Create;
  try
    Reg.RootKey := RootKey;
    if not Reg.OpenKeyReadOnly(P.Path) then
      raise Exception.CreateFmt('Cannot open key: %s\%s', [RootName(RootKey), P.Path]);
    Reg.GetValueNames(Names);
    Arr := TJSONArray.Create;
    for N in Names do
      Arr.Add(N);
  finally
    Names.Free;
    Reg.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('root',   RootName(RootKey));
  Result.AddPair('path',   P.Path);
  Result.AddPair('values', Arr);
  Result.AddPair('count',  TJSONNumber.Create(Arr.Count));
  Result.AddPair('ok',     TJSONTrue.Create);
end;

function TRegistryTool.DoDeleteValue(const P: TRegistryParams): TJSONObject;
var
  Reg:     TRegistry;
  RootKey: HKEY;
begin
  if P.Path = '' then raise Exception.Create('"path" required for delete_value');
  if P.Name = '' then raise Exception.Create('"name" required for delete_value');

  RootKey := ResolveRoot(P.Root);
  Reg     := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := RootKey;
    if not Reg.OpenKey(P.Path, False) then
      raise Exception.CreateFmt('Cannot open key: %s\%s', [RootName(RootKey), P.Path]);
    Reg.DeleteValue(P.Name);
  finally
    Reg.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('root', RootName(RootKey));
  Result.AddPair('path', P.Path);
  Result.AddPair('name', P.Name);
  Result.AddPair('ok',   TJSONTrue.Create);
end;

function TRegistryTool.DoDeleteKey(const P: TRegistryParams): TJSONObject;
var
  Reg:     TRegistry;
  RootKey: HKEY;
begin
  if P.Path = '' then raise Exception.Create('"path" required for delete_key');

  RootKey := ResolveRoot(P.Root);
  Reg     := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := RootKey;
    Reg.DeleteKey(P.Path);
  finally
    Reg.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('root', RootName(RootKey));
  Result.AddPair('path', P.Path);
  Result.AddPair('ok',   TJSONTrue.Create);
end;

function TRegistryTool.DoExists(const P: TRegistryParams): TJSONObject;
var
  Reg:     TRegistry;
  RootKey: HKEY;
  Exists:  Boolean;
begin
  if P.Path = '' then raise Exception.Create('"path" required for exists');

  RootKey := ResolveRoot(P.Root);
  Reg     := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := RootKey;
    if P.Name <> '' then
    begin
      if Reg.OpenKeyReadOnly(P.Path) then
        Exists := Reg.ValueExists(P.Name)
      else
        Exists := False;
    end
    else
      Exists := Reg.KeyExists(P.Path);
  finally
    Reg.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('root',   RootName(RootKey));
  Result.AddPair('path',   P.Path);
  if P.Name <> '' then
    Result.AddPair('name', P.Name);
  Result.AddPair('exists', TJSONBool.Create(Exists));
  Result.AddPair('ok',     TJSONTrue.Create);
end;

function TRegistryTool.ExecuteWithParams(const AParams: TRegistryParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'read'         then R := DoRead(AParams)
    else if Op = 'write'        then R := DoWrite(AParams)
    else if Op = 'list_keys'    then R := DoListKeys(AParams)
    else if Op = 'list_values'  then R := DoListValues(AParams)
    else if Op = 'delete_value' then R := DoDeleteValue(AParams)
    else if Op = 'delete_key'   then R := DoDeleteKey(AParams)
    else if Op = 'exists'       then R := DoExists(AParams)
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

constructor TRegistryTool.Create;
begin
  inherited;
  FName        := 'mcp-registry';
  FDescription :=
    'Windows Registry access. ' +
    'Root hives: HKCU (default), HKLM, HKCR, HKU, HKCC. ' +
    'Operations: ' +
    'read (read a value; params: root, path, name), ' +
    'write (write a value; params: root, path, name, value, valuetype), ' +
    'list_keys (list subkeys; params: root, path), ' +
    'list_values (list value names; params: root, path), ' +
    'delete_value (delete a value; params: root, path, name), ' +
    'delete_key (delete a key; params: root, path), ' +
    'exists (check key or value; params: root, path, name?). ' +
    'Value types for write: string (default), expandstr, dword, qword, multistr (pipe-separated).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-registry',
    function: IAiMCPTool
    begin
      Result := TRegistryTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-registry] ready');
end;

end.
