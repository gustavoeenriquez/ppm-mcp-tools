// Nombre: Gustavo Enríquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit MCPTool.Telegram;

{
  MCPTool.Telegram
  MCP tool: mcp-telegram

  Uses FastTelega library (E:\Delphi\Delphi13\Compo\FMXCompo\FastTelega\Source)
  for the full Telegram Bot API stack.

  Requires a Telegram Bot token from @BotFather.
  Token can be passed in "token" or set in TELEGRAM_BOT_TOKEN env var.

  Operations:
    me       - get bot profile info (getMe)
    send     - send a text message
    photo    - send a photo by public URL, file_id, or local file path
    audio    - send an audio file from local path
    video    - send a video file from local path
    document - send any file as a document from local path
    file     - auto-detect type and send photo/audio/video/document
    updates  - get recent incoming updates (getUpdates)
    delete   - delete a message

  IMPORTANT: TftBot is kept as a global per-token instance.
  Creating/destroying TftBot per-call causes "Invalid pointer operation"
  because the destructor frees internal state still referenced by returned objects.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.IOUtils,
  fastTelega.Bot,
  fastTelega.API,
  fastTelega.AvailableTypes;

type

  TTelegramParams = class
  private
    FOperation: string;
    FToken:     string;
    FChatId:    string;
    FText:      string;
    FParseMode: string;
    FMessageId: Integer;
    FPhotoUrl:  string;
    FCaption:   string;
    FLimit:     Integer;
    FOffset:    Integer;
    FPath:      string;
  public
    [AiMCPSchemaDescription(
      'Operation to perform. Required params per operation: ' +
      'me=none; ' +
      'send=chatId+text (parseMode optional, default HTML); ' +
      'photo=chatId + path (local file) or photoUrl (remote), caption optional; ' +
      'audio=chatId+path, caption optional; ' +
      'video=chatId+path, caption optional; ' +
      'document=chatId+path, caption optional; ' +
      'file=chatId+path, caption optional (auto-detects photo/audio/video/document by extension); ' +
      'updates=limit optional (default 10, max 100), offset optional; ' +
      'delete=chatId+messageId')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription(
      'Bot token from @BotFather (e.g. ''123456:ABC-DEF...''). ' +
      'OPTIONAL: omit or pass empty string to use TELEGRAM_BOT_TOKEN env var instead.')]
    property Token: string read FToken write FToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Target chat or user ID (required for send, photo, audio, video, document, file, delete)')]
    property ChatId: string read FChatId write FChatId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Message text for send. Supports HTML and Markdown.')]
    property Text: string read FText write FText;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Text parse mode: HTML (default), Markdown, MarkdownV2')]
    property ParseMode: string read FParseMode write FParseMode;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Message ID (required for delete)')]
    property MessageId: Integer read FMessageId write FMessageId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Public photo URL or file_id (for photo operation with remote source)')]
    property PhotoUrl: string read FPhotoUrl write FPhotoUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Caption for photo, audio, video, document or file')]
    property Caption: string read FCaption write FCaption;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum updates to fetch (default: 10, max: 100)')]
    property Limit: Integer read FLimit write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Update offset for pagination (marks prior updates as read)')]
    property Offset: Integer read FOffset write FOffset;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Local file path for audio, video, document, or file operations')]
    property Path: string read FPath write FPath;
  end;

  TTelegramTool = class(TAiMCPToolBase<TTelegramParams>)
  private
    function ResolveToken(const Param: string): string;
    function GetBot(const Token: string): TftBot;
    function GetMimeType(const FilePath: string): string;
    function DetectMediaType(const FilePath: string): string;
  protected
    function ExecuteWithParams(const AParams: TTelegramParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Global bot cache (one per token) ────────────────────────────────────────
// TftBot must NOT be created/destroyed per-call: its destructor frees internal
// state that is still referenced by objects returned from API methods.

var
  GBotToken: string  = '';
  GBot:      TftBot  = nil;

// ── Helpers ──────────────────────────────────────────────────────────────────

function TTelegramTool.ResolveToken(const Param: string): string;
begin
  Result := Trim(Param);
  if Result = '' then
    Result := GetEnvironmentVariable('TELEGRAM_BOT_TOKEN');
  if Result = '' then
    raise Exception.Create(
      'Bot token required: pass "token" or set TELEGRAM_BOT_TOKEN env var');
end;

function TTelegramTool.GetBot(const Token: string): TftBot;
begin
  if (GBot = nil) or (GBotToken <> Token) then
  begin
    FreeAndNil(GBot);
    GBot      := TftBot.Create(Token, 'https://api.telegram.org');
    GBotToken := Token;
  end;
  Result := GBot;
end;

function TTelegramTool.GetMimeType(const FilePath: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(TPath.GetExtension(FilePath));
  if      Ext = '.jpg'  then Result := 'image/jpeg'
  else if Ext = '.jpeg' then Result := 'image/jpeg'
  else if Ext = '.png'  then Result := 'image/png'
  else if Ext = '.gif'  then Result := 'image/gif'
  else if Ext = '.webp' then Result := 'image/webp'
  else if Ext = '.mp3'  then Result := 'audio/mpeg'
  else if Ext = '.ogg'  then Result := 'audio/ogg'
  else if Ext = '.wav'  then Result := 'audio/wav'
  else if Ext = '.mp4'  then Result := 'video/mp4'
  else if Ext = '.mov'  then Result := 'video/quicktime'
  else if Ext = '.avi'  then Result := 'video/x-msvideo'
  else if Ext = '.pdf'  then Result := 'application/pdf'
  else if Ext = '.docx' then Result := 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  else if Ext = '.xlsx' then Result := 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  else                       Result := 'application/octet-stream';
end;

// Returns 'photo', 'audio', 'video', or 'document'
function TTelegramTool.DetectMediaType(const FilePath: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(TPath.GetExtension(FilePath));
  if      Ext = '.jpg'  then Result := 'photo'
  else if Ext = '.jpeg' then Result := 'photo'
  else if Ext = '.png'  then Result := 'photo'
  else if Ext = '.gif'  then Result := 'photo'
  else if Ext = '.webp' then Result := 'photo'
  else if Ext = '.mp3'  then Result := 'audio'
  else if Ext = '.ogg'  then Result := 'audio'
  else if Ext = '.wav'  then Result := 'audio'
  else if Ext = '.mp4'  then Result := 'video'
  else if Ext = '.mov'  then Result := 'video'
  else if Ext = '.avi'  then Result := 'video'
  else                       Result := 'document';
end;

// ── Main execution ──────────────────────────────────────────────────────────

function TTelegramTool.ExecuteWithParams(const AParams: TTelegramParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:     string;
  Token:  string;
  Bot:    TftBot;
  R:      TJSONObject;
  ChatId: Integer;
begin
  try
    Op    := LowerCase(Trim(AParams.Operation));
    Token := ResolveToken(AParams.Token);
    Bot   := GetBot(Token);

    // ── me ─────────────────────────────────────────────────────────────
    if Op = 'me' then
    begin
      var Me := Bot.API.getMe;
      try
        R := TJSONObject.Create;
        R.AddPair('id',         TJSONNumber.Create(Me.Id));
        R.AddPair('username',   Me.UserName);
        R.AddPair('first_name', Me.FirstName);
        R.AddPair('is_bot',     TJSONBool.Create(Me.IsBot));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      finally
        Me.Free;
      end;
    end

    // ── send ───────────────────────────────────────────────────────────
    else if Op = 'send' then
    begin
      if AParams.ChatId = '' then raise Exception.Create('"chatId" is required');
      if AParams.Text   = '' then raise Exception.Create('"text" is required');
      ChatId := StrToIntDef(AParams.ChatId, 0);
      var PM := AParams.ParseMode;
      if PM = '' then PM := 'HTML';

      var Msg := Bot.API.sendMessage(ChatId, AParams.Text, False, 0, nil, PM);
      try
        if (Msg.MessageId = 0) and (Msg.Date = 0) then
          raise Exception.Create(
            'sendMessage returned empty result — possible causes: ' +
            'invalid token, bot blocked by user, wrong chatId, or network error');
        R := TJSONObject.Create;
        R.AddPair('ok',         TJSONBool.Create(True));
        R.AddPair('message_id', TJSONNumber.Create(Msg.MessageId));
        R.AddPair('chat_id',    AParams.ChatId);
        R.AddPair('text',       AParams.Text);
        R.AddPair('date',       TJSONNumber.Create(Msg.Date));
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      finally
        Msg.Free;
      end;
    end

    // ── photo ──────────────────────────────────────────────────────────
    else if Op = 'photo' then
    begin
      if AParams.ChatId = '' then raise Exception.Create('"chatId" is required');
      ChatId := StrToIntDef(AParams.ChatId, 0);

      var InputFile: TftInputFile := nil;
      if AParams.Path <> '' then
      begin
        if not TFile.Exists(AParams.Path) then
          raise Exception.CreateFmt('File not found: %s', [AParams.Path]);
        InputFile := TftInputFile.fromFile(AParams.Path, GetMimeType(AParams.Path));
      end
      else if AParams.PhotoUrl <> '' then
      begin
        InputFile := TftInputFile.Create;
        InputFile.Data := AParams.PhotoUrl;
      end
      else
        raise Exception.Create('"path" or "photoUrl" is required');

      try
        var Msg := Bot.API.sendPhoto(ChatId, InputFile, AParams.Caption);
        try
          R := TJSONObject.Create;
          R.AddPair('ok',         TJSONBool.Create(True));
          R.AddPair('message_id', TJSONNumber.Create(Msg.MessageId));
          R.AddPair('chat_id',    AParams.ChatId);
          R.AddPair('caption',    AParams.Caption);
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Msg.Free;
        end;
      finally
        InputFile.Free;
      end;
    end

    // ── audio ──────────────────────────────────────────────────────────
    else if Op = 'audio' then
    begin
      if AParams.ChatId = '' then raise Exception.Create('"chatId" is required');
      if AParams.Path   = '' then raise Exception.Create('"path" is required');
      if not TFile.Exists(AParams.Path) then
        raise Exception.CreateFmt('File not found: %s', [AParams.Path]);
      ChatId := StrToIntDef(AParams.ChatId, 0);

      Bot.API.sendChatAction(ChatId, 'upload_voice');
      var InputFile := TftInputFile.fromFile(AParams.Path, GetMimeType(AParams.Path));
      try
        var Msg := Bot.API.sendAudio(ChatId, InputFile, AParams.Caption);
        try
          R := TJSONObject.Create;
          R.AddPair('ok',         TJSONBool.Create(True));
          R.AddPair('message_id', TJSONNumber.Create(Msg.MessageId));
          R.AddPair('chat_id',    AParams.ChatId);
          R.AddPair('file',       TPath.GetFileName(AParams.Path));
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Msg.Free;
        end;
      finally
        InputFile.Free;
      end;
    end

    // ── video ──────────────────────────────────────────────────────────
    else if Op = 'video' then
    begin
      if AParams.ChatId = '' then raise Exception.Create('"chatId" is required');
      if AParams.Path   = '' then raise Exception.Create('"path" is required');
      if not TFile.Exists(AParams.Path) then
        raise Exception.CreateFmt('File not found: %s', [AParams.Path]);
      ChatId := StrToIntDef(AParams.ChatId, 0);

      Bot.API.sendChatAction(ChatId, 'upload_video');
      var InputFile := TftInputFile.fromFile(AParams.Path, GetMimeType(AParams.Path));
      try
        var Msg := Bot.API.sendVideo(ChatId, InputFile, 0, 0, 0, nil,
          AParams.Caption, 'HTML', True);
        try
          R := TJSONObject.Create;
          R.AddPair('ok',         TJSONBool.Create(True));
          R.AddPair('message_id', TJSONNumber.Create(Msg.MessageId));
          R.AddPair('chat_id',    AParams.ChatId);
          R.AddPair('file',       TPath.GetFileName(AParams.Path));
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Msg.Free;
        end;
      finally
        InputFile.Free;
      end;
    end

    // ── document ───────────────────────────────────────────────────────
    else if Op = 'document' then
    begin
      if AParams.ChatId = '' then raise Exception.Create('"chatId" is required');
      if AParams.Path   = '' then raise Exception.Create('"path" is required');
      if not TFile.Exists(AParams.Path) then
        raise Exception.CreateFmt('File not found: %s', [AParams.Path]);
      ChatId := StrToIntDef(AParams.ChatId, 0);

      Bot.API.sendChatAction(ChatId, 'upload_document');
      var InputFile := TftInputFile.fromFile(AParams.Path, GetMimeType(AParams.Path));
      try
        var Msg := Bot.API.sendDocument(ChatId, InputFile, nil, AParams.Caption);
        try
          R := TJSONObject.Create;
          R.AddPair('ok',         TJSONBool.Create(True));
          R.AddPair('message_id', TJSONNumber.Create(Msg.MessageId));
          R.AddPair('chat_id',    AParams.ChatId);
          R.AddPair('file',       TPath.GetFileName(AParams.Path));
          Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
          R.Free;
        finally
          Msg.Free;
        end;
      finally
        InputFile.Free;
      end;
    end

    // ── file (auto-detect type) ─────────────────────────────────────────
    else if Op = 'file' then
    begin
      if AParams.ChatId = '' then raise Exception.Create('"chatId" is required');
      if AParams.Path   = '' then raise Exception.Create('"path" is required');
      if not TFile.Exists(AParams.Path) then
        raise Exception.CreateFmt('File not found: %s', [AParams.Path]);
      ChatId := StrToIntDef(AParams.ChatId, 0);

      var MediaType := DetectMediaType(AParams.Path);
      var MsgId     := 0;

      var InputFile := TftInputFile.fromFile(AParams.Path, GetMimeType(AParams.Path));
      try
        if MediaType = 'photo' then
        begin
          var Msg := Bot.API.sendPhoto(ChatId, InputFile, AParams.Caption);
          try MsgId := Msg.MessageId; finally Msg.Free; end;
        end
        else if MediaType = 'audio' then
        begin
          Bot.API.sendChatAction(ChatId, 'upload_voice');
          var Msg := Bot.API.sendAudio(ChatId, InputFile, AParams.Caption);
          try MsgId := Msg.MessageId; finally Msg.Free; end;
        end
        else if MediaType = 'video' then
        begin
          Bot.API.sendChatAction(ChatId, 'upload_video');
          var Msg := Bot.API.sendVideo(ChatId, InputFile, 0, 0, 0, nil,
            AParams.Caption, 'HTML', True);
          try MsgId := Msg.MessageId; finally Msg.Free; end;
        end
        else
        begin
          Bot.API.sendChatAction(ChatId, 'upload_document');
          var Msg := Bot.API.sendDocument(ChatId, InputFile, nil, AParams.Caption);
          try MsgId := Msg.MessageId; finally Msg.Free; end;
        end;
      finally
        InputFile.Free;
      end;

      R := TJSONObject.Create;
      R.AddPair('ok',         TJSONBool.Create(True));
      R.AddPair('message_id', TJSONNumber.Create(MsgId));
      R.AddPair('chat_id',    AParams.ChatId);
      R.AddPair('file',       TPath.GetFileName(AParams.Path));
      R.AddPair('type',       MediaType);
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── updates ────────────────────────────────────────────────────────
    else if Op = 'updates' then
    begin
      var Lim := AParams.Limit;
      if Lim <= 0  then Lim := 10;
      if Lim > 100 then Lim := 100;

      var UpdList := Bot.API.getUpdates(AParams.Offset, Lim, 0);
      try
        var Items := TJSONArray.Create;
        for var i := 0 to UpdList.Count - 1 do
        begin
          var Upd  := TftUpdate(UpdList[i]);
          var Item := TJSONObject.Create;
          Item.AddPair('update_id', TJSONNumber.Create(Upd.UpdateId));
          if Assigned(Upd.Message) then
          begin
            Item.AddPair('message_id', TJSONNumber.Create(Upd.Message.MessageId));
            Item.AddPair('date',       TJSONNumber.Create(Upd.Message.Date));
            Item.AddPair('text',       Upd.Message.Text);
            if Assigned(Upd.Message.Chat) then
              Item.AddPair('chat_id',  TJSONNumber.Create(Upd.Message.Chat.Id));
            if Assigned(Upd.Message.From) then
            begin
              Item.AddPair('from_name',     Upd.Message.From.FirstName);
              Item.AddPair('from_username', Upd.Message.From.UserName);
            end;
          end;
          Items.AddElement(Item);
        end;
        R := TJSONObject.Create;
        R.AddPair('count',   TJSONNumber.Create(Items.Count));
        R.AddPair('updates', Items);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      finally
        UpdList.Free;
      end;
    end

    // ── delete ─────────────────────────────────────────────────────────
    else if Op = 'delete' then
    begin
      if AParams.ChatId    = '' then raise Exception.Create('"chatId" is required');
      if AParams.MessageId = 0  then raise Exception.Create('"messageId" is required');
      ChatId := StrToIntDef(AParams.ChatId, 0);

      Bot.API.deleteMessage(ChatId, AParams.MessageId);
      R := TJSONObject.Create;
      R.AddPair('ok',         TJSONBool.Create(True));
      R.AddPair('chat_id',    AParams.ChatId);
      R.AddPair('message_id', TJSONNumber.Create(AParams.MessageId));
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    else
      raise Exception.CreateFmt(
        'Unknown operation: "%s". Valid: me, send, photo, audio, video, document, file, updates, delete',
        [Op]);

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-telegram]: ' + E.Message)
        .Build;
  end;
end;

constructor TTelegramTool.Create;
begin
  inherited;
  FName        := 'mcp-telegram';
  FDescription :=
    'Send Telegram messages, media and files via Bot API. ' +
    'token: bot token from @BotFather — OPTIONAL if TELEGRAM_BOT_TOKEN env var is set (pass empty or omit). ' +
    'Operations and required params — ' +
    'me: none; ' +
    'send: chatId, text, parseMode? (HTML/Markdown/MarkdownV2, default HTML); ' +
    'photo: chatId, path (local file) or photoUrl (remote URL/file_id), caption?; ' +
    'audio: chatId, path, caption?; ' +
    'video: chatId, path, caption?; ' +
    'document: chatId, path, caption?; ' +
    'file: chatId, path, caption? (auto-detects photo/audio/video/document by extension); ' +
    'updates: limit? (default 10, max 100), offset?; ' +
    'delete: chatId, messageId.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-telegram',
    function: IAiMCPTool
    begin
      Result := TTelegramTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-telegram');
end;

end.
