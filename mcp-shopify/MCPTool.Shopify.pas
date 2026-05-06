unit MCPTool.Shopify;

{
  MCPTool.Shopify  ·  mcp-shopify  (port 8632)
  Shopify Admin REST API 2024-01.

  Operations:
    list_products    - list products
    get_product      - get product by id
    create_product   - create a product
    update_product   - update a product
    delete_product   - delete a product
    list_orders      - list orders
    get_order        - get order by id
    list_customers   - list customers
    get_customer     - get customer by id
    update_inventory - set inventory level for a variant
    list_collections - list custom collections
    list_variants    - list variants for a product
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TShopifyParams = class
  private
    FOperation  : string;
    FShop       : string;
    FAccessToken: string;
    FProductId  : string;
    FOrderId    : string;
    FCustomerId : string;
    FVariantId  : string;
    FLocationId : string;
    FQuantity   : Integer;
    FLimit      : Integer;
    FStatus     : string;
    FBody       : string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_products, get_product, create_product, update_product, delete_product, list_orders, get_order, list_customers, get_customer, update_inventory, list_collections, list_variants')]
    property Operation  : string  read FOperation   write FOperation;

    [AiMCPSchemaDescription('Shopify store domain e.g. mystore.myshopify.com')]
    property Shop       : string  read FShop        write FShop;

    [AiMCPSchemaDescription('Shopify Admin API access token')]
    property AccessToken: string  read FAccessToken  write FAccessToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Product ID')]
    property ProductId  : string  read FProductId   write FProductId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Order ID')]
    property OrderId    : string  read FOrderId     write FOrderId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Customer ID')]
    property CustomerId : string  read FCustomerId  write FCustomerId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Variant ID (for update_inventory, list_variants)')]
    property VariantId  : string  read FVariantId   write FVariantId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Location ID (for update_inventory)')]
    property LocationId : string  read FLocationId  write FLocationId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Inventory quantity (for update_inventory)')]
    property Quantity   : Integer read FQuantity    write FQuantity;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max results to return (default 50)')]
    property Limit      : Integer read FLimit       write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Order status filter: open, closed, cancelled, any (for list_orders)')]
    property Status     : string  read FStatus      write FStatus;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON body for create/update operations')]
    property Body       : string  read FBody        write FBody;
  end;

  TShopifyTool = class(TAiMCPToolBase<TShopifyParams>)
  private
    function BaseURL(const Shop: string): string;
    function ApiGet(const URL, Token: string): TJSONObject;
    function ApiPost(const URL, Token, Body: string): TJSONObject;
    function ApiPut(const URL, Token, Body: string): TJSONObject;
    function ApiDelete(const URL, Token: string): TJSONObject;

    function DoListProducts(const P: TShopifyParams): TJSONObject;
    function DoGetProduct(const P: TShopifyParams): TJSONObject;
    function DoCreateProduct(const P: TShopifyParams): TJSONObject;
    function DoUpdateProduct(const P: TShopifyParams): TJSONObject;
    function DoDeleteProduct(const P: TShopifyParams): TJSONObject;
    function DoListOrders(const P: TShopifyParams): TJSONObject;
    function DoGetOrder(const P: TShopifyParams): TJSONObject;
    function DoListCustomers(const P: TShopifyParams): TJSONObject;
    function DoGetCustomer(const P: TShopifyParams): TJSONObject;
    function DoUpdateInventory(const P: TShopifyParams): TJSONObject;
    function DoListCollections(const P: TShopifyParams): TJSONObject;
    function DoListVariants(const P: TShopifyParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TShopifyParams;
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

{ TShopifyParams }

constructor TShopifyParams.Create;
begin
  inherited;
  FLimit    := 50;
  FQuantity := 0;
  FStatus   := 'any';
end;

{ TShopifyTool }

constructor TShopifyTool.Create;
begin
  inherited;
  FName        := 'mcp-shopify';
  FDescription :=
    'Shopify Admin REST API 2024-01 — products, orders, customers, inventory. ' +
    'Operations: list_products, get_product (productId), create_product (body), ' +
    'update_product (productId, body), delete_product (productId), ' +
    'list_orders (status?, limit?), get_order (orderId), ' +
    'list_customers (limit?), get_customer (customerId), ' +
    'update_inventory (variantId, locationId, quantity), ' +
    'list_collections, list_variants (productId). ' +
    'Auth: shop (mystore.myshopify.com), accessToken.';
end;

function TShopifyTool.BaseURL(const Shop: string): string;
begin
  Result := 'https://' + Trim(Shop) + '/admin/api/2024-01';
end;

function TShopifyTool.ApiGet(const URL, Token: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp := HTTP.Get(URL, nil,
      [TNameValuePair.Create('X-Shopify-Access-Token', Token),
       TNameValuePair.Create('Accept', 'application/json')]);
    Result := TJSONObject.ParseJSONValue(Resp.ContentAsString()) as TJSONObject;
    if Result = nil then Result := TJSONObject.Create;
  finally
    HTTP.Free;
  end;
end;

function TShopifyTool.ApiPost(const URL, Token, Body: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Strm: TStringStream;
begin
  HTTP := THTTPClient.Create;
  Strm := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Post(URL, Strm, nil,
      [TNameValuePair.Create('X-Shopify-Access-Token', Token),
       TNameValuePair.Create('Content-Type', 'application/json'),
       TNameValuePair.Create('Accept', 'application/json')]);
    Result := TJSONObject.ParseJSONValue(Resp.ContentAsString()) as TJSONObject;
    if Result = nil then Result := TJSONObject.Create;
  finally
    Strm.Free;
    HTTP.Free;
  end;
end;

function TShopifyTool.ApiPut(const URL, Token, Body: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Strm: TStringStream;
begin
  HTTP := THTTPClient.Create;
  Strm := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Put(URL, Strm, nil,
      [TNameValuePair.Create('X-Shopify-Access-Token', Token),
       TNameValuePair.Create('Content-Type', 'application/json'),
       TNameValuePair.Create('Accept', 'application/json')]);
    Result := TJSONObject.ParseJSONValue(Resp.ContentAsString()) as TJSONObject;
    if Result = nil then Result := TJSONObject.Create;
  finally
    Strm.Free;
    HTTP.Free;
  end;
end;

function TShopifyTool.ApiDelete(const URL, Token: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp := HTTP.Delete(URL, nil,
      [TNameValuePair.Create('X-Shopify-Access-Token', Token)]);
    Result := TJSONObject.Create;
    Result.AddPair('status', IntToStr(Resp.StatusCode));
    Result.AddPair('ok', TJSONBool.Create(Resp.StatusCode < 300));
  finally
    HTTP.Free;
  end;
end;

function TShopifyTool.DoListProducts(const P: TShopifyParams): TJSONObject;
var
  Lim: Integer;
begin
  Lim := P.Limit; if Lim <= 0 then Lim := 50;
  Result := ApiGet(
    Format('%s/products.json?limit=%d', [BaseURL(P.Shop), Lim]),
    P.AccessToken);
end;

function TShopifyTool.DoGetProduct(const P: TShopifyParams): TJSONObject;
begin
  if Trim(P.ProductId) = '' then raise Exception.Create('"productId" required');
  Result := ApiGet(
    Format('%s/products/%s.json', [BaseURL(P.Shop), Trim(P.ProductId)]),
    P.AccessToken);
end;

function TShopifyTool.DoCreateProduct(const P: TShopifyParams): TJSONObject;
begin
  if Trim(P.Body) = '' then raise Exception.Create('"body" required');
  Result := ApiPost(
    BaseURL(P.Shop) + '/products.json',
    P.AccessToken, Trim(P.Body));
end;

function TShopifyTool.DoUpdateProduct(const P: TShopifyParams): TJSONObject;
begin
  if Trim(P.ProductId) = '' then raise Exception.Create('"productId" required');
  if Trim(P.Body)      = '' then raise Exception.Create('"body" required');
  Result := ApiPut(
    Format('%s/products/%s.json', [BaseURL(P.Shop), Trim(P.ProductId)]),
    P.AccessToken, Trim(P.Body));
end;

function TShopifyTool.DoDeleteProduct(const P: TShopifyParams): TJSONObject;
begin
  if Trim(P.ProductId) = '' then raise Exception.Create('"productId" required');
  Result := ApiDelete(
    Format('%s/products/%s.json', [BaseURL(P.Shop), Trim(P.ProductId)]),
    P.AccessToken);
end;

function TShopifyTool.DoListOrders(const P: TShopifyParams): TJSONObject;
var
  Lim: Integer;
  St: string;
begin
  Lim := P.Limit;  if Lim <= 0 then Lim := 50;
  St  := Trim(P.Status); if St = '' then St := 'any';
  Result := ApiGet(
    Format('%s/orders.json?limit=%d&status=%s', [BaseURL(P.Shop), Lim, St]),
    P.AccessToken);
end;

function TShopifyTool.DoGetOrder(const P: TShopifyParams): TJSONObject;
begin
  if Trim(P.OrderId) = '' then raise Exception.Create('"orderId" required');
  Result := ApiGet(
    Format('%s/orders/%s.json', [BaseURL(P.Shop), Trim(P.OrderId)]),
    P.AccessToken);
end;

function TShopifyTool.DoListCustomers(const P: TShopifyParams): TJSONObject;
var
  Lim: Integer;
begin
  Lim := P.Limit; if Lim <= 0 then Lim := 50;
  Result := ApiGet(
    Format('%s/customers.json?limit=%d', [BaseURL(P.Shop), Lim]),
    P.AccessToken);
end;

function TShopifyTool.DoGetCustomer(const P: TShopifyParams): TJSONObject;
begin
  if Trim(P.CustomerId) = '' then raise Exception.Create('"customerId" required');
  Result := ApiGet(
    Format('%s/customers/%s.json', [BaseURL(P.Shop), Trim(P.CustomerId)]),
    P.AccessToken);
end;

function TShopifyTool.DoUpdateInventory(const P: TShopifyParams): TJSONObject;
var
  Variant, InvItemId: string;
  VResp: TJSONObject;
  InvItemVal: TJSONValue;
  Body: string;
begin
  if Trim(P.VariantId)  = '' then raise Exception.Create('"variantId" required');
  if Trim(P.LocationId) = '' then raise Exception.Create('"locationId" required');

  // Step 1: get inventory_item_id from variant
  VResp := ApiGet(
    Format('%s/variants/%s.json', [BaseURL(P.Shop), Trim(P.VariantId)]),
    P.AccessToken);
  InvItemId := '';
  try
    var VarObj := VResp.GetValue('variant') as TJSONObject;
    if VarObj <> nil then
    begin
      InvItemVal := VarObj.GetValue('inventory_item_id');
      if InvItemVal <> nil then InvItemId := InvItemVal.Value;
    end;
  finally
    VResp.Free;
  end;
  if InvItemId = '' then raise Exception.Create('Could not retrieve inventory_item_id for variant');

  // Step 2: set inventory level
  Body := Format('{"location_id":%s,"inventory_item_id":%s,"available":%d}',
    [Trim(P.LocationId), InvItemId, P.Quantity]);
  Result := ApiPost(
    BaseURL(P.Shop) + '/inventory_levels/set.json',
    P.AccessToken, Body);
end;

function TShopifyTool.DoListCollections(const P: TShopifyParams): TJSONObject;
var
  Lim: Integer;
begin
  Lim := P.Limit; if Lim <= 0 then Lim := 50;
  Result := ApiGet(
    Format('%s/custom_collections.json?limit=%d', [BaseURL(P.Shop), Lim]),
    P.AccessToken);
end;

function TShopifyTool.DoListVariants(const P: TShopifyParams): TJSONObject;
begin
  if Trim(P.ProductId) = '' then raise Exception.Create('"productId" required');
  Result := ApiGet(
    Format('%s/products/%s/variants.json', [BaseURL(P.Shop), Trim(P.ProductId)]),
    P.AccessToken);
end;

function TShopifyTool.ExecuteWithParams(const AParams: TShopifyParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');
    if Trim(AParams.Shop)        = '' then raise Exception.Create('"shop" required');
    if Trim(AParams.AccessToken) = '' then raise Exception.Create('"accessToken" required');

    if      Op = 'list_products'    then R := DoListProducts(AParams)
    else if Op = 'get_product'      then R := DoGetProduct(AParams)
    else if Op = 'create_product'   then R := DoCreateProduct(AParams)
    else if Op = 'update_product'   then R := DoUpdateProduct(AParams)
    else if Op = 'delete_product'   then R := DoDeleteProduct(AParams)
    else if Op = 'list_orders'      then R := DoListOrders(AParams)
    else if Op = 'get_order'        then R := DoGetOrder(AParams)
    else if Op = 'list_customers'   then R := DoListCustomers(AParams)
    else if Op = 'get_customer'     then R := DoGetCustomer(AParams)
    else if Op = 'update_inventory' then R := DoUpdateInventory(AParams)
    else if Op = 'list_collections' then R := DoListCollections(AParams)
    else if Op = 'list_variants'    then R := DoListVariants(AParams)
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

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-shopify',
    function: IAiMCPTool
    begin
      Result := TShopifyTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-shopify');
end;

end.
