unit MCPTool.CoinGecko;

{
  MCPTool.CoinGecko  ·  mcp-coingecko  (port 8623)
  Cryptocurrency data via CoinGecko API v3 (free & Pro).

  Operations:
    price        - current price for one or more coins
    markets      - market data (rank, price, volume, cap) for multiple coins
    coin_info    - detailed info for a single coin
    market_chart - historical price/volume/cap data
    trending     - trending coins in last 24h
    search       - search coins, categories, exchanges
    global       - global crypto market statistics
    exchanges    - list exchanges with volume data
    categories   - list coin categories
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TCoinGeckoParams = class
  private
    FOperation:  string;
    FApiKey:     string;
    FCoinId:     string;
    FCoinIds:    string;
    FCurrency:   string;
    FPage:       Integer;
    FPerPage:    Integer;
    FDays:       string;
    FOrder:      string;
    FQuery:      string;
    FCategory:   string;
    FSparkline:  Boolean;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: price, markets, coin_info, market_chart, trending, search, global, exchanges, categories')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('CoinGecko Pro API key (optional, for higher rate limits)')]
    property ApiKey:     string  read FApiKey     write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Coin ID (e.g. bitcoin, ethereum, solana) — for price, coin_info, market_chart')]
    property CoinId:     string  read FCoinId     write FCoinId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Comma-separated coin IDs for price (e.g. bitcoin,ethereum,solana)')]
    property CoinIds:    string  read FCoinIds    write FCoinIds;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Target currency (default: usd). Examples: usd, eur, btc, eth')]
    property Currency:   string  read FCurrency   write FCurrency;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Page number for paginated results (default: 1)')]
    property Page:       Integer read FPage       write FPage;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Results per page for markets/exchanges (default: 20, max: 250)')]
    property PerPage:    Integer read FPerPage    write FPerPage;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Days of history for market_chart: 1, 7, 14, 30, 90, 180, 365, max')]
    property Days:       string  read FDays       write FDays;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Sort order for markets: market_cap_desc, market_cap_asc, volume_asc, volume_desc (default: market_cap_desc)')]
    property Order:      string  read FOrder      write FOrder;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search query (for search operation)')]
    property Query:      string  read FQuery      write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Filter markets by category slug (for markets operation)')]
    property Category:   string  read FCategory   write FCategory;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Include 7-day sparkline data in markets (default: false)')]
    property Sparkline:  Boolean read FSparkline  write FSparkline;
  end;

  TCoinGeckoTool = class(TAiMCPToolBase<TCoinGeckoParams>)
  private
    function ApiGet(const Path, ApiKey: string): string;
    function ParseResponse(const Raw: string): TJSONObject;
    function DoPrice(const P: TCoinGeckoParams): TJSONObject;
    function DoMarkets(const P: TCoinGeckoParams): TJSONObject;
    function DoCoinInfo(const P: TCoinGeckoParams): TJSONObject;
    function DoMarketChart(const P: TCoinGeckoParams): TJSONObject;
    function DoTrending(const P: TCoinGeckoParams): TJSONObject;
    function DoSearch(const P: TCoinGeckoParams): TJSONObject;
    function DoGlobal(const P: TCoinGeckoParams): TJSONObject;
    function DoExchanges(const P: TCoinGeckoParams): TJSONObject;
    function DoCategories(const P: TCoinGeckoParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TCoinGeckoParams;
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
  BASE_FREE = 'https://api.coingecko.com/api/v3';
  BASE_PRO  = 'https://pro-api.coingecko.com/api/v3';

{ TCoinGeckoParams }

constructor TCoinGeckoParams.Create;
begin
  inherited;
  FCurrency := 'usd';
  FPage     := 1;
  FPerPage  := 20;
  FDays     := '7';
  FOrder    := 'market_cap_desc';
  FSparkline := False;
end;

{ TCoinGeckoTool }

function TCoinGeckoTool.ApiGet(const Path, ApiKey: string): string;
var
  HTTP:    THTTPClient;
  Resp:    IHTTPResponse;
  BaseURL: string;
  URL:     string;
begin
  HTTP := THTTPClient.Create;
  try
    if Trim(ApiKey) <> '' then
    begin
      BaseURL := BASE_PRO;
      URL     := BaseURL + Path;
      Resp    := HTTP.Get(URL, nil,
        [TNameValuePair.Create('x-cg-pro-api-key', Trim(ApiKey))]);
    end
    else
    begin
      BaseURL := BASE_FREE;
      URL     := BaseURL + Path;
      Resp    := HTTP.Get(URL, nil,
        [TNameValuePair.Create('Accept', 'application/json')]);
    end;
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TCoinGeckoTool.ParseResponse(const Raw: string): TJSONObject;
var
  J: TJSONValue;
begin
  J := TJSONObject.ParseJSONValue(Raw);
  if Assigned(J) then
  begin
    if J is TJSONObject then
      Result := J as TJSONObject
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

function TCoinGeckoTool.DoPrice(const P: TCoinGeckoParams): TJSONObject;
var
  Ids, Cur, Path, Raw: string;
begin
  Ids := Trim(P.CoinIds);
  if Ids = '' then Ids := Trim(P.CoinId);
  if Ids = '' then raise Exception.Create('"coinIds" or "coinId" required for price');
  Cur  := Trim(P.Currency); if Cur = '' then Cur := 'usd';
  Path := '/simple/price?ids=' + Ids + '&vs_currencies=' + Cur +
          '&include_market_cap=true&include_24hr_vol=true&include_24hr_change=true';
  Raw  := ApiGet(Path, P.ApiKey);
  Result := ParseResponse(Raw);
end;

function TCoinGeckoTool.DoMarkets(const P: TCoinGeckoParams): TJSONObject;
var
  Cur, Order, Path, Raw, SP, Cat: string;
  Per: Integer;
begin
  Cur   := Trim(P.Currency); if Cur = '' then Cur := 'usd';
  Order := Trim(P.Order);    if Order = '' then Order := 'market_cap_desc';
  Per   := P.PerPage;        if Per <= 0 then Per := 20;
  if P.Sparkline then SP := 'true' else SP := 'false';
  Cat := Trim(P.Category);

  Path := Format('/coins/markets?vs_currency=%s&order=%s&per_page=%d&page=%d&sparkline=%s',
    [Cur, Order, Per, P.Page, SP]);
  if Cat <> '' then Path := Path + '&category=' + Cat;
  Raw := ApiGet(Path, P.ApiKey);
  Result := ParseResponse(Raw);
end;

function TCoinGeckoTool.DoCoinInfo(const P: TCoinGeckoParams): TJSONObject;
var
  Id, Raw: string;
begin
  Id := Trim(P.CoinId);
  if Id = '' then raise Exception.Create('"coinId" required for coin_info');
  Raw    := ApiGet('/coins/' + Id + '?localization=false&tickers=false&community_data=false&developer_data=false', P.ApiKey);
  Result := ParseResponse(Raw);
end;

function TCoinGeckoTool.DoMarketChart(const P: TCoinGeckoParams): TJSONObject;
var
  Id, Cur, Days, Raw: string;
begin
  Id   := Trim(P.CoinId);   if Id   = '' then raise Exception.Create('"coinId" required for market_chart');
  Cur  := Trim(P.Currency); if Cur  = '' then Cur  := 'usd';
  Days := Trim(P.Days);     if Days = '' then Days := '7';
  Raw    := ApiGet(Format('/coins/%s/market_chart?vs_currency=%s&days=%s', [Id, Cur, Days]), P.ApiKey);
  Result := ParseResponse(Raw);
end;

function TCoinGeckoTool.DoTrending(const P: TCoinGeckoParams): TJSONObject;
var
  Raw: string;
begin
  Raw    := ApiGet('/search/trending', P.ApiKey);
  Result := ParseResponse(Raw);
end;

function TCoinGeckoTool.DoSearch(const P: TCoinGeckoParams): TJSONObject;
var
  Q, Raw: string;
begin
  Q := Trim(P.Query);
  if Q = '' then raise Exception.Create('"query" required for search');
  Raw    := ApiGet('/search?query=' + Q.Replace(' ', '%20'), P.ApiKey);
  Result := ParseResponse(Raw);
end;

function TCoinGeckoTool.DoGlobal(const P: TCoinGeckoParams): TJSONObject;
var
  Raw: string;
begin
  Raw    := ApiGet('/global', P.ApiKey);
  Result := ParseResponse(Raw);
end;

function TCoinGeckoTool.DoExchanges(const P: TCoinGeckoParams): TJSONObject;
var
  Per, Raw: string;
  PerI: Integer;
begin
  PerI := P.PerPage; if PerI <= 0 then PerI := 20;
  Per  := IntToStr(PerI);
  Raw    := ApiGet(Format('/exchanges?per_page=%s&page=%d', [Per, P.Page]), P.ApiKey);
  Result := ParseResponse(Raw);
end;

function TCoinGeckoTool.DoCategories(const P: TCoinGeckoParams): TJSONObject;
var
  Raw: string;
begin
  Raw    := ApiGet('/coins/categories/list', P.ApiKey);
  Result := ParseResponse(Raw);
end;

function TCoinGeckoTool.ExecuteWithParams(const AParams: TCoinGeckoParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'price'        then R := DoPrice(AParams)
    else if Op = 'markets'      then R := DoMarkets(AParams)
    else if Op = 'coin_info'    then R := DoCoinInfo(AParams)
    else if Op = 'market_chart' then R := DoMarketChart(AParams)
    else if Op = 'trending'     then R := DoTrending(AParams)
    else if Op = 'search'       then R := DoSearch(AParams)
    else if Op = 'global'       then R := DoGlobal(AParams)
    else if Op = 'exchanges'    then R := DoExchanges(AParams)
    else if Op = 'categories'   then R := DoCategories(AParams)
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

constructor TCoinGeckoTool.Create;
begin
  inherited;
  FName        := 'mcp-coingecko';
  FDescription :=
    'Cryptocurrency data via CoinGecko API v3 (free, no key required for basic use). ' +
    'Operations: price (params: coinIds, currency?), ' +
    'markets (params: currency?, order?, perPage?, page?, category?, sparkline?), ' +
    'coin_info (params: coinId), ' +
    'market_chart (params: coinId, currency?, days? [1/7/14/30/90/180/365/max]), ' +
    'trending, search (params: query), global, ' +
    'exchanges (params: perPage?, page?), categories. ' +
    'Optional apiKey for CoinGecko Pro (higher rate limits).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-coingecko',
    function: IAiMCPTool
    begin
      Result := TCoinGeckoTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-coingecko');
end;

end.
