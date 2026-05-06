unit MCPTool.RSS;

{
  MCPTool.RSS  ·  mcp-rss

  RSS 2.0 and Atom feed reader using Delphi native XML + TNetHTTPClient.
  No external dependencies.

  Operations:
    fetch   - download and parse a feed, return items list.
    latest  - return only the N most recent items.
    search  - filter items whose title/description contains a keyword.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient,
  Xml.XMLDoc,
  Xml.XMLIntf,
  System.Math;

type

  TRSSParams = class
  private
    FOperation: string;
    FUrl:       string;
    FCount:     Integer;
    FKeyword:   string;
    FTimeout:   Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: fetch, latest, search')]
    property Operation: string  read FOperation write FOperation;

    [AiMCPSchemaDescription('Feed URL (RSS 2.0 or Atom)')]
    property Url:       string  read FUrl       write FUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('latest: max items to return (default 10)')]
    property Count:     Integer read FCount     write FCount;

    [AiMCPOptional]
    [AiMCPSchemaDescription('search: keyword to filter in title or description')]
    property Keyword:   string  read FKeyword   write FKeyword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('HTTP timeout in milliseconds (default 10000)')]
    property Timeout:   Integer read FTimeout   write FTimeout;
  end;

  TRSSTool = class(TAiMCPToolBase<TRSSParams>)
  private
    function DownloadFeed(const Url: string; Timeout: Integer): string;
    function NodeText(const Node: IXMLNode; const TagName: string): string;
    function ParseFeed(const Xml: string): TJSONArray;
    function DoFetch(const P: TRSSParams): TJSONObject;
    function DoLatest(const P: TRSSParams): TJSONObject;
    function DoSearch(const P: TRSSParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TRSSParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ TRSSParams }

constructor TRSSParams.Create;
begin
  inherited;
  FCount   := 10;
  FTimeout := 10000;
end;

{ TRSSTool }

function TRSSTool.DownloadFeed(const Url: string; Timeout: Integer): string;
var
  Client: THTTPClient;
  Resp:   IHTTPResponse;
begin
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := Timeout;
    Client.ResponseTimeout   := Timeout;
    Client.HandleRedirects   := True;
    Client.MaxRedirects      := 5;
    Resp   := Client.Get(Url);
    Result := Resp.ContentAsString;
  finally
    Client.Free;
  end;
end;

function TRSSTool.NodeText(const Node: IXMLNode; const TagName: string): string;
var
  Child: IXMLNode;
begin
  Result := '';
  if Node = nil then Exit;
  Child := Node.ChildNodes.FindNode(TagName);
  if Child <> nil then
  begin
    if Child.IsTextElement then
      Result := Trim(Child.Text)
    else if Child.ChildNodes.Count > 0 then
      Result := Trim(Child.ChildNodes[0].Text);
  end;
end;

function TRSSTool.ParseFeed(const Xml: string): TJSONArray;
var
  Doc:      IXMLDocument;
  Root:     IXMLNode;
  Channel:  IXMLNode;
  ItemNode: IXMLNode;
  Item:     TJSONObject;
  i:        Integer;
  IsAtom:   Boolean;
  Title:    string;
  Link:     string;
  Desc:     string;
  PubDate:  string;
  Author:   string;
begin
  Result := TJSONArray.Create;

  Doc := TXMLDocument.Create(nil);
  Doc.Active := False;
  Doc.LoadFromXML(Xml);
  Doc.Active := True;

  Root    := Doc.DocumentElement;
  IsAtom  := SameText(Root.LocalName, 'feed');

  if IsAtom then
  begin
    // Atom feed: root is <feed>, items are <entry>
    for i := 0 to Root.ChildNodes.Count - 1 do
    begin
      ItemNode := Root.ChildNodes[i];
      if not SameText(ItemNode.LocalName, 'entry') then Continue;

      Title   := NodeText(ItemNode, 'title');
      Desc    := NodeText(ItemNode, 'summary');
      if Desc = '' then
        Desc  := NodeText(ItemNode, 'content');
      PubDate := NodeText(ItemNode, 'updated');
      if PubDate = '' then
        PubDate := NodeText(ItemNode, 'published');
      Author  := '';
      var AuthorNode := ItemNode.ChildNodes.FindNode('author');
      if AuthorNode <> nil then
        Author := NodeText(AuthorNode, 'name');

      // <link href="..."/> or <link>url</link>
      Link := '';
      var LinkNode := ItemNode.ChildNodes.FindNode('link');
      if LinkNode <> nil then
      begin
        if LinkNode.HasAttribute('href') then
          Link := LinkNode.Attributes['href']
        else
          Link := Trim(LinkNode.Text);
      end;

      Item := TJSONObject.Create;
      Item.AddPair('title',   Title);
      Item.AddPair('link',    Link);
      Item.AddPair('desc',    Desc.Substring(0, Min(500, Length(Desc))));
      Item.AddPair('pubdate', PubDate);
      Item.AddPair('author',  Author);
      Result.Add(Item);
    end;
  end
  else
  begin
    // RSS 2.0: root is <rss>, items are inside <channel><item>
    Channel := nil;
    for i := 0 to Root.ChildNodes.Count - 1 do
    begin
      if SameText(Root.ChildNodes[i].LocalName, 'channel') then
      begin
        Channel := Root.ChildNodes[i];
        Break;
      end;
    end;

    if Channel = nil then Exit;

    for i := 0 to Channel.ChildNodes.Count - 1 do
    begin
      ItemNode := Channel.ChildNodes[i];
      if not SameText(ItemNode.LocalName, 'item') then Continue;

      Title   := NodeText(ItemNode, 'title');
      Link    := NodeText(ItemNode, 'link');
      Desc    := NodeText(ItemNode, 'description');
      PubDate := NodeText(ItemNode, 'pubDate');
      if PubDate = '' then
        PubDate := NodeText(ItemNode, 'dc:date');
      Author  := NodeText(ItemNode, 'author');
      if Author = '' then
        Author := NodeText(ItemNode, 'dc:creator');

      Item := TJSONObject.Create;
      Item.AddPair('title',   Title);
      Item.AddPair('link',    Link);
      Item.AddPair('desc',    Desc.Substring(0, Min(500, Length(Desc))));
      Item.AddPair('pubdate', PubDate);
      Item.AddPair('author',  Author);
      Result.Add(Item);
    end;
  end;
