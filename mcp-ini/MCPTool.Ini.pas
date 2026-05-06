// Nombre: Gustavo Enríquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit MCPTool.Ini;

{
  MCPTool.Ini  ·  mcp-ini

  Read and write INI configuration files using System.IniFiles.

  Operations:
    read            - read a key value (returns default if not found)
    write           - write a key value
    list_sections   - list all sections
    list_keys       - list all keys in a section
    read_section    - read all key=value pairs in a section as a JSON object
    delete_key      - delete a specific key
    delete_section  - delete an entire section
    exists          - check if a section or key exists
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.IniFiles;

type

  TIniParams = class
  private
    FOperation:    string;
    FFilePath:     string;
    FSection:      string;
    FKey:          string;
    FValue:        string;
    FDefaultValue: string;
  public
    [AiMCPSchemaDescription('Operation: read, write, list_sections, list_keys, read_section, delete_key, delete_section, exists')]
    property Operation:    string read FOperation    write FOperation;

    [AiMCPSchemaDescription('Path to the INI file')]
    property FilePath:     string read FFilePath     write FFilePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Section name')]
    property Section:      string read FSection      write FSection;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Key name (for read, write, delete_key, exists)')]
    property Key:          string read FKey          write FKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Value to write (for write)')]
    property Value:        string read FValue        write FValue;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Default value returned when key is not found (for read)')]
    property DefaultValue: string read FDefaultValue write FDefaultValue;
  end;

  TIniTool = class(TAiMCPToolBase<TIniParams>)
  private
    function DoRead(const P: TIniParams): TJSONObject;
    function DoWrite(const P: TIniParams): TJSONObject;
    function DoListSections(const P: TIniParams): TJSONObject;
    function DoListKeys(const P: TIniParams): TJSONObject;
    function DoReadSection(const P: TIniParams): TJSONObject;
    function DoDeleteKey(const P: TIniParams): TJSONObject;
    function DoDeleteSection(const P: TIniParams): TJSONObject;
    function DoExists(const P: TIniParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TIniParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ TIniTool }

function TIniTool.DoRead(const P: TIniParams): TJSONObject;
var
  Ini: TIniFile;
  Val: string;
begin
  if P.Section = '' then raise Exception.Create('"section" required for read');
  if P.Key     = '' then raise Exception.Create('"key" required for read');
  if P.FilePath = '' then raise Exception.Create('"filepath" required');

  Ini := TIniFile.Create(P.FilePath);
  try
    Val := Ini.ReadString(P.Section, P.Key, P.DefaultValue);
  finally
    Ini.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('filepath', P.FilePath);
  Result.AddPair('section',  P.Section);
  Result.AddPair('key',      P.Key);
  Result.AddPair('value',    Val);
  Result.AddPair('found',    TJSONBool.Create(Val <> P.DefaultValue));
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function TIniTool.DoWrite(const P: TIniParams): TJSONObject;
var
  Ini: TIniFile;
begin
  if P.Section  = '' then raise Exception.Create('"section" required for write');
  if P.Key      = '' then raise Exception.Create('"key" required for write');
  if P.FilePath = '' then raise Exception.Create('"filepath" required');

  Ini := TIniFile.Create(P.FilePath);
  try
    Ini.WriteString(P.Section, P.Key, P.Value);
  finally
    Ini.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('filepath', P.FilePath);
  Result.AddPair('section',  P.Section);
  Result.AddPair('key',      P.Key);
  Result.AddPair('value',    P.Value);
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function TIniTool.DoListSections(const P: TIniParams): TJSONObject;
var
  Ini:      TIniFile;
  Sections: TStringList;
  Arr:      TJSONArray;
  S:        string;
begin
  if P.FilePath = '' then raise Exception.Create('"filepath" required');

  Ini      := TIniFile.Create(P.FilePath);
  Sections := TStringList.Create;
  try
    Ini.ReadSections(Sections);
    Arr := TJSONArray.Create;
    for S in Sections do
      Arr.Add(S);
  finally
    Sections.Free;
    Ini.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('filepath', P.FilePath);
  Result.AddPair('sections', Arr);
  Result.AddPair('count',    TJSONNumber.Create(Arr.Count));
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function TIniTool.DoListKeys(const P: TIniParams): TJSONObject;
var
  Ini:  TIniFile;
  Keys: TStringList;
  Arr:  TJSONArray;
  K:    string;
begin
  if P.FilePath = '' then raise Exception.Create('"filepath" required');
  if P.Section  = '' then raise Exception.Create('"section" required for list_keys');

  Ini  := TIniFile.Create(P.FilePath);
  Keys := TStringList.Create;
  try
    Ini.ReadSection(P.Section, Keys);
    Arr := TJSONArray.Create;
    for K in Keys do
      Arr.Add(K);
  finally
    Keys.Free;
    Ini.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('filepath', P.FilePath);
  Result.AddPair('section',  P.Section);
  Result.AddPair('keys',     Arr);
  Result.AddPair('count',    TJSONNumber.Create(Arr.Count));
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function TIniTool.DoReadSection(const P: TIniParams): TJSONObject;
var
  Ini:    TIniFile;
  Values: TStringList;
  Obj:    TJSONObject;
  i:      Integer;
  EqPos:  Integer;
  K, V:   string;
begin
  if P.FilePath = '' then raise Exception.Create('"filepath" required');
  if P.Section  = '' then raise Exception.Create('"section" required for read_section');

  Ini    := TIniFile.Create(P.FilePath);
  Values := TStringList.Create;
  try
    Ini.ReadSectionValues(P.Section, Values);
    Obj := TJSONObject.Create;
    for i := 0 to Values.Count - 1 do
    begin
      EqPos := Pos('=', Values[i]);
      if EqPos > 0 then
      begin
        K := Copy(Values[i], 1, EqPos - 1);
        V := Copy(Values[i], EqPos + 1, MaxInt);
        Obj.AddPair(K, V);
      end;
    end;
  finally
    Values.Free;
    Ini.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('filepath', P.FilePath);
  Result.AddPair('section',  P.Section);
  Result.AddPair('values',   Obj);
  Result.AddPair('count',    TJSONNumber.Create(Obj.Count));
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function TIniTool.DoDeleteKey(const P: TIniParams): TJSONObject;
var
  Ini: TIniFile;
begin
  if P.FilePath = '' then raise Exception.Create('"filepath" required');
  if P.Section  = '' then raise Exception.Create('"section" required for delete_key');
  if P.Key      = '' then raise Exception.Create('"key" required for delete_key');

  Ini := TIniFile.Create(P.FilePath);
  try
    Ini.DeleteKey(P.Section, P.Key);
  finally
    Ini.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('filepath', P.FilePath);
  Result.AddPair('section',  P.Section);
  Result.AddPair('key',      P.Key);
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function TIniTool.DoDeleteSection(const P: TIniParams): TJSONObject;
var
  Ini: TIniFile;
begin
  if P.FilePath = '' then raise Exception.Create('"filepath" required');
  if P.Section  = '' then raise Exception.Create('"section" required for delete_section');

  Ini := TIniFile.Create(P.FilePath);
  try
    Ini.EraseSection(P.Section);
  finally
    Ini.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('filepath', P.FilePath);
  Result.AddPair('section',  P.Section);
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function TIniTool.DoExists(const P: TIniParams): TJSONObject;
var
  Ini:    TIniFile;
  Exists: Boolean;
begin
  if P.FilePath = '' then raise Exception.Create('"filepath" required');
  if P.Section  = '' then raise Exception.Create('"section" required for exists');

  Ini := TIniFile.Create(P.FilePath);
  try
    if P.Key <> '' then
      Exists := Ini.ValueExists(P.Section, P.Key)
    else
      Exists := Ini.SectionExists(P.Section);
  finally
    Ini.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('filepath', P.FilePath);
  Result.AddPair('section',  P.Section);
  if P.Key <> '' then
    Result.AddPair('key', P.Key);
  Result.AddPair('exists', TJSONBool.Create(Exists));
  Result.AddPair('ok',     TJSONTrue.Create);
end;

function TIniTool.ExecuteWithParams(const AParams: TIniParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'read'           then R := DoRead(AParams)
    else if Op = 'write'          then R := DoWrite(AParams)
    else if Op = 'list_sections'  then R := DoListSections(AParams)
    else if Op = 'list_keys'      then R := DoListKeys(AParams)
    else if Op = 'read_section'   then R := DoReadSection(AParams)
    else if Op = 'delete_key'     then R := DoDeleteKey(AParams)
    else if Op = 'delete_section' then R := DoDeleteSection(AParams)
    else if Op = 'exists'         then R := DoExists(AParams)
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

constructor TIniTool.Create;
begin
  inherited;
  FName        := 'mcp-ini';
  FDescription :=
    'Read and write INI configuration files. ' +
    'Operations: ' +
    'read (read a key; params: filepath, section, key, default_value), ' +
    'write (write a key; params: filepath, section, key, value), ' +
    'list_sections (list all sections; param: filepath), ' +
    'list_keys (list keys in section; params: filepath, section), ' +
    'read_section (read all key=value pairs; params: filepath, section), ' +
    'delete_key (delete a key; params: filepath, section, key), ' +
    'delete_section (delete a section; params: filepath, section), ' +
    'exists (check if section or key exists; params: filepath, section, key?).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-ini',
    function: IAiMCPTool
    begin
      Result := TIniTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-ini');
end;

end.
