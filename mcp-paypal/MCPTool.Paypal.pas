unit MCPTool.Paypal;

{
  MCPTool.Paypal  ·  mcp-paypal  (port 8625)
  PayPal REST API v2 — orders, payments, payouts, invoices, subscriptions.

  Operations:
    get_token       - get OAuth2 access token (cached per call)
    create_order    - create payment order
    get_order       - get order details
    capture_order   - capture authorized order
    create_payout   - send mass payouts
    get_payout      - get payout batch status
    list_invoices   - list invoices
    create_invoice  - create invoice draft
    send_invoice    - send invoice to recipient
    get_invoice     - get invoice details
    list_subs       - list subscriptions
    get_sub         - get subscription details
    cancel_sub      - cancel subscription
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TPaypalParams = class
  private
    FOperation:   string;
    FClientId:    string;
    FSecret:      string;
    FSandbox:     Boolean;
    FOrderId:     string;
    FAmount:      string;
    FCurrency:    string;
    FDescription: string;
    FReturnUrl:   string;
    FCancelUrl:   string;
    FPayoutItems: string;
    FBatchId:     string;
    FInvoiceId:   string;
    FRecipient:   string;
    FSubId:       string;
    FBody:        string;
    FPageSize:    Integer;
    FPage:        Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: get_token, create_order, get_order, capture_order, create_payout, get_payout, list_invoices, create_invoice, send_invoice, get_invoice, list_subs, get_sub, cancel_sub')]
    property Operation:   string  read FOperation   write FOperation;

    [AiMCPSchemaDescription('PayPal app Client ID (from developer.paypal.com)')]
    property ClientId:    string  read FClientId    write FClientId;

    [AiMCPSchemaDescription('PayPal app Client Secret')]
    property Secret:      string  read FSecret      write FSecret;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Use sandbox environment (default: false = live)')]
    property Sandbox:     Boolean read FSandbox     write FSandbox;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Order/transaction ID for get_order, capture_order')]
    property OrderId:     string  read FOrderId     write FOrderId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Amount value as string (e.g. "10.00") for create_order')]
    property Amount:      string  read FAmount      write FAmount;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Currency code (default: USD) for create_order')]
    property Currency:    string  read FCurrency    write FCurrency;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Description/reference for order or payout')]
    property Description: string  read FDescription write FDescription;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Return URL after PayPal approval (for create_order)')]
    property ReturnUrl:   string  read FReturnUrl   write FReturnUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Cancel URL if buyer cancels (for create_order)')]
    property CancelUrl:   string  read FCancelUrl   write FCancelUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Payout items as JSON array: [{"recipient_type":"EMAIL","receiver":"x@y.com","amount":{"value":"10","currency":"USD"},"note":"Thanks","sender_item_id":"1"}]')]
    property PayoutItems: string  read FPayoutItems write FPayoutItems;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Payout batch ID for get_payout')]
    property BatchId:     string  read FBatchId     write FBatchId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Invoice ID for get_invoice, send_invoice')]
    property InvoiceId:   string  read FInvoiceId   write FInvoiceId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Recipient email for create_invoice')]
    property Recipient:   string  read FRecipient   write FRecipient;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Subscription ID for get_sub, cancel_sub')]
    property SubId:       string  read FSubId       write FSubId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Raw JSON body to override auto-constructed body (advanced)')]
    property Body:        string  read FBody        write FBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Page size for list operations (default: 10)')]
    property PageSize:    Integer read FPageSize    write FPageSize;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Page number for list operations (default: 1)')]
    property Page:        Integer read FPage        write FPage;
  end;

  TPaypalTool = class(TAiMCPToolBase<TPaypalParams>)
  private
    function BaseURL(Sandbox: Boolean): string;
    function GetToken(const ClientId, Secret: string; Sandbox: Boolean): string;
    function ApiGet(const URL, Token: string): string;
    function ApiPost(const URL, Token, Body: string): string;
    function ApiDelete(const URL, Token: string): string;
    function Wrap(const Raw: string): TJSONObject;
    function DoGetToken(const P: TPaypalParams): TJSONObject;
    function DoCreateOrder(const P: TPaypalParams): TJSONObject;
    function DoGetOrder(const P: TPaypalParams): TJSONObject;
    function DoCaptureOrder(const P: TPaypalParams): TJSONObject;
    function DoCreatePayout(const P: TPaypalParams): TJSONObject;
    function DoGetPayout(const P: TPaypalParams): TJSONObject;
    function DoListInvoices(const P: TPaypalParams): TJSONObject;
    function DoCreateInvoice(const P: TPaypalParams): TJSONObject;
    function DoSendInvoice(const P: TPaypalParams): TJSONObject;
    function DoGetInvoice(const P: TPaypalParams): TJSONObject;
    function DoListSubs(const P: TPaypalParams): TJSONObject;
    function DoGetSub(const P: TPaypalParams): TJSONObject;
    function DoCancelSub(const P: TPaypalParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TPaypalParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.NetEncoding,
  System.Net.HttpClient,
  System.Net.URLClient;

{ TPaypalParams }

constructor TPaypalParams.Create;
begin
  inherited;
  FSandbox  := False;
  FCurrency := 'USD';
  FPageSize := 10;
  FPage     := 1;
end;

{ TPaypalTool }

function TPaypalTool.BaseURL(Sandbox: Boolean): string;
begin
  if Sandbox then
    Result := 'https://api-m.sandbox.paypal.com'
  else
    Result := 'https://api-m.paypal.com';
end;

function TPaypalTool.GetToken(const ClientId, Secret: string;
  Sandbox: Boolean): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
  Creds:  string;
  J:      TJSONValue;
begin
  Creds  := TNetEncoding.Base64.Encode(ClientId + ':' + Secret);
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create('grant_type=client_credentials', TEncoding.UTF8);
  try
    Resp := HTTP.Post(BaseURL(Sandbox) + '/v1/oauth2/token', Stream, nil,
      [TNameValuePair.Create('Authorization', 'Basic ' + Creds),
       TNameValuePair.Create('Content-Type', 'application/x-www-form-urlencoded')]);
    J := TJSONObject.ParseJSONValue(Resp.ContentAsString(TEncoding.UTF8));
    try
      if Assigned(J) then
        Result := (J as TJSONObject).GetValue<string>('access_token', '')
      else
        Result := '';
    finally
      J.Free;
    end;
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TPaypalTool.ApiGet(const URL, Token: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp   := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Token),
       TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TPaypalTool.ApiPost(const URL, Token, Body: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp   := HTTP.Post(URL, Stream, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Token),
       TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TPaypalTool.ApiDelete(const URL, Token: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp   := HTTP.Delete(URL, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Token),
       TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TPaypalTool.Wrap(const Raw: string): TJSONObject;
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
    if Raw <> '' then
      Result.AddPair('raw', TJSONString.Create(Raw));
  end;
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TPaypalTool.DoGetToken(const P: TPaypalParams): TJSONObject;
var
  Token: string;
begin
  Token  := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  Result := TJSONObject.Create;
  if Token <> '' then
  begin
    Result.AddPair('access_token', TJSONString.Create(Token));
    Result.AddPair('ok', TJSONTrue.Create);
  end
  else
  begin
    Result.AddPair('ok',    TJSONFalse.Create);
    Result.AddPair('error', TJSONString.Create('Failed to obtain access token'));
  end;
end;

function TPaypalTool.DoCreateOrder(const P: TPaypalParams): TJSONObject;
var
  Token, Cur, Amt, Desc, Body: string;
begin
  Token := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  if Token = '' then raise Exception.Create('Could not authenticate with PayPal');

  if Trim(P.Body) <> '' then
    Body := Trim(P.Body)
  else
  begin
    Amt  := Trim(P.Amount);   if Amt  = '' then raise Exception.Create('"amount" required for create_order');
    Cur  := Trim(P.Currency); if Cur  = '' then Cur := 'USD';
    Desc := Trim(P.Description);
    var Links := '';
    if Trim(P.ReturnUrl) <> '' then
      Links := Links + Format('{"href":"%s","rel":"return","method":"GET"},', [P.ReturnUrl]);
    if Trim(P.CancelUrl) <> '' then
      Links := Links + Format('{"href":"%s","rel":"cancel","method":"GET"},', [P.CancelUrl]);
    if Links <> '' then
      Links := Copy(Links, 1, Length(Links) - 1);
    var AppCtx := '';
    if Links <> '' then
      AppCtx := Format('"application_context":{"return_url":"%s","cancel_url":"%s"},',
        [Trim(P.ReturnUrl), Trim(P.CancelUrl)]);
    var DescPart := '';
    if Desc <> '' then DescPart := ',"description":"' + Desc + '"';
    Body := Format('{"intent":"CAPTURE",%s"purchase_units":[{"amount":{"currency_code":"%s","value":"%s"}%s}]}',
      [AppCtx, Cur, Amt, DescPart]);
  end;

  Result := Wrap(ApiPost(BaseURL(P.Sandbox) + '/v2/checkout/orders', Token, Body));
end;

function TPaypalTool.DoGetOrder(const P: TPaypalParams): TJSONObject;
var
  Token: string;
begin
  if Trim(P.OrderId) = '' then raise Exception.Create('"orderId" required for get_order');
  Token  := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  if Token = '' then raise Exception.Create('Could not authenticate with PayPal');
  Result := Wrap(ApiGet(BaseURL(P.Sandbox) + '/v2/checkout/orders/' + Trim(P.OrderId), Token));
end;

function TPaypalTool.DoCaptureOrder(const P: TPaypalParams): TJSONObject;
var
  Token: string;
begin
  if Trim(P.OrderId) = '' then raise Exception.Create('"orderId" required for capture_order');
  Token  := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  if Token = '' then raise Exception.Create('Could not authenticate with PayPal');
  Result := Wrap(ApiPost(BaseURL(P.Sandbox) + '/v2/checkout/orders/' + Trim(P.OrderId) + '/capture', Token, '{}'));
end;

function TPaypalTool.DoCreatePayout(const P: TPaypalParams): TJSONObject;
var
  Token, Items, Desc, Body: string;
begin
  Items := Trim(P.PayoutItems);
  if Items = '' then raise Exception.Create('"payoutItems" JSON array required for create_payout');
  Token := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  if Token = '' then raise Exception.Create('Could not authenticate with PayPal');
  Desc := Trim(P.Description); if Desc = '' then Desc := 'Payout';
  Body := Format('{"sender_batch_header":{"sender_batch_id":"%s","email_subject":"%s"},"items":%s}',
    [FormatDateTime('yyyymmddhhnnsszzz', Now), Desc, Items]);
  Result := Wrap(ApiPost(BaseURL(P.Sandbox) + '/v1/payments/payouts', Token, Body));
end;

function TPaypalTool.DoGetPayout(const P: TPaypalParams): TJSONObject;
var
  Token: string;
begin
  if Trim(P.BatchId) = '' then raise Exception.Create('"batchId" required for get_payout');
  Token  := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  if Token = '' then raise Exception.Create('Could not authenticate with PayPal');
  Result := Wrap(ApiGet(BaseURL(P.Sandbox) + '/v1/payments/payouts/' + Trim(P.BatchId), Token));
end;

function TPaypalTool.DoListInvoices(const P: TPaypalParams): TJSONObject;
var
  Token: string;
  PS, Pg: Integer;
begin
  Token := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  if Token = '' then raise Exception.Create('Could not authenticate with PayPal');
  PS := P.PageSize; if PS <= 0 then PS := 10;
  Pg := P.Page;     if Pg <= 0 then Pg := 1;
  Result := Wrap(ApiGet(
    Format('%s/v2/invoicing/invoices?page_size=%d&page=%d', [BaseURL(P.Sandbox), PS, Pg]), Token));
end;

function TPaypalTool.DoCreateInvoice(const P: TPaypalParams): TJSONObject;
var
  Token, Recipient, Body: string;
begin
  Token     := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  if Token = '' then raise Exception.Create('Could not authenticate with PayPal');
  Recipient := Trim(P.Recipient);
  if Recipient = '' then raise Exception.Create('"recipient" email required for create_invoice');
  if Trim(P.Body) <> '' then
    Body := Trim(P.Body)
  else
    Body := Format('{"detail":{"currency_code":"%s"},"primary_recipients":[{"billing_info":{"email_address":"%s"}}]}',
      [Trim(P.Currency), Recipient]);
  Result := Wrap(ApiPost(BaseURL(P.Sandbox) + '/v2/invoicing/invoices', Token, Body));
end;

function TPaypalTool.DoSendInvoice(const P: TPaypalParams): TJSONObject;
var
  Token: string;
begin
  if Trim(P.InvoiceId) = '' then raise Exception.Create('"invoiceId" required for send_invoice');
  Token  := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  if Token = '' then raise Exception.Create('Could not authenticate with PayPal');
  Result := Wrap(ApiPost(BaseURL(P.Sandbox) + '/v2/invoicing/invoices/' + Trim(P.InvoiceId) + '/send', Token, '{}'));
end;

function TPaypalTool.DoGetInvoice(const P: TPaypalParams): TJSONObject;
var
  Token: string;
begin
  if Trim(P.InvoiceId) = '' then raise Exception.Create('"invoiceId" required for get_invoice');
  Token  := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  if Token = '' then raise Exception.Create('Could not authenticate with PayPal');
  Result := Wrap(ApiGet(BaseURL(P.Sandbox) + '/v2/invoicing/invoices/' + Trim(P.InvoiceId), Token));
end;

function TPaypalTool.DoListSubs(const P: TPaypalParams): TJSONObject;
var
  Token: string;
  PS, Pg: Integer;
begin
  Token := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  if Token = '' then raise Exception.Create('Could not authenticate with PayPal');
  PS := P.PageSize; if PS <= 0 then PS := 10;
  Pg := P.Page;     if Pg <= 0 then Pg := 1;
  Result := Wrap(ApiGet(
    Format('%s/v1/billing/subscriptions?page_size=%d&start_index=%d', [BaseURL(P.Sandbox), PS, (Pg - 1) * PS]), Token));
end;

function TPaypalTool.DoGetSub(const P: TPaypalParams): TJSONObject;
var
  Token: string;
begin
  if Trim(P.SubId) = '' then raise Exception.Create('"subId" required for get_sub');
  Token  := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  if Token = '' then raise Exception.Create('Could not authenticate with PayPal');
  Result := Wrap(ApiGet(BaseURL(P.Sandbox) + '/v1/billing/subscriptions/' + Trim(P.SubId), Token));
end;

function TPaypalTool.DoCancelSub(const P: TPaypalParams): TJSONObject;
var
  Token, Reason: string;
begin
  if Trim(P.SubId) = '' then raise Exception.Create('"subId" required for cancel_sub');
  Token  := GetToken(Trim(P.ClientId), Trim(P.Secret), P.Sandbox);
  if Token = '' then raise Exception.Create('Could not authenticate with PayPal');
  Reason := Trim(P.Description); if Reason = '' then Reason := 'Cancelled by user';
  Result := Wrap(ApiPost(BaseURL(P.Sandbox) + '/v1/billing/subscriptions/' + Trim(P.SubId) + '/cancel',
    Token, Format('{"reason":"%s"}', [Reason.Replace('"','\"')])));
end;

function TPaypalTool.ExecuteWithParams(const AParams: TPaypalParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    if Trim(AParams.ClientId) = '' then raise Exception.Create('"clientId" is required');
    if Trim(AParams.Secret)   = '' then raise Exception.Create('"secret" is required');
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'get_token'      then R := DoGetToken(AParams)
    else if Op = 'create_order'   then R := DoCreateOrder(AParams)
    else if Op = 'get_order'      then R := DoGetOrder(AParams)
    else if Op = 'capture_order'  then R := DoCaptureOrder(AParams)
    else if Op = 'create_payout'  then R := DoCreatePayout(AParams)
    else if Op = 'get_payout'     then R := DoGetPayout(AParams)
    else if Op = 'list_invoices'  then R := DoListInvoices(AParams)
    else if Op = 'create_invoice' then R := DoCreateInvoice(AParams)
    else if Op = 'send_invoice'   then R := DoSendInvoice(AParams)
    else if Op = 'get_invoice'    then R := DoGetInvoice(AParams)
    else if Op = 'list_subs'      then R := DoListSubs(AParams)
    else if Op = 'get_sub'        then R := DoGetSub(AParams)
    else if Op = 'cancel_sub'     then R := DoCancelSub(AParams)
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

constructor TPaypalTool.Create;
begin
  inherited;
  FName        := 'mcp-paypal';
  FDescription :=
    'PayPal REST API v2 integration. Requires clientId and secret from developer.paypal.com. ' +
    'Operations: get_token → OAuth2 token, ' +
    'create_order (params: amount, currency?, description?, returnUrl?, cancelUrl?) → checkout order, ' +
    'get_order (params: orderId), ' +
    'capture_order (params: orderId) → complete payment, ' +
    'create_payout (params: payoutItems=JSON array, description?) → mass payouts, ' +
    'get_payout (params: batchId) → payout status, ' +
    'list_invoices (params: pageSize?, page?), ' +
    'create_invoice (params: recipient, currency?, body?), ' +
    'send_invoice (params: invoiceId), ' +
    'get_invoice (params: invoiceId), ' +
    'list_subs (params: pageSize?, page?) → subscriptions, ' +
    'get_sub (params: subId), ' +
    'cancel_sub (params: subId, description?). ' +
    'sandbox=true uses sandbox.paypal.com for testing.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-paypal',
    function: IAiMCPTool
    begin
      Result := TPaypalTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-paypal');
end;

end.