end;

function TRSSTool.DoFetch(const P: TRSSParams): TJSONObject;
var
  Xml:   string;
  Items: TJSONArray;
begin
  if P.Url = '' then raise Exception.Create('"url" is required');
  Xml   := DownloadFeed(P.Url, P.Timeout);
  Items := ParseFeed(Xml);

  Result := TJSONObject.Create;
  Result.AddPair('url',   P.Url);
  Result.AddPair('count', TJSONNumber.Create(Items.Count));
  Result.AddPair('items', Items);
  Result.AddPair('ok',    TJSONTrue.Create);
end;

function TRSSTool.DoLatest(const P: TRSSParams): TJSONObject;
var
  Xml:    string;
  All:    TJSONArray;
  Items:  TJSONArray;
  Limit:  Integer;
  i:      Integer;
begin
  if P.Url = '' then raise Exception.Create('"url" is required');
  Xml   := DownloadFeed(P.Url, P.Timeout);
  All   := ParseFeed(Xml);
  try
    Limit := P.Count;
    if Limit <= 0 then Limit := 10;
    if Limit > All.Count then Limit := All.Count;

    Items := TJSONArray.Create;
    for i := 0 to Limit - 1 do
      Items.AddElement(All.Items[i].Clone as TJSONValue);
  finally
    All.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('url',   P.Url);
  Result.AddPair('count', TJSONNumber.Create(Items.Count));
  Result.AddPair('items', Items);
  Result.AddPair('ok',    TJSONTrue.Create);
end;

function TRSSTool.DoSearch(const P: TRSSParams): TJSONObject;
var
  Xml:     string;
  All:     TJSONArray;
  Items:   TJSONArray;
  i:       Integer;
  Item:    TJSONObject;
  KW:      string;
  Title:   string;
  Desc:    string;
begin
  if P.Url     = '' then raise Exception.Create('"url" is required');
  if P.Keyword = '' then raise Exception.Create('"keyword" is required for search');

  Xml := DownloadFeed(P.Url, P.Timeout);
  All := ParseFeed(Xml);
  try
    KW    := LowerCase(P.Keyword);
    Items := TJSONArray.Create;
    for i := 0 to All.Count - 1 do
    begin
      Item  := All.Items[i] as TJSONObject;
      Title := LowerCase(Item.GetValue<string>('title', ''));
      Desc  := LowerCase(Item.GetValue<string>('desc',  ''));
      if Title.Contains(KW) or Desc.Contains(KW) then
        Items.AddElement(Item.Clone as TJSONValue);
    end;
  finally
    All.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('url',     P.Url);
  Result.AddPair('keyword', P.Keyword);
  Result.AddPair('count',   TJSONNumber.Create(Items.Count));
  Result.AddPair('items',   Items);
  Result.AddPair('ok',      TJSONTrue.Create);
end;

function TRSSTool.ExecuteWithParams(const AParams: TRSSParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'fetch'  then R := DoFetch(AParams)
    else if Op = 'latest' then R := DoLatest(AParams)
    else if Op = 'search' then R := DoSearch(AParams)
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

constructor TRSSTool.Create;
begin
  inherited;
  FName        := 'mcp-rss';
  FDescription :=
    'RSS 2.0 and Atom feed reader. ' +
    'Operations: ' +
    'fetch (download and parse all items from a feed URL), ' +
    'latest (return only the N most recent items; param: count), ' +
    'search (filter items by keyword in title or description; param: keyword).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-rss',
    function: IAiMCPTool
    begin
      Result := TRSSTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-rss] ready');
end;

end.
