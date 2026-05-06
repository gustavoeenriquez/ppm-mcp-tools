unit MCPTool.Hash;

{
  MCPTool.Hash  ·  mcp-hash

  Cryptographic and checksum hashing using System.Hash.

  Operations:
    hash      - hash a string (algos: md5, sha1, sha256, sha384, sha512, crc32)
    file_hash - hash a file (same algos)
    compare   - compare hashes of two strings, two files, or a string and file
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Hash,
  System.NetEncoding;

type

  THashParams = class
  private
    FOperation: string;
    FAlgo:      string;
    FValue:     string;
    FValue2:    string;
    FFilePath:  string;
    FFilePath2: string;
    FEncoding:  string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: hash, file_hash, compare')]
    property Operation: string  read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Algorithm: md5, sha1, sha256, sha384, sha512, crc32 (default: sha256)')]
    property Algo:      string  read FAlgo      write FAlgo;

    [AiMCPOptional]
    [AiMCPSchemaDescription('String to hash (for hash / compare)')]
    property Value:     string  read FValue     write FValue;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Second string to compare (for compare)')]
    property Value2:    string  read FValue2    write FValue2;

    [AiMCPOptional]
    [AiMCPSchemaDescription('File path to hash (for file_hash / compare)')]
    property FilePath:  string  read FFilePath  write FFilePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Second file path (for compare with two files)')]
    property FilePath2: string  read FFilePath2 write FFilePath2;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Output encoding: hex (default), base64')]
    property Encoding:  string  read FEncoding  write FEncoding;
  end;

  THashTool = class(TAiMCPToolBase<THashParams>)
  private
    function ResolveAlgo(const Algo: string): string;
    function CRC32Hex(const Data: TBytes): string;
    function HashBytes(const Data: TBytes; const Algo, Enc: string): string;
    function HashString(const Value, Algo, Enc: string): string;
    function HashFile(const AFilePath, Algo, Enc: string): string;
    function DoHash(const P: THashParams): TJSONObject;
    function DoFileHash(const P: THashParams): TJSONObject;
    function DoCompare(const P: THashParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: THashParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ THashParams }

constructor THashParams.Create;
begin
  inherited;
  FAlgo     := 'sha256';
  FEncoding := 'hex';
end;

{ THashTool }

function THashTool.ResolveAlgo(const Algo: string): string;
begin
  Result := LowerCase(Trim(Algo));
  if Result = '' then Result := 'sha256';
end;

function THashTool.CRC32Hex(const Data: TBytes): string;
const
  Poly = $EDB88320;
var
  Table: array[0..255] of Cardinal;
  CRC:   Cardinal;
  i, j:  Integer;
  c:     Cardinal;
begin
  for i := 0 to 255 do
  begin
    c := i;
    for j := 0 to 7 do
      if (c and 1) <> 0 then c := Poly xor (c shr 1)
      else c := c shr 1;
    Table[i] := c;
  end;
  CRC := $FFFFFFFF;
  for i := 0 to High(Data) do
    CRC := Table[(CRC xor Data[i]) and $FF] xor (CRC shr 8);
  Result := LowerCase(IntToHex(CRC xor $FFFFFFFF, 8));
end;

function THashTool.HashBytes(const Data: TBytes; const Algo, Enc: string): string;
var
  LAlgo:  string;
  Bytes:  TBytes;
  HMD5:   THashMD5;
  HSHA1:  THashSHA1;
  HSHA2:  THashSHA2;
  SB:     TStringBuilder;
  B:      Byte;
begin
  LAlgo := ResolveAlgo(Algo);

  if LAlgo = 'crc32' then
  begin
    Result := CRC32Hex(Data);
    Exit;
  end;

  if LAlgo = 'md5' then
  begin
    HMD5 := THashMD5.Create;
    HMD5.Update(Data);
    Bytes := HMD5.HashAsBytes;
  end
  else if LAlgo = 'sha1' then
  begin
    HSHA1 := THashSHA1.Create;
    HSHA1.Update(Data);
    Bytes := HSHA1.HashAsBytes;
  end
  else if LAlgo = 'sha384' then
  begin
    HSHA2 := THashSHA2.Create(THashSHA2.TSHA2Version.SHA384);
    HSHA2.Update(Data);
    Bytes := HSHA2.HashAsBytes;
  end
  else if LAlgo = 'sha512' then
  begin
    HSHA2 := THashSHA2.Create(THashSHA2.TSHA2Version.SHA512);
    HSHA2.Update(Data);
    Bytes := HSHA2.HashAsBytes;
  end
  else  // sha256 default
  begin
    HSHA2 := THashSHA2.Create;
    HSHA2.Update(Data);
    Bytes := HSHA2.HashAsBytes;
  end;

  if SameText(Enc, 'base64') then
    Result := TBase64Encoding.Base64.EncodeBytesToString(Bytes)
  else
  begin
    SB := TStringBuilder.Create;
    try
      for B in Bytes do
        SB.Append(LowerCase(IntToHex(B, 2)));
      Result := SB.ToString;
    finally
      SB.Free;
    end;
  end;
end;

function THashTool.HashString(const Value, Algo, Enc: string): string;
var
  Data: TBytes;
begin
  Data   := TEncoding.UTF8.GetBytes(Value);
  Result := HashBytes(Data, Algo, Enc);
end;

function THashTool.HashFile(const AFilePath, Algo, Enc: string): string;
var
  FS:   TFileStream;
  Data: TBytes;
begin
  FS := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Data, FS.Size);
    if FS.Size > 0 then
      FS.ReadBuffer(Data[0], FS.Size);
  finally
    FS.Free;
  end;
  Result := HashBytes(Data, Algo, Enc);
