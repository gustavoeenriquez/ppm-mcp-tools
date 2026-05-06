unit MCPTool.Redis;

{
  MCPTool.Redis
  MCP tool: mcp-redis

  Redis client using Indy TIdTCPClient with RESP protocol.
  Credentials via params or env vars:
    REDIS_HOST, REDIS_PORT, REDIS_PASSWORD, REDIS_DB

  Operations:
    ping    - check connectivity
    get     - get string value
    set     - set string value (with optional TTL in seconds)
    del     - delete one or more keys (comma-separated)
    exists  - check if key exists
    keys    - list keys matching pattern
    incr    - increment integer value
    expire  - set TTL on existing key
    ttl     - get remaining TTL of key
    hget    - get hash field value
    hset    - set hash field value
    hgetall - get all hash fields and values
    lpush   - prepend value to list
    lrange  - get list elements by range
    info    - server info (server section)
    dbsize  - number of keys in current db
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  IdTCPClient,
  IdGlobal;

type

  TRedisParams = class
  private
    FOperation: string;
    FHost:      string;
    FPort:      Integer;
    FPassword:  string;
    FDb:        Integer;
    FKey:       string;
    FValue:     string;
    FField:     string;
    FTtl:       Integer;
    FPattern:   string;
    FStart:     Integer;
    FStop:      Integer;
  public
    [AiMCPSchemaDescription('Operation: ping, get, set, del, exists, keys, incr, expire, ttl, hget, hset, hgetall, lpush, lrange, info, dbsize')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Redis host (default: localhost or REDIS_HOST env var)')]
    property Host: string read FHost write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Redis port (default: 6379 or REDIS_PORT env var)')]
    property Port: Integer read FPort write FPort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Redis password (or REDIS_PASSWORD env var)')]
    property Password: string read FPassword write FPassword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Redis database number (default: 0 or REDIS_DB env var)')]
    property Db: Integer read FDb write FDb;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Key name (required for get, set, del, exists, incr, expire, ttl, hget, hset, hgetall, lpush, lrange)')]
    property Key: string read FKey write FKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('String value (for set, hset, lpush)')]
    property Value: string read FValue write FValue;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Hash field name (for hget, hset)')]
    property Field: string read FField write FField;

    [AiMCPOptional]
    [AiMCPSchemaDescription('TTL in seconds (for set with expiry or expire operation)')]
    property Ttl: Integer read FTtl write FTtl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Key pattern for keys operation (default: *)')]
    property Pattern: string read FPattern write FPattern;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Start index for lrange (default: 0)')]
    property Start: Integer read FStart write FStart;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Stop index for lrange (default: -1 = all)')]
    property Stop: Integer read FStop write FStop;
  end;

  TRedisTool = class(TAiMCPToolBase<TRedisParams>)
  private
    FClient: TIdTCPClient;
    procedure Connect(const AParams: TRedisParams);
    procedure Disconnect;
    function  SendCmd(const Args: array of string): string;
    function  ReadLine: string;
    function  ReadResponse: string;
    function  Env(const Key, Default: string): string;
    function  EnvInt(const Key: string; Default: Integer): Integer;
  protected
    function ExecuteWithParams(const AParams: TRedisParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
    destructor  Destroy; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── RESP protocol helpers ────────────────────────────────────────────────────

function TRedisTool.Env(const Key, Default: string): string;
begin
  Result := GetEnvironmentVariable(Key);
  if Result = '' then Result := Default;
end;

function TRedisTool.EnvInt(const Key: string; Default: Integer): Integer;
var S: string;
begin
  S := GetEnvironmentVariable(Key);
  if S = '' then Result := Default
  else            Result := StrToIntDef(S, Default);
end;

procedure TRedisTool.Connect(const AParams: TRedisParams);
var
  Host, Pass: string;
  Port, Db:   Integer;
begin
  Host := AParams.Host;     if Host = '' then Host := Env('REDIS_HOST', 'localhost');
  Port := AParams.Port;     if Port = 0  then Port := EnvInt('REDIS_PORT', 6379);
  Pass := AParams.Password; if Pass = '' then Pass := Env('REDIS_PASSWORD', '');
  Db   := AParams.Db;

  FClient.Host            := Host;
  FClient.Port            := Port;
  FClient.ConnectTimeout  := 10000;
  FClient.ReadTimeout     := 15000;
  FClient.Connect;

  if Pass <> '' then
  begin
    var Resp := SendCmd(['AUTH', Pass]);
    if not Resp.StartsWith('+OK') and not Resp.StartsWith(':') then
      raise Exception.Create('Redis AUTH failed: ' + Resp);
  end;

  if Db <> 0 then
  begin
    var Resp := SendCmd(['SELECT', IntToStr(Db)]);
    if not Resp.StartsWith('+OK') then
      raise Exception.Create('Redis SELECT failed: ' + Resp);
  end;
end;

procedure TRedisTool.Disconnect;
begin
  if FClient.Connected then
    FClient.Disconnect;
end;

function TRedisTool.SendCmd(const Args: array of string): string;
var
  Cmd: string;
begin
  Cmd := '*' + IntToStr(Length(Args)) + #13#10;
  for var S in Args do
    Cmd := Cmd + '$' + IntToStr(Length(S)) + #13#10 + S + #13#10;
  FClient.IOHandler.Write(Cmd);
  Result := ReadResponse;
end;

function TRedisTool.ReadLine: string;
begin
  Result := FClient.IOHandler.ReadLn(#10);
  if Result.EndsWith(#13) then
    Result := Result.Substring(0, Result.Length - 1);
end;

function TRedisTool.ReadResponse: string;
var
  Line: string;
  Len:  Integer;
begin
  Line := ReadLine;
  if Line = '' then
    Exit('');

  case Line[1] of
    '+': Result := Line;
    '-': Result := Line;
    ':': Result := Line;
    '$':
    begin
      Len := StrToIntDef(Line.Substring(1), -1);
      if Len = -1 then
        Result := '$-1'
      else
      begin
        var Data := FClient.IOHandler.ReadString(Len);
        ReadLine;
        Result := '+' + Data;
      end;
    end;
    '*':
    begin
      var Count := StrToIntDef(Line.Substring(1), 0);
      if Count <= 0 then
        Result := '*0'
      else
      begin
        var Parts := TStringList.Create;
        try
          for var i := 0 to Count - 1 do
            Parts.Add(ReadResponse);
          Result := '*' + Parts.CommaText;
        finally
          Parts.Free;
        end;
      end;
    end;
  else
    Result := Line;
  end;
end;

function RespValue(const R: string): string;
begin
  if R = '' then Result := ''
  else if R = '$-1' then Result := '(nil)'
  else if (R[1] = '+') or (R[1] = ':') then Result := R.Substring(1)
  else if R[1] = '-' then raise Exception.Create(R.Substring(1))
  else Result := R;
end;

// ── Main execution ──────────────────────────────────────────────────────────

function TRedisTool.ExecuteWithParams(const AParams: TRedisParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    Connect(AParams);
    try

      if Op = 'ping' then
      begin
        var Resp := SendCmd(['PING']);
        R := TJSONObject.Create;
        R.AddPair('ok',       TJSONBool.Create(Resp.StartsWith('+PONG')));
        R.AddPair('response', RespValue(Resp));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'get' then
      begin
        if AParams.Key = '' then raise Exception.Create('"key" is required');
        var Resp := SendCmd(['GET', AParams.Key]);
        var Val  := RespValue(Resp);
        R := TJSONObject.Create;
        R.AddPair('key',   AParams.Key);
        R.AddPair('value', Val);
        R.AddPair('exists', TJSONBool.Create(Val <> '(nil)'));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'set' then
      begin
        if AParams.Key   = '' then raise Exception.Create('"key" is required');
        if AParams.Value = '' then raise Exception.Create('"value" is required');
        var Resp: string;
        if AParams.Ttl > 0 then
          Resp := SendCmd(['SET', AParams.Key, AParams.Value, 'EX', IntToStr(AParams.Ttl)])
        else
          Resp := SendCmd(['SET', AParams.Key, AParams.Value]);
        R := TJSONObject.Create;
        R.AddPair('ok',  TJSONBool.Create(Resp.StartsWith('+OK')));
        R.AddPair('key', AParams.Key);
        if AParams.Ttl > 0 then
          R.AddPair('ttl', TJSONNumber.Create(AParams.Ttl));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'del' then
      begin
        if AParams.Key = '' then raise Exception.Create('"key" is required');
        var Keys := AParams.Key.Split([',']);
        var Args: TArray<string>;
        SetLength(Args, Length(Keys) + 1);
        Args[0] := 'DEL';
        for var i := 0 to High(Keys) do
          Args[i + 1] := Trim(Keys[i]);
        var Resp := SendCmd(Args);
        R := TJSONObject.Create;
        R.AddPair('deleted', TJSONNumber.Create(StrToIntDef(RespValue(Resp), 0)));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'exists' then
      begin
        if AParams.Key = '' then raise Exception.Create('"key" is required');
        var Resp := SendCmd(['EXISTS', AParams.Key]);
        R := TJSONObject.Create;
        R.AddPair('key',    AParams.Key);
        R.AddPair('exists', TJSONBool.Create(RespValue(Resp) = '1'));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'keys' then
      begin
        var Pat := AParams.Pattern;
        if Pat = '' then Pat := '*';
        var Resp := SendCmd(['KEYS', Pat]);
        var Items := TJSONArray.Create;
        if Resp.StartsWith('*') then
        begin
          var Parts := Resp.Substring(1).Split([',']);
          for var P in Parts do
          begin
            var K := P.Trim;
            if K.StartsWith('+') then K := K.Substring(1);
            if K <> '' then Items.Add(K);
          end;
        end;
        R := TJSONObject.Create;
        R.AddPair('pattern', Pat);
        R.AddPair('count',   TJSONNumber.Create(Items.Count));
        R.AddPair('keys',    Items);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'incr' then
      begin
        if AParams.Key = '' then raise Exception.Create('"key" is required');
        var Resp := SendCmd(['INCR', AParams.Key]);
        R := TJSONObject.Create;
        R.AddPair('key',   AParams.Key);
        R.AddPair('value', TJSONNumber.Create(StrToInt64Def(RespValue(Resp), 0)));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'expire' then
      begin
        if AParams.Key = '' then raise Exception.Create('"key" is required');
        if AParams.Ttl <= 0 then raise Exception.Create('"ttl" must be > 0');
        var Resp := SendCmd(['EXPIRE', AParams.Key, IntToStr(AParams.Ttl)]);
        R := TJSONObject.Create;
        R.AddPair('key', AParams.Key);
        R.AddPair('ok',  TJSONBool.Create(RespValue(Resp) = '1'));
        R.AddPair('ttl', TJSONNumber.Create(AParams.Ttl));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'ttl' then
      begin
        if AParams.Key = '' then raise Exception.Create('"key" is required');
        var Resp := SendCmd(['TTL', AParams.Key]);
        var Secs := StrToInt64Def(RespValue(Resp), -2);
        R := TJSONObject.Create;
        R.AddPair('key', AParams.Key);
        R.AddPair('ttl', TJSONNumber.Create(Secs));
        if    Secs = -1 then R.AddPair('note', 'key exists, no TTL set')
        else if Secs = -2 then R.AddPair('note', 'key does not exist');
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'hget' then
      begin
        if AParams.Key   = '' then raise Exception.Create('"key" is required');
        if AParams.Field = '' then raise Exception.Create('"field" is required');
        var Resp := SendCmd(['HGET', AParams.Key, AParams.Field]);
        R := TJSONObject.Create;
        R.AddPair('key',   AParams.Key);
        R.AddPair('field', AParams.Field);
        R.AddPair('value', RespValue(Resp));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'hset' then
      begin
        if AParams.Key   = '' then raise Exception.Create('"key" is required');
        if AParams.Field = '' then raise Exception.Create('"field" is required');
        if AParams.Value = '' then raise Exception.Create('"value" is required');
        var Resp := SendCmd(['HSET', AParams.Key, AParams.Field, AParams.Value]);
        R := TJSONObject.Create;
        R.AddPair('ok',    TJSONBool.Create(True));
        R.AddPair('key',   AParams.Key);
        R.AddPair('field', AParams.Field);
        R.AddPair('added', TJSONNumber.Create(StrToIntDef(RespValue(Resp), 0)));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'hgetall' then
      begin
        if AParams.Key = '' then raise Exception.Create('"key" is required');
        var Resp := SendCmd(['HGETALL', AParams.Key]);
        var Hash := TJSONObject.Create;
        if Resp.StartsWith('*') then
        begin
          var Parts := Resp.Substring(1).Split([',']);
          var i := 0;
          while i + 1 < Length(Parts) do
          begin
            var K := Parts[i].Trim;   if K.StartsWith('+') then K := K.Substring(1);
            var V := Parts[i+1].Trim; if V.StartsWith('+') then V := V.Substring(1);
            Hash.AddPair(K, V);
            Inc(i, 2);
          end;
        end;
        R := TJSONObject.Create;
        R.AddPair('key',    AParams.Key);
        R.AddPair('fields', Hash);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'lpush' then
      begin
        if AParams.Key   = '' then raise Exception.Create('"key" is required');
        if AParams.Value = '' then raise Exception.Create('"value" is required');
        var Resp := SendCmd(['LPUSH', AParams.Key, AParams.Value]);
        R := TJSONObject.Create;
        R.AddPair('ok',          TJSONBool.Create(True));
        R.AddPair('key',         AParams.Key);
        R.AddPair('list_length', TJSONNumber.Create(StrToIntDef(RespValue(Resp), 0)));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'lrange' then
      begin
        if AParams.Key = '' then raise Exception.Create('"key" is required');
        var Sta := AParams.Start;
        var Sto := AParams.Stop;
        if Sto = 0 then Sto := -1;
        var Resp := SendCmd(['LRANGE', AParams.Key, IntToStr(Sta), IntToStr(Sto)]);
        var Items := TJSONArray.Create;
        if Resp.StartsWith('*') then
        begin
          var Parts := Resp.Substring(1).Split([',']);
          for var P in Parts do
          begin
            var V := P.Trim;
            if V.StartsWith('+') then V := V.Substring(1);
            if V <> '' then Items.Add(V);
          end;
        end;
        R := TJSONObject.Create;
        R.AddPair('key',   AParams.Key);
        R.AddPair('count', TJSONNumber.Create(Items.Count));
        R.AddPair('items', Items);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'dbsize' then
      begin
        var Resp := SendCmd(['DBSIZE']);
        R := TJSONObject.Create;
        R.AddPair('keys', TJSONNumber.Create(StrToInt64Def(RespValue(Resp), 0)));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else if Op = 'info' then
      begin
        var Resp := SendCmd(['INFO', 'server']);
        var Info := RespValue(Resp);
        var InfoObj := TJSONObject.Create;
        var Lines := Info.Split([#10]);
        for var Line in Lines do
        begin
          var L := Trim(Line);
          if (L = '') or L.StartsWith('#') then Continue;
          var Pos := L.IndexOf(':');
          if Pos > 0 then
            InfoObj.AddPair(L.Substring(0, Pos), Trim(L.Substring(Pos + 1)));
        end;
        R := TJSONObject.Create;
        R.AddPair('info', InfoObj);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      end

      else
        raise Exception.CreateFmt(
          'Unknown operation: "%s". Valid: ping, get, set, del, exists, keys, ' +
          'incr, expire, ttl, hget, hset, hgetall, lpush, lrange, info, dbsize', [Op]);

    finally
      Disconnect;
    end;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-redis]: ' + E.Message)
        .Build;
  end;
end;

constructor TRedisTool.Create;
begin
  inherited;
  FClient      := TIdTCPClient.Create(nil);
  FName        := 'mcp-redis';
  FDescription :=
    'Redis client (RESP protocol via Indy). ' +
    'Credentials via params (host, port, password, db) or env vars REDIS_HOST/REDIS_PORT/REDIS_PASSWORD/REDIS_DB. ' +
    'ping: check connectivity. ' +
    'get/set/del/exists/keys/incr: string operations. ' +
    'expire/ttl: key expiry. ' +
    'hget/hset/hgetall: hash operations. ' +
    'lpush/lrange: list operations. ' +
    'dbsize: count keys. ' +
    'info: server information.';
end;

destructor TRedisTool.Destroy;
begin
  FClient.Free;
  inherited;
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-redis',
    function: IAiMCPTool
    begin
      Result := TRedisTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-redis] registered');
end;

end.
