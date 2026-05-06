unit MCPTool.DateTime;

{
  MCPTool.DateTime
  MCP tool: mcp-datetime

  Operations:
    now     — current date/time (local or UTC)
    convert — convert a datetime to another timezone/offset
    add     — add/subtract a duration from a datetime
    diff    — difference between two datetimes
    format  — format a datetime string with a custom pattern
    parse   — parse a datetime string and return ISO 8601

  Timezone support:
    Empty string  → local system time
    "UTC"         → UTC (offset 0)
    "UTC+N"/"UTC-N" → fixed UTC offset in hours (e.g. "UTC-5", "UTC+5:30")
    Windows tz ID → resolved via TTimeZone (e.g. "Eastern Standard Time")
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.DateUtils,
  System.TimeSpan,
  System.JSON,
  System.StrUtils;

type

  // ── Parameters ─────────────────────────────────────────────────────────────

  TDateTimeParams = class
  private
    FOperation: string;
    FTimezone:  string;
    FDatetime:  string;
    FDatetimeB: string;
    FAmount:    Integer;
    FTimeUnit:  string;
    FFormatStr: string;
  public
    [AiMCPSchemaDescription('Operation to perform: now, convert, add, diff, format, parse')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Timezone: empty = local, "UTC", "UTC+N", "UTC-N" or Windows TZ name (e.g. "Eastern Standard Time")')]
    property Timezone: string read FTimezone write FTimezone;

    [AiMCPOptional]
    [AiMCPSchemaDescription('ISO 8601 datetime string (e.g. "2025-03-14T10:30:00"). Required for convert, add, diff, format, parse')]
    property Datetime: string read FDatetime write FDatetime;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Second ISO 8601 datetime for diff operation')]
    property DatetimeB: string read FDatetimeB write FDatetimeB;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Amount to add (negative to subtract). Used with add operation')]
    property Amount: Integer read FAmount write FAmount;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Time unit for add/diff: seconds, minutes, hours, days, weeks, months, years. Default: hours')]
    property TimeUnit: string read FTimeUnit write FTimeUnit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Format string for format operation. Uses Delphi patterns: yyyy-mm-dd, hh:nn:ss, dd/mm/yyyy, etc.')]
    property FormatStr: string read FFormatStr write FFormatStr;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TDateTimeTool = class(TAiMCPToolBase<TDateTimeParams>)
  private
    function ParseISO(const S: string): TDateTime;
    function ToISO(const DT: TDateTime): string;
    function GetUTCOffset(const TZ: string; out OffsetMin: Integer): Boolean;

    function OpNow(const Params: TDateTimeParams): TJSONObject;
    function OpConvert(const Params: TDateTimeParams): TJSONObject;
    function OpAdd(const Params: TDateTimeParams): TJSONObject;
    function OpDiff(const Params: TDateTimeParams): TJSONObject;
    function OpFormat(const Params: TDateTimeParams): TJSONObject;
    function OpParse(const Params: TDateTimeParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TDateTimeParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Helpers ────────────────────────────────────────────────────────────────

function TDateTimeTool.ParseISO(const S: string): TDateTime;
var
  FS: TFormatSettings;
begin
  // Try ISO 8601 formats: yyyy-mm-ddThh:nn:ss, yyyy-mm-dd hh:nn:ss, yyyy-mm-dd
  FS := TFormatSettings.Create('en-US');
  FS.DateSeparator  := '-';
  FS.TimeSeparator  := ':';
  FS.ShortDateFormat := 'yyyy-mm-dd';
  FS.ShortTimeFormat := 'hh:nn:ss';

  var Normalized := StringReplace(S, 'T', ' ', []);
  // Strip timezone suffix Z or +HH:MM
  var PlusPos  := Pos('+', Normalized, 11);
  var MinusPos := Pos('-', Normalized, 11);
  if PlusPos > 0  then Normalized := Copy(Normalized, 1, PlusPos - 1);
  if MinusPos > 0 then Normalized := Copy(Normalized, 1, MinusPos - 1);
  Normalized := Trim(Normalized);

  if not TryStrToDateTime(Normalized, Result, FS) then
    if not TryStrToDate(Normalized, Result, FS) then
      raise Exception.CreateFmt('Cannot parse datetime: "%s"', [S]);
end;

function TDateTimeTool.ToISO(const DT: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', DT);
end;

function TDateTimeTool.GetUTCOffset(const TZ: string; out OffsetMin: Integer): Boolean;
var
  Upper: string;
  Sign:  Integer;
  Parts: TArray<string>;
  H, M:  Integer;
begin
  Result    := False;
  OffsetMin := 0;
  Upper     := UpperCase(Trim(TZ));

  if (Upper = '') or (Upper = 'LOCAL') then
  begin
    // Use local TZ offset
    var Bias := TTimeZone.Local.UtcOffset;
    OffsetMin := Trunc(Bias.TotalMinutes);
    Exit(True);
  end;

  if Upper = 'UTC' then
  begin
    OffsetMin := 0;
    Exit(True);
  end;

  // Parse UTC+N or UTC-N or UTC+N:MM
  if Upper.StartsWith('UTC') then
  begin
    var Rest := Copy(Upper, 4, MaxInt);
    if Rest = '' then begin OffsetMin := 0; Exit(True); end;

    Sign := 1;
    if Rest[1] = '+' then Rest := Copy(Rest, 2, MaxInt)
    else if Rest[1] = '-' then begin Sign := -1; Rest := Copy(Rest, 2, MaxInt); end;

    Parts := Rest.Split([':']);
    H := StrToIntDef(Parts[0], -9999);
    if H = -9999 then Exit(False);
    M := 0;
    if Length(Parts) > 1 then M := StrToIntDef(Parts[1], 0);

    OffsetMin := Sign * (H * 60 + M);
    Exit(True);
  end;

  // Windows TZ names not supported — use UTC+N format instead
  Result := False;
end;

// ── Operations ─────────────────────────────────────────────────────────────

function TDateTimeTool.OpNow(const Params: TDateTimeParams): TJSONObject;
var
  OffsetMin: Integer;
  LocalNow:  TDateTime;
  UtcNow:    TDateTime;
  TZName:    string;
  TZHours:   Double;
begin
  LocalNow := Now;
  UtcNow   := TTimeZone.Local.ToUniversalTime(LocalNow);

  if (Params.Timezone = '') or SameText(Params.Timezone, 'local') then
  begin
    TZName  := TTimeZone.Local.ID;
    if not GetUTCOffset('LOCAL', OffsetMin) then OffsetMin := 0;
    TZHours := OffsetMin / 60.0;
  end
  else
  begin
    TZName := Params.Timezone;
    if not GetUTCOffset(Params.Timezone, OffsetMin) then
      raise Exception.CreateFmt('Unknown timezone: "%s"', [Params.Timezone]);
    TZHours    := OffsetMin / 60.0;
    LocalNow   := UtcNow + TZHours / 24.0;
  end;

  var OffsetStr := Format('UTC%s%.0f', [IfThen(TZHours >= 0, '+', ''), TZHours]);

  Result := TJSONObject.Create;
  Result.AddPair('datetime',  ToISO(LocalNow));
  Result.AddPair('date',      FormatDateTime('yyyy-mm-dd', LocalNow));
  Result.AddPair('time',      FormatDateTime('hh:nn:ss', LocalNow));
  Result.AddPair('timestamp', TJSONNumber.Create(DateTimeToUnix(UtcNow)));
  Result.AddPair('timezone',  TZName);
  Result.AddPair('utc_offset', OffsetStr);
  Result.AddPair('utc',       ToISO(UtcNow));
  Result.AddPair('day_of_week', FormatDateTime('dddd', LocalNow));
  Result.AddPair('week_number', TJSONNumber.Create(WeekOf(LocalNow)));
end;

function TDateTimeTool.OpConvert(const Params: TDateTimeParams): TJSONObject;
var
  SrcDT:    TDateTime;
  OffsetMin: Integer;
  TZHours:  Double;
  DstDT:    TDateTime;
begin
  if Params.Datetime = '' then
    raise Exception.Create('datetime is required for convert');
  if Params.Timezone = '' then
    raise Exception.Create('timezone is required for convert');

  // Parse source as local
  SrcDT := ParseISO(Params.Datetime);

  // Convert to UTC, then to target TZ
  var LocalOffset: Integer;
  GetUTCOffset('LOCAL', LocalOffset);
  var UtcDT := SrcDT - (LocalOffset / 60.0) / 24.0;

  if not GetUTCOffset(Params.Timezone, OffsetMin) then
    raise Exception.CreateFmt('Unknown timezone: "%s"', [Params.Timezone]);
  TZHours := OffsetMin / 60.0;
  DstDT   := UtcDT + TZHours / 24.0;

  var OffsetStr := Format('UTC%s%.0f', [IfThen(TZHours >= 0, '+', ''), TZHours]);

  Result := TJSONObject.Create;
  Result.AddPair('source_datetime', ToISO(SrcDT));
  Result.AddPair('result_datetime', ToISO(DstDT));
  Result.AddPair('timezone',  Params.Timezone);
  Result.AddPair('utc_offset', OffsetStr);
  Result.AddPair('date', FormatDateTime('yyyy-mm-dd', DstDT));
  Result.AddPair('time', FormatDateTime('hh:nn:ss', DstDT));
end;

function TDateTimeTool.OpAdd(const Params: TDateTimeParams): TJSONObject;
var
  DT:  TDateTime;
  Res: TDateTime;
  U:   string;
begin
  if Params.Datetime = '' then
    raise Exception.Create('datetime is required for add');

  DT := ParseISO(Params.Datetime);
  U  := LowerCase(Trim(Params.TimeUnit));
  if U = '' then U := 'hours';

  if      U = 'seconds' then Res := IncSecond(DT, Params.Amount)
  else if U = 'minutes' then Res := IncMinute(DT, Params.Amount)
  else if U = 'hours'   then Res := IncHour(DT, Params.Amount)
  else if U = 'days'    then Res := IncDay(DT, Params.Amount)
  else if U = 'weeks'   then Res := IncWeek(DT, Params.Amount)
  else if U = 'months'  then Res := IncMonth(DT, Params.Amount)
  else if U = 'years'   then Res := IncYear(DT, Params.Amount)
  else raise Exception.CreateFmt('Unknown time unit: "%s"', [Params.TimeUnit]);

  Result := TJSONObject.Create;
  Result.AddPair('source_datetime', ToISO(DT));
  Result.AddPair('result_datetime', ToISO(Res));
  Result.AddPair('amount', TJSONNumber.Create(Params.Amount));
  Result.AddPair('unit',   U);
  Result.AddPair('date',   FormatDateTime('yyyy-mm-dd', Res));
  Result.AddPair('time',   FormatDateTime('hh:nn:ss', Res));
end;

function TDateTimeTool.OpDiff(const Params: TDateTimeParams): TJSONObject;
var
  DT1, DT2: TDateTime;
  U:         string;
  Diff:      Int64;
begin
  if Params.Datetime = '' then
    raise Exception.Create('datetime is required for diff');
  if Params.DatetimeB = '' then
    raise Exception.Create('datetime_b is required for diff');

  DT1 := ParseISO(Params.Datetime);
  DT2 := ParseISO(Params.DatetimeB);
  U   := LowerCase(Trim(Params.TimeUnit));
  if U = '' then U := 'seconds';

  if      U = 'seconds' then Diff := SecondsBetween(DT1, DT2)
  else if U = 'minutes' then Diff := MinutesBetween(DT1, DT2)
  else if U = 'hours'   then Diff := HoursBetween(DT1, DT2)
  else if U = 'days'    then Diff := DaysBetween(DT1, DT2)
  else if U = 'weeks'   then Diff := WeeksBetween(DT1, DT2)
  else if U = 'months'  then Diff := MonthsBetween(DT1, DT2)
  else if U = 'years'   then Diff := YearsBetween(DT1, DT2)
  else raise Exception.CreateFmt('Unknown time unit: "%s"', [Params.TimeUnit]);

  Result := TJSONObject.Create;
  Result.AddPair('datetime_a',   ToISO(DT1));
  Result.AddPair('datetime_b',   ToISO(DT2));
  Result.AddPair('difference',   TJSONNumber.Create(Diff));
  Result.AddPair('unit',         U);
  // Also provide full breakdown
  Result.AddPair('total_seconds', TJSONNumber.Create(SecondsBetween(DT1, DT2)));
  Result.AddPair('total_minutes', TJSONNumber.Create(MinutesBetween(DT1, DT2)));
  Result.AddPair('total_hours',   TJSONNumber.Create(HoursBetween(DT1, DT2)));
  Result.AddPair('total_days',    TJSONNumber.Create(DaysBetween(DT1, DT2)));
end;

function TDateTimeTool.OpFormat(const Params: TDateTimeParams): TJSONObject;
var
  DT:  TDateTime;
  Fmt: string;
begin
  if Params.Datetime = '' then
    raise Exception.Create('datetime is required for format');

  DT  := ParseISO(Params.Datetime);
  Fmt := Params.FormatStr;
  if Fmt = '' then Fmt := 'yyyy-mm-dd hh:nn:ss';

  Result := TJSONObject.Create;
  Result.AddPair('datetime',  ToISO(DT));
  Result.AddPair('formatted', FormatDateTime(Fmt, DT));
  Result.AddPair('format',    Fmt);
end;

function TDateTimeTool.OpParse(const Params: TDateTimeParams): TJSONObject;
var
  DT: TDateTime;
begin
  if Params.Datetime = '' then
    raise Exception.Create('datetime is required for parse');

  DT := ParseISO(Params.Datetime);

  Result := TJSONObject.Create;
  Result.AddPair('input',       Params.Datetime);
  Result.AddPair('iso8601',     ToISO(DT));
  Result.AddPair('date',        FormatDateTime('yyyy-mm-dd', DT));
  Result.AddPair('time',        FormatDateTime('hh:nn:ss', DT));
  Result.AddPair('timestamp',   TJSONNumber.Create(DateTimeToUnix(DT)));
  Result.AddPair('day_of_week', FormatDateTime('dddd', DT));
  Result.AddPair('week_number', TJSONNumber.Create(WeekOf(DT)));
  Result.AddPair('year',        TJSONNumber.Create(YearOf(DT)));
  Result.AddPair('month',       TJSONNumber.Create(MonthOf(DT)));
  Result.AddPair('day',         TJSONNumber.Create(DayOf(DT)));
  Result.AddPair('hour',        TJSONNumber.Create(HourOf(DT)));
  Result.AddPair('minute',      TJSONNumber.Create(MinuteOf(DT)));
  Result.AddPair('second',      TJSONNumber.Create(SecondOf(DT)));
end;

// ── Tool main ──────────────────────────────────────────────────────────────

constructor TDateTimeTool.Create;
begin
  inherited;
  FName        := 'mcp-datetime';
  FDescription :=
    'Get current date/time in any timezone, perform timezone conversions, ' +
    'date arithmetic (add/subtract), compute differences between dates, ' +
    'format dates and parse datetime strings. Operations: now, convert, add, diff, format, parse.';
end;

function TDateTimeTool.ExecuteWithParams(const AParams: TDateTimeParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Data: TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));

    if      Op = 'now'     then Data := OpNow(AParams)
    else if Op = 'convert' then Data := OpConvert(AParams)
    else if Op = 'add'     then Data := OpAdd(AParams)
    else if Op = 'diff'    then Data := OpDiff(AParams)
    else if Op = 'format'  then Data := OpFormat(AParams)
    else if Op = 'parse'   then Data := OpParse(AParams)
    else raise Exception.CreateFmt(
      'Unknown operation: "%s". Valid: now, convert, add, diff, format, parse', [Op]);

    Result := TAiMCPResponseBuilder.New
      .AddText(Data.ToJSON)
      .Build;
    Data.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-datetime]: ' + E.Message)
        .Build;
  end;
end;

// ── Registration ───────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-datetime',
    function: IAiMCPTool
    begin
      Result := TDateTimeTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-datetime] registered.');
end;

end.
