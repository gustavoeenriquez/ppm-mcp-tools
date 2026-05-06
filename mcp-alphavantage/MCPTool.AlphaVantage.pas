unit MCPTool.AlphaVantage;

{
  MCPTool.AlphaVantage  ·  mcp-alphavantage  (port 8624)
  Stock market data via Alpha Vantage API (free key required).

  Operations:
    quote        - real-time stock quote (GLOBAL_QUOTE)
    daily        - daily time series OHLCV
    weekly       - weekly time series OHLCV
    monthly      - monthly time series OHLCV
    intraday     - intraday time series (1min/5min/15min/30min/60min)
    overview     - company overview (fundamentals)
    earnings     - annual/quarterly EPS
    forex        - FX exchange rate (CURRENCY_EXCHANGE_RATE)
    crypto       - crypto exchange rate
    indicator    - technical indicator (SMA, EMA, RSI, MACD, BBANDS, etc.)
    search       - symbol search by keyword
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TAlphaVantageParams = class
  private
    FOperation:  string;
    FApiKey:     string;
    FSymbol:     string;
    FFromCur:    string;
    FToCur:      string;
    FInterval:   string;
    FOutputSize: string;
    FIndicator:  string;
    FTimePeriod: Integer;
    FSeriesType: string;
    FKeyword:    string;
    FDataType:   string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: quote, daily, weekly, monthly, intraday, overview, earnings, forex, crypto, indicator, search')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPSchemaDescription('Alpha Vantage API key (free at alphavantage.co)')]
    property ApiKey:     string  read FApiKey     write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Stock/crypto symbol (e.g. IBM, AAPL, MSFT, BTC)')]
    property Symbol:     string  read FSymbol     write FSymbol;

    [AiMCPOptional]
    [AiMCPSchemaDescription('From currency code for forex/crypto (e.g. USD, BTC, EUR)')]
    property FromCur:    string  read FFromCur    write FFromCur;

    [AiMCPOptional]
    [AiMCPSchemaDescription('To currency code for forex/crypto (e.g. USD, JPY, ETH)')]
    property ToCur:      string  read FToCur      write FToCur;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Interval for intraday: 1min, 5min, 15min, 30min, 60min (default: 5min)')]
    property Interval:   string  read FInterval   write FInterval;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Output size: compact (latest 100) or full (20+ years). Default: compact')]
    property OutputSize: string  read FOutputSize write FOutputSize;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Technical indicator name: SMA, EMA, WMA, DEMA, TEMA, RSI, MACD, BBANDS, STOCH, ADX, CCI, AROON')]
    property Indicator:  string  read FIndicator  write FIndicator;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of data points for indicator calculation (default: 14)')]
    property TimePeriod: Integer read FTimePeriod write FTimePeriod;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Price series for indicator: open, high, low, close (default: close)')]
    property SeriesType: string  read FSeriesType write FSeriesType;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search keyword for symbol lookup')]
    property Keyword:    string  read FKeyword    write FKeyword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Response format: json or csv (default: json)')]
    property DataType:   string  read FDataType   write FDataType;
  end;

  TAlphaVantageTool = class(TAiMCPToolBase<TAlphaVantageParams>)
  private
    function ApiGet(const Params, ApiKey: string): string;
    function ParseResponse(const Raw: string): TJSONObject;
    function DoQuote(const P: TAlphaVantageParams): TJSONObject;
    function DoTimeSeries(const P: TAlphaVantageParams; const Func: string): TJSONObject;
    function DoIntraday(const P: TAlphaVantageParams): TJSONObject;
    function DoOverview(const P: TAlphaVantageParams): TJSONObject;
    function DoEarnings(const P: TAlphaVantageParams): TJSONObject;
    function DoForex(const P: TAlphaVantageParams): TJSONObject;
    function DoCrypto(const P: TAlphaVantageParams): TJSONObject;
    function DoIndicator(const P: TAlphaVantageParams): TJSONObject;
    function DoSearch(const P: TAlphaVantageParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TAlphaVantageParams;
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

const
  BASE_URL = 'https://www.alphavantage.co/query';

{ TAlphaVantageParams }

constructor TAlphaVantageParams.Create;
begin
  inherited;
  FInterval   := '5min';
  FOutputSize := 'compact';
  FSeriesType := 'close';
  FTimePeriod := 14;
  FDataType   := 'json';
end;

{ TAlphaVantageTool }

function TAlphaVantageTool.ApiGet(const Params, ApiKey: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  URL:  string;
begin
  HTTP := THTTPClient.Create;
  try
    URL    := BASE_URL + '?' + Params + '&apikey=' + Trim(ApiKey);
    Resp   := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TAlphaVantageTool.ParseResponse(const Raw: string): TJSONObject;
var
  J: TJSONValue;
begin
  J := TJSONObject.ParseJSONValue(Raw);
  if Assigned(J) then
  begin
    if J is TJSONObject then
    begin
      // Check for API error messages
      var Err := (J as TJSONObject).GetValue<string>('Information', '');
      if Err = '' then
        Err := (J as TJSONObject).GetValue<string>('Note', '');
      if Err = '' then
        Err := (J as TJSONObject).GetValue<string>('Error Message', '');
      if Err <> '' then
      begin
        Result := TJSONObject.Create;
        Result.AddPair('ok',    TJSONFalse.Create);
        Result.AddPair('error', TJSONString.Create(Err));
        J.Free;
        Exit;
      end;
      Result := J as TJSONObject;
    end
    else
    begin
      Result := TJSONObject.Create;
      Result.AddPair('data', J);
    end;
  end
  else
  begin
    Result := TJSONObject.Create;
    Result.AddPair('raw', TJSONString.Create(Raw));
  end;
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TAlphaVantageTool.DoQuote(const P: TAlphaVantageParams): TJSONObject;
var
  Sym: string;
begin
  Sym := Trim(P.Symbol);
  if Sym = '' then raise Exception.Create('"symbol" required for quote');
  Result := ParseResponse(ApiGet('function=GLOBAL_QUOTE&symbol=' + Sym, P.ApiKey));
end;

function TAlphaVantageTool.DoTimeSeries(const P: TAlphaVantageParams;
  const Func: string): TJSONObject;
var
  Sym, OS: string;
begin
  Sym := Trim(P.Symbol);
  if Sym = '' then raise Exception.Create('"symbol" required');
  OS := Trim(P.OutputSize); if OS = '' then OS := 'compact';
  Result := ParseResponse(ApiGet(
    'function=' + Func + '&symbol=' + Sym + '&outputsize=' + OS, P.ApiKey));
end;

function TAlphaVantageTool.DoIntraday(const P: TAlphaVantageParams): TJSONObject;
var
  Sym, Intv, OS: string;
begin
  Sym  := Trim(P.Symbol);   if Sym  = '' then raise Exception.Create('"symbol" required for intraday');
  Intv := Trim(P.Interval); if Intv = '' then Intv := '5min';
  OS   := Trim(P.OutputSize); if OS = '' then OS := 'compact';
  Result := ParseResponse(ApiGet(
    'function=TIME_SERIES_INTRADAY&symbol=' + Sym +
    '&interval=' + Intv + '&outputsize=' + OS, P.ApiKey));
end;

function TAlphaVantageTool.DoOverview(const P: TAlphaVantageParams): TJSONObject;
var
  Sym: string;
begin
  Sym := Trim(P.Symbol);
  if Sym = '' then raise Exception.Create('"symbol" required for overview');
  Result := ParseResponse(ApiGet('function=OVERVIEW&symbol=' + Sym, P.ApiKey));
end;

function TAlphaVantageTool.DoEarnings(const P: TAlphaVantageParams): TJSONObject;
var
  Sym: string;
begin
  Sym := Trim(P.Symbol);
  if Sym = '' then raise Exception.Create('"symbol" required for earnings');
  Result := ParseResponse(ApiGet('function=EARNINGS&symbol=' + Sym, P.ApiKey));
end;

function TAlphaVantageTool.DoForex(const P: TAlphaVantageParams): TJSONObject;
var
  From, To_: string;
begin
  From := Trim(P.FromCur); if From = '' then raise Exception.Create('"fromCur" required for forex');
  To_  := Trim(P.ToCur);  if To_  = '' then raise Exception.Create('"toCur" required for forex');
  Result := ParseResponse(ApiGet(
    'function=CURRENCY_EXCHANGE_RATE&from_currency=' + From + '&to_currency=' + To_, P.ApiKey));
end;

function TAlphaVantageTool.DoCrypto(const P: TAlphaVantageParams): TJSONObject;
var
  From, To_: string;
begin
  From := Trim(P.FromCur); if From = '' then raise Exception.Create('"fromCur" (crypto symbol) required');
  To_  := Trim(P.ToCur);  if To_  = '' then To_ := 'USD';
  Result := ParseResponse(ApiGet(
    'function=CURRENCY_EXCHANGE_RATE&from_currency=' + From + '&to_currency=' + To_, P.ApiKey));
end;

function TAlphaVantageTool.DoIndicator(const P: TAlphaVantageParams): TJSONObject;
var
  Sym, Ind, Intv, ST: string;
  TP: Integer;
begin
  Sym  := Trim(P.Symbol);     if Sym  = '' then raise Exception.Create('"symbol" required for indicator');
  Ind  := UpperCase(Trim(P.Indicator)); if Ind = '' then raise Exception.Create('"indicator" required (e.g. SMA, RSI, MACD)');
  Intv := Trim(P.Interval);   if Intv = '' then Intv := 'daily';
  ST   := Trim(P.SeriesType); if ST   = '' then ST   := 'close';
  TP   := P.TimePeriod;       if TP   <= 0 then TP   := 14;
  Result := ParseResponse(ApiGet(
    'function=' + Ind + '&symbol=' + Sym + '&interval=' + Intv +
    '&time_period=' + IntToStr(TP) + '&series_type=' + ST, P.ApiKey));
end;

function TAlphaVantageTool.DoSearch(const P: TAlphaVantageParams): TJSONObject;
var
  Kw: string;
begin
  Kw := Trim(P.Keyword);
  if Kw = '' then raise Exception.Create('"keyword" required for search');
  Result := ParseResponse(ApiGet(
    'function=SYMBOL_SEARCH&keywords=' + Kw.Replace(' ', '+'), P.ApiKey));
end;

function TAlphaVantageTool.ExecuteWithParams(const AParams: TAlphaVantageParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    if Trim(AParams.ApiKey) = '' then
      raise Exception.Create('"apiKey" is required (get free key at alphavantage.co)');
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'quote'    then R := DoQuote(AParams)
    else if Op = 'daily'    then R := DoTimeSeries(AParams, 'TIME_SERIES_DAILY')
    else if Op = 'weekly'   then R := DoTimeSeries(AParams, 'TIME_SERIES_WEEKLY')
    else if Op = 'monthly'  then R := DoTimeSeries(AParams, 'TIME_SERIES_MONTHLY')
    else if Op = 'intraday' then R := DoIntraday(AParams)
    else if Op = 'overview' then R := DoOverview(AParams)
    else if Op = 'earnings' then R := DoEarnings(AParams)
    else if Op = 'forex'    then R := DoForex(AParams)
    else if Op = 'crypto'   then R := DoCrypto(AParams)
    else if Op = 'indicator' then R := DoIndicator(AParams)
    else if Op = 'search'   then R := DoSearch(AParams)
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

constructor TAlphaVantageTool.Create;
begin
  inherited;
  FName        := 'mcp-alphavantage';
  FDescription :=
    'Stock market data via Alpha Vantage API (free key required from alphavantage.co). ' +
    'Operations: quote (params: symbol) → real-time price, ' +
    'daily/weekly/monthly (params: symbol, outputSize?) → OHLCV time series, ' +
    'intraday (params: symbol, interval? [1min/5min/15min/30min/60min], outputSize?) → intraday bars, ' +
    'overview (params: symbol) → company fundamentals, ' +
    'earnings (params: symbol) → annual/quarterly EPS, ' +
    'forex (params: fromCur, toCur) → FX exchange rate, ' +
    'crypto (params: fromCur, toCur?) → crypto/fiat rate, ' +
    'indicator (params: symbol, indicator [SMA/EMA/RSI/MACD/BBANDS/etc], interval?, timePeriod?, seriesType?) → technical analysis, ' +
    'search (params: keyword) → symbol lookup. ' +
    'apiKey required for all operations.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-alphavantage',
    function: IAiMCPTool
    begin
      Result := TAlphaVantageTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-alphavantage');
end;

end.
