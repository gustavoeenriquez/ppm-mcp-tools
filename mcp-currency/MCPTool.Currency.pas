unit MCPTool.Currency;

{
  MCPTool.Currency  ·  mcp-currency

  Currency exchange rates and conversion via open.er-api.com (free, no key required).

  Operations:
    latest  - get latest exchange rates for a base currency
    convert - convert an amount from one currency to another
    list    - list all available currency codes
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient;

type

  TCurrencyParams = class
  private
    FOperation: string;
    FBase:      string;
    FTarget:    string;
    FAmount:    Double;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: latest, convert, list')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Base currency code (default: USD)')]
    property Base:      string read FBase      write FBase;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Target currency code (for convert)')]
    property Target:    string read FTarget    write FTarget;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Amount to convert (default: 1)')]
    property Amount:    Double read FAmount    write FAmount;
  end;

  TCurrencyTool = class(TAiMCPToolBase<TCurrencyParams>)
  private
    function HttpGet(const URL: string): string;
    function DoLatest(const P: TCurrencyParams): TJSONObject;
    function DoConvert(const P: TCurrencyParams): TJSONObject;
    function DoList(const P: TCurrencyParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TCurrencyParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

const
  API_BASE = 'https://open.er-api.com/v6/latest/';

{ TCurrencyParams }

constructor TCurrencyParams.Create;
begin
  inherited;
  FBase   := 'USD';
  FAmount := 1.0;
end;

{ TCurrencyTool }

function TCurrencyTool.HttpGet(const URL: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 10000;
    HTTP.ResponseTimeout   := 15000;
    Resp := HTTP.Get(URL);
    if Resp.StatusCode <> 200 then
      raise Exception.CreateFmt('HTTP %d: %s', [Resp.StatusCode, Resp.ContentAsString.Substring(0, 200)]);
    Result := Resp.ContentAsString;
  finally
    HTTP.Free;
  end;
end;

function TCurrencyTool.DoLatest(const P: TCurrencyParams): TJSONObject;
var
  Base:    string;
  RespStr: string;
  Parsed:  TJSONValue;
  Rates:   TJSONObject;
  Updated: string;
begin
  Base    := UpperCase(Trim(P.Base));
  if Base = '' then Base := 'USD';
  RespStr := HttpGet(API_BASE + Base);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    if not (Parsed is TJSONObject) then
      raise Exception.Create('Invalid API response');
    var J := Parsed as TJSONObject;
    var Status := J.GetValue<string>('result', '');
    if not SameText(Status, 'success') then
      raise Exception.Create('API error: ' + J.GetValue<string>('error-type', 'unknown'));

    Rates   := nil;
    J.TryGetValue<TJSONObject>('rates', Rates);
    Updated := J.GetValue<string>('time_last_update_utc', '');

    Result := TJSONObject.Create;
    Result.AddPair('base',    Base);
    Result.AddPair('updated', Updated);
    if Rates <> nil then
      Result.AddPair('rates', Rates.Clone as TJSONObject);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TCurrencyTool.DoConvert(const P: TCurrencyParams): TJSONObject;
var
  Base, Target: string;
  Amount:       Double;
  RespStr:      string;
  Parsed:       TJSONValue;
  Rates:        TJSONObject;
  RateVal:      TJSONValue;
  Rate:         Double;
begin
  Base   := UpperCase(Trim(P.Base));
  Target := UpperCase(Trim(P.Target));
  Amount := P.Amount;
  if Base   = '' then Base   := 'USD';
  if Target = '' then raise Exception.Create('"target" required for convert');
  if Amount <= 0 then Amount := 1;

  RespStr := HttpGet(API_BASE + Base);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    if not (Parsed is TJSONObject) then
      raise Exception.Create('Invalid API response');
    var J := Parsed as TJSONObject;
    Rates  := nil;
    J.TryGetValue<TJSONObject>('rates', Rates);
    if Rates = nil then
      raise Exception.Create('No rates data in response');

    RateVal := Rates.GetValue(Target);
    if RateVal = nil then
      raise Exception.CreateFmt('Currency not found: %s', [Target]);

    if RateVal is TJSONNumber then
      Rate := (RateVal as TJSONNumber).AsDouble
    else
      Rate := StrToFloatDef(RateVal.Value, 0);

    if Rate = 0 then
      raise Exception.CreateFmt('Invalid rate for: %s', [Target]);

    Result := TJSONObject.Create;
    Result.AddPair('from',      Base);
    Result.AddPair('to',        Target);
    Result.AddPair('amount',    TJSONNumber.Create(Amount));
    Result.AddPair('rate',      TJSONNumber.Create(Rate));
    Result.AddPair('converted', TJSONNumber.Create(Amount * Rate));
    Result.AddPair('ok',        TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TCurrencyTool.DoList(const P: TCurrencyParams): TJSONObject;
var
  RespStr: string;
  Parsed:  TJSONValue;
  Rates:   TJSONObject;
  Arr:     TJSONArray;
  i:       Integer;
begin
  RespStr := HttpGet(API_BASE + 'USD');
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    if not (Parsed is TJSONObject) then
      raise Exception.Create('Invalid API response');
    Rates := nil;
    (Parsed as TJSONObject).TryGetValue<TJSONObject>('rates', Rates);
    Arr := TJSONArray.Create;
    if Rates <> nil then
      for i := 0 to Rates.Count - 1 do
        Arr.Add(Rates.Pairs[i].JsonString.Value);

    Result := TJSONObject.Create;
    Result.AddPair('currencies', Arr);
    Result.AddPair('count',      TJSONNumber.Create(Arr.Count));
    Result.AddPair('ok',         TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TCurrencyTool.ExecuteWithParams(const AParams: TCurrencyParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'latest'  then R := DoLatest(AParams)
    else if Op = 'convert' then R := DoConvert(AParams)
    else if Op = 'list'    then R := DoList(AParams)
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

constructor TCurrencyTool.Create;
begin
  inherited;
  FName        := 'mcp-currency';
  FDescription :=
    'Currency exchange rates and conversion (free API, no key required). ' +
    'Operations: ' +
    'latest (get all rates for a base currency; param: base), ' +
    'convert (convert an amount; params: base, target, amount), ' +
    'list (list all available currency codes). ' +
    'Supports 160+ currencies (USD, EUR, GBP, JPY, etc.).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-currency',
    function: IAiMCPTool
    begin
      Result := TCurrencyTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-currency] ready');
end;

end.