end;

function THashTool.DoHash(const P: THashParams): TJSONObject;
var
  Algo, Enc, Hash: string;
begin
  if P.Value = '' then
    raise Exception.Create('"value" required for hash');
  Algo := ResolveAlgo(P.Algo);
  Enc  := LowerCase(Trim(P.Encoding));
  if Enc = '' then Enc := 'hex';
  Hash := HashString(P.Value, Algo, Enc);
  Result := TJSONObject.Create;
  Result.AddPair('algo',     Algo);
  Result.AddPair('encoding', Enc);
  Result.AddPair('hash',     Hash);
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function THashTool.DoFileHash(const P: THashParams): TJSONObject;
var
  Algo, Enc, Hash: string;
  FS:              TFileStream;
  Size:            Int64;
begin
  if P.FilePath = '' then
    raise Exception.Create('"filepath" required for file_hash');
  if not FileExists(P.FilePath) then
    raise Exception.CreateFmt('File not found: %s', [P.FilePath]);

  Algo := ResolveAlgo(P.Algo);
  Enc  := LowerCase(Trim(P.Encoding));
  if Enc = '' then Enc := 'hex';

  FS := TFileStream.Create(P.FilePath, fmOpenRead or fmShareDenyNone);
  try
    Size := FS.Size;
  finally
    FS.Free;
  end;
  Hash := HashFile(P.FilePath, Algo, Enc);

  Result := TJSONObject.Create;
  Result.AddPair('filepath', P.FilePath);
  Result.AddPair('algo',     Algo);
  Result.AddPair('encoding', Enc);
  Result.AddPair('hash',     Hash);
  Result.AddPair('size',     TJSONNumber.Create(Size));
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function THashTool.DoCompare(const P: THashParams): TJSONObject;
var
  Algo, Enc, Hash1, Hash2: string;
  Match:                   Boolean;
begin
  Algo := ResolveAlgo(P.Algo);
  Enc  := LowerCase(Trim(P.Encoding));
  if Enc = '' then Enc := 'hex';

  if (P.Value <> '') and (P.Value2 <> '') then
  begin
    Hash1 := HashString(P.Value,  Algo, Enc);
    Hash2 := HashString(P.Value2, Algo, Enc);
  end
  else if (P.FilePath <> '') and (P.FilePath2 <> '') then
  begin
    Hash1 := HashFile(P.FilePath,  Algo, Enc);
    Hash2 := HashFile(P.FilePath2, Algo, Enc);
  end
  else if (P.Value <> '') and (P.FilePath <> '') then
  begin
    Hash1 := HashString(P.Value, Algo, Enc);
    Hash2 := HashFile(P.FilePath, Algo, Enc);
  end
  else
    raise Exception.Create(
      'compare requires: (value + value2), (filepath + filepath2), or (value + filepath)');

  Match := SameText(Hash1, Hash2);

  Result := TJSONObject.Create;
  Result.AddPair('algo',  Algo);
  Result.AddPair('hash1', Hash1);
  Result.AddPair('hash2', Hash2);
  Result.AddPair('match', TJSONBool.Create(Match));
  Result.AddPair('ok',    TJSONTrue.Create);
end;

function THashTool.ExecuteWithParams(const AParams: THashParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'hash'      then R := DoHash(AParams)
    else if Op = 'file_hash' then R := DoFileHash(AParams)
    else if Op = 'compare'   then R := DoCompare(AParams)
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

constructor THashTool.Create;
begin
  inherited;
  FName        := 'mcp-hash';
  FDescription :=
    'Cryptographic and checksum hashing. ' +
    'Operations: ' +
    'hash (hash a string; params: value, algo, encoding), ' +
    'file_hash (hash a file; params: filepath, algo, encoding), ' +
    'compare (compare hashes; params: value+value2, filepath+filepath2, or value+filepath). ' +
    'Algos: md5, sha1, sha256 (default), sha384, sha512, crc32. ' +
    'Encoding: hex (default), base64.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-hash',
    function: IAiMCPTool
    begin
      Result := THashTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-hash] ready');
end;

end.
