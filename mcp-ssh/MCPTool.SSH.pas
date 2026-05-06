unit MCPTool.SSH;

{
  MCPTool.SSH  ·  mcp-ssh

  SSH client via libssh2 dynamic library.
  Requires: libssh2.dll (Windows) / libssh2.so.1 (Linux)
            + libssl-3.dll + libcrypto-3.dll (OpenSSL 3.x, required by libssh2)

  Operations:
    exec         - Execute a remote command; returns stdout, stderr, exit_code
    sftp_list    - List a remote directory
    sftp_read    - Read a remote file as text
    sftp_write   - Write text content to a remote file
    sftp_delete  - Delete a remote file
    sftp_mkdir   - Create a remote directory
    scp_upload   - Upload a local file to a remote path (via SFTP)
    scp_download - Download a remote file to a local path (via SFTP)

  Authentication: password  OR  private key file (PEM).
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.IOUtils,
  System.DateUtils;

type

  // ── Parameters ─────────────────────────────────────────────────────────────

  TSSHParams = class
  private
    FHost:           string;
    FPort:           Integer;
    FUsername:       string;
    FPassword:       string;
    FPrivateKeyPath: string;
    FPassphrase:     string;
    FOperation:      string;
    FCommand:        string;
    FTimeoutMs:      Integer;
    FRemotePath:     string;
    FLocalPath:      string;
    FContent:        string;
    FEncoding:       string;
  public
    [AiMCPSchemaDescription('Remote host address (hostname or IP)')]
    property Host: string read FHost write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SSH port (default: 22)')]
    property Port: Integer read FPort write FPort;

    [AiMCPSchemaDescription('SSH username')]
    property Username: string read FUsername write FUsername;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Password for password-based authentication')]
    property Password: string read FPassword write FPassword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Path to PEM private key file for key-based authentication')]
    property PrivateKeyPath: string read FPrivateKeyPath write FPrivateKeyPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Passphrase for encrypted private key')]
    property Passphrase: string read FPassphrase write FPassphrase;

    [AiMCPSchemaDescription('Operation: exec, sftp_list, sftp_read, sftp_write, sftp_delete, sftp_mkdir, scp_upload, scp_download')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Shell command to execute on the remote host (for exec)')]
    property Command: string read FCommand write FCommand;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Timeout in milliseconds as an INTEGER number, NOT a string (default: 30000). Example: 30000')]
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Remote file or directory path (for sftp_* and scp_*)')]
    property RemotePath: string read FRemotePath write FRemotePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Local file path: source for scp_upload, destination for scp_download')]
    property LocalPath: string read FLocalPath write FLocalPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Text content to write to the remote file (for sftp_write)')]
    property Content: string read FContent write FContent;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Text encoding for sftp_read / sftp_write (default: utf-8)')]
    property Encoding: string read FEncoding write FEncoding;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TSSHTool = class(TAiMCPToolBase<TSSHParams>)
  private

    // ── libssh2 function-pointer types ─────────────────────────────────────
    type TL_Init              = function(flags: Integer): Integer; cdecl;
    type TL_SessionNew        = function(a, b, c, d: Pointer): Pointer; cdecl;
    type TL_SessionHandshake  = function(session: Pointer; sock: THandle): Integer; cdecl;
    type TL_SessionBlocking   = procedure(session: Pointer; blocking: Integer); cdecl;
    type TL_SessionTimeout    = procedure(session: Pointer; timeout: Integer); cdecl;
    type TL_SessionFree       = function(session: Pointer): Integer; cdecl;
    type TL_AuthPassword      = function(session: Pointer;
                                  user: PAnsiChar; user_len: NativeUInt;
                                  pass: PAnsiChar; pass_len: NativeUInt;
                                  cb: Pointer): Integer; cdecl;
    type TL_AuthPubkey        = function(session: Pointer;
                                  user, pubkey, privkey, passphrase: PAnsiChar): Integer; cdecl;
    type TL_ChannelOpen       = function(session: Pointer;
                                  chan_type: PAnsiChar; type_len: Cardinal;
                                  window_size, packet_size: Cardinal;
                                  msg: PAnsiChar; msg_len: Cardinal): Pointer; cdecl;
    type TL_ChannelProcess    = function(channel: Pointer;
                                  req: PAnsiChar; req_len: Cardinal;
                                  msg: PAnsiChar; msg_len: Cardinal): Integer; cdecl;
    type TL_ChannelRead       = function(channel: Pointer;
                                  stream_id: Integer;
                                  buf: Pointer; buflen: NativeUInt): NativeInt; cdecl;
    type TL_ChannelEof        = function(channel: Pointer): Integer; cdecl;
    type TL_ChannelSendEof    = function(channel: Pointer): Integer; cdecl;
    type TL_ChannelClose      = function(channel: Pointer): Integer; cdecl;
    type TL_ChannelFree       = function(channel: Pointer): Integer; cdecl;
    type TL_ChannelExitCode   = function(channel: Pointer): Integer; cdecl;
    type TL_SFTPInit          = function(session: Pointer): Pointer; cdecl;
    type TL_SFTPShutdown      = function(sftp: Pointer): Integer; cdecl;
    type TL_SFTPOpenEx        = function(sftp: Pointer;
                                  path: PAnsiChar; path_len: Cardinal;
                                  flags, mode: NativeUInt;
                                  open_type: Integer): Pointer; cdecl;
    type TL_SFTPReaddir       = function(handle: Pointer;
                                  buf: PAnsiChar; buflen: NativeUInt;
                                  longbuf: PAnsiChar; longbuflen: NativeUInt;
                                  attrs: Pointer): NativeInt; cdecl;
    type TL_SFTPRead          = function(handle: Pointer;
                                  buf: Pointer; buflen: NativeUInt): NativeInt; cdecl;
    type TL_SFTPWrite         = function(handle: Pointer;
                                  buf: Pointer; count: NativeUInt): NativeInt; cdecl;
    type TL_SFTPClose         = function(handle: Pointer): Integer; cdecl;
    type TL_SFTPUnlink        = function(sftp: Pointer;
                                  path: PAnsiChar; path_len: Cardinal): Integer; cdecl;
    type TL_SFTPMkDir         = function(sftp: Pointer;
                                  path: PAnsiChar; path_len: Cardinal;
                                  mode: NativeUInt): Integer; cdecl;
    type TL_Exit              = procedure; cdecl;

    // ── State & function pointers (var section required after nested types) ─
    var
    FLibHandle  : THandle;
    FSession    : Pointer;
    FSocket     : THandle;
    FTimeoutMs  : Integer;  // effective timeout for this connection

    // ── Function pointers ──────────────────────────────────────────────────
    ssh2_init              : TL_Init;
    ssh2_session_new       : TL_SessionNew;
    ssh2_session_handshake : TL_SessionHandshake;
    ssh2_session_blocking  : TL_SessionBlocking;
    ssh2_session_timeout   : TL_SessionTimeout;
    ssh2_session_free      : TL_SessionFree;
    ssh2_auth_password     : TL_AuthPassword;
    ssh2_auth_pubkey       : TL_AuthPubkey;
    ssh2_channel_open      : TL_ChannelOpen;
    ssh2_channel_process   : TL_ChannelProcess;
    ssh2_channel_read      : TL_ChannelRead;
    ssh2_channel_eof       : TL_ChannelEof;
    ssh2_channel_send_eof  : TL_ChannelSendEof;
    ssh2_channel_close     : TL_ChannelClose;
    ssh2_channel_free      : TL_ChannelFree;
    ssh2_channel_exit_code : TL_ChannelExitCode;
    ssh2_sftp_init         : TL_SFTPInit;
    ssh2_sftp_shutdown     : TL_SFTPShutdown;
    ssh2_sftp_open_ex      : TL_SFTPOpenEx;
    ssh2_sftp_readdir      : TL_SFTPReaddir;
    ssh2_sftp_read         : TL_SFTPRead;
    ssh2_sftp_write        : TL_SFTPWrite;
    ssh2_sftp_close        : TL_SFTPClose;
    ssh2_sftp_unlink       : TL_SFTPUnlink;
    ssh2_sftp_mkdir        : TL_SFTPMkDir;
    ssh2_exit              : TL_Exit;

    // ── Low-level helpers ──────────────────────────────────────────────────
    function  LoadLib: Boolean;
    procedure FreeLib;
    function  CreateTCPSocket(const AHost: string; APort: Integer; ATimeoutMs: Integer): THandle;
    procedure SSHConnect(const AHost: string; APort: Integer;
                         const AUser, APass, AKeyFile, APassphrase: string;
                         ATimeoutMs: Integer = 30000);
    procedure SSHDisconnect;
    function  ReadChannel(AChannel: Pointer; AStreamId: Integer): string;
    procedure ReadChannelBoth(AChannel: Pointer; out AStdOut, AStdErr: string);
    function  GetPermString(APerms: UInt64): string;
    function  MTimeToStr(AUnixTs: UInt64): string;

    // ── Operations ─────────────────────────────────────────────────────────
    function DoExec(const P: TSSHParams): TJSONObject;
    function DoSFTPList(const P: TSSHParams): TJSONObject;
    function DoSFTPRead(const P: TSSHParams): TJSONObject;
    function DoSFTPWrite(const P: TSSHParams): TJSONObject;
    function DoSFTPDelete(const P: TSSHParams): TJSONObject;
    function DoSFTPMkDir(const P: TSSHParams): TJSONObject;
    function DoSCPUpload(const P: TSSHParams): TJSONObject;
    function DoSCPDownload(const P: TSSHParams): TJSONObject;

  protected
    function ExecuteWithParams(const AParams: TSSHParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
  Winapi.WinSock2,
{$ENDIF}
{$IF DEFINED(LINUX) OR DEFINED(MACOS)}
  Posix.SysSocket,
  Posix.NetinetIn,
  Posix.ArpaInet,
  Posix.NetDB,
  Posix.Unistd,
{$ENDIF}
  System.Math,
  System.StrUtils,
  System.SyncObjs;

// ── SSH Diagnostics Log ───────────────────────────────────────────────────────
// Keeps the last 50 entries in <exe_dir>/mcp-ssh.log.
// Each line: [ISO-timestamp] PHASE key=value ...
// ─────────────────────────────────────────────────────────────────────────────
var
  GSSHLogFile : string = '';
  GSSHLogLock : TCriticalSection = nil;

function SSHLogFile: string;
begin
  if GSSHLogFile = '' then
    GSSHLogFile := TPath.Combine(
      TPath.GetDirectoryName(ParamStr(0)), 'mcp-ssh.log');
  Result := GSSHLogFile;
end;

procedure SSHLog(const ALine: string);
var
  F : TextFile;
  TS: string;
begin
  try
    if GSSHLogLock = nil then
      GSSHLogLock := TCriticalSection.Create;
    TS := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', Now);
    GSSHLogLock.Enter;
    try
      AssignFile(F, SSHLogFile);
      if TFile.Exists(SSHLogFile) then
        Append(F)
      else
        Rewrite(F);
      try
        WriteLn(F, '[' + TS + '] ' + ALine);
      finally
        CloseFile(F);
      end;
    finally
      GSSHLogLock.Leave;
    end;
  except
    // Never let logging crash the tool
  end;
end;

// Trim log to last 50 lines (called at end of each operation).
procedure SSHLogTrim;
var
  Lines: TStringList;
  LFile: string;
begin
  try
    LFile := SSHLogFile;
    if not TFile.Exists(LFile) then Exit;
    Lines := TStringList.Create;
    try
      Lines.LoadFromFile(LFile);
      if Lines.Count > 50 then
      begin
        while Lines.Count > 50 do
          Lines.Delete(0);
        Lines.SaveToFile(LFile);
      end;
    finally
      Lines.Free;
    end;
  except
  end;
end;

// ── SFTP attributes struct ────────────────────────────────────────────────────
// Windows 64-bit (MinGW): unsigned long = 4 bytes → explicit padding needed
// Linux   64-bit (GCC)  : unsigned long = 8 bytes → no padding needed
//
{$IFDEF MSWINDOWS}
type
  TLIBSSH2SFTPAttrs = packed record
    flags       : UInt32;   // unsigned long (4 bytes on Windows)
    _pad        : UInt32;   // explicit padding to align filesize to offset 8
    filesize    : UInt64;   // libssh2_uint64_t
    uid         : UInt32;
    gid         : UInt32;
    permissions : UInt32;
    atime       : UInt32;
    mtime       : UInt32;
    _tail       : UInt32;   // tail pad → struct = 40 bytes, matches MinGW layout
  end;
{$ELSE}
type
  // Linux x64 GCC: unsigned long = 8 bytes, no padding needed
  TLIBSSH2SFTPAttrs = packed record
    flags       : UInt64;
    filesize    : UInt64;
    uid         : UInt64;
    gid         : UInt64;
    permissions : UInt64;
    atime       : UInt64;
    mtime       : UInt64;
  end;
{$ENDIF}

const
{$IFDEF MSWINDOWS}
  LIBSSH2_NAME = 'libssh2.dll';
{$ENDIF}
{$IFDEF LINUX}
  LIBSSH2_NAME = 'libssh2.so.1';
{$ENDIF}
{$IFDEF MACOS}
  LIBSSH2_NAME = 'libssh2.dylib';
{$ENDIF}

  // SFTP attribute flags
  SFTP_ATTR_SIZE        = $00000001;
  SFTP_ATTR_PERMISSIONS = $00000004;
  SFTP_ATTR_ACMODTIME   = $00000008;

  // SFTP file-type masks (Unix mode bits)
  S_IFMT  = $F000;
  S_IFDIR = $4000;
  S_IFREG = $8000;
  S_IFLNK = $A000;

  // SFTP open flags
  LIBSSH2_FXF_READ  = $00000001;
  LIBSSH2_FXF_WRITE = $00000002;
  LIBSSH2_FXF_CREAT = $00000008;
  LIBSSH2_FXF_TRUNC = $00000010;

  // SFTP open types
  LIBSSH2_SFTP_OPENFILE = 0;
  LIBSSH2_SFTP_OPENDIR  = 1;

  // SFTP default permissions (octal 644 and 755)
  SFTP_PERM_FILE = $1A4;   // 0644
  SFTP_PERM_DIR  = $1ED;   // 0755

{$IFDEF MSWINDOWS}
// Avoid name collision with inherited Connect method
function wsa_connect(s: TSocket; addr: Pointer; addrlen: Integer): Integer; stdcall;
  external 'ws2_32.dll' name 'connect';
{$ENDIF}

// ── LoadLib ──────────────────────────────────────────────────────────────────

function TSSHTool.LoadLib: Boolean;
{$IFDEF MSWINDOWS}
  function Sym(const Name: string): Pointer;
  begin
    Result := GetProcAddress(FLibHandle, PChar(Name));
    if Result = nil then
      raise Exception.CreateFmt('libssh2: symbol "%s" not found', [Name]);
  end;
begin
  FLibHandle := LoadLibrary(LIBSSH2_NAME);
  Result := FLibHandle <> 0;
  if not Result then Exit;
  @ssh2_init              := Sym('libssh2_init');
  @ssh2_session_new       := Sym('libssh2_session_init_ex');
  @ssh2_session_handshake := Sym('libssh2_session_handshake');
  @ssh2_session_blocking  := Sym('libssh2_session_set_blocking');
  @ssh2_session_timeout   := Sym('libssh2_session_set_timeout');
  @ssh2_session_free      := Sym('libssh2_session_free');
  @ssh2_auth_password     := Sym('libssh2_userauth_password_ex');
  @ssh2_auth_pubkey       := Sym('libssh2_userauth_publickey_fromfile_ex');
  @ssh2_channel_open      := Sym('libssh2_channel_open_ex');
  @ssh2_channel_process   := Sym('libssh2_channel_process_startup');
  @ssh2_channel_read      := Sym('libssh2_channel_read_ex');
  @ssh2_channel_eof       := Sym('libssh2_channel_eof');
  @ssh2_channel_send_eof  := Sym('libssh2_channel_send_eof');
  @ssh2_channel_close     := Sym('libssh2_channel_close');
  @ssh2_channel_free      := Sym('libssh2_channel_free');
  @ssh2_channel_exit_code := Sym('libssh2_channel_get_exit_status');
  @ssh2_sftp_init         := Sym('libssh2_sftp_init');
  @ssh2_sftp_shutdown     := Sym('libssh2_sftp_shutdown');
  @ssh2_sftp_open_ex      := Sym('libssh2_sftp_open_ex');
  @ssh2_sftp_readdir      := Sym('libssh2_sftp_readdir_ex');
  @ssh2_sftp_read         := Sym('libssh2_sftp_read');
  @ssh2_sftp_write        := Sym('libssh2_sftp_write');
  @ssh2_sftp_close        := Sym('libssh2_sftp_close_handle');
  @ssh2_sftp_unlink       := Sym('libssh2_sftp_unlink_ex');
  @ssh2_sftp_mkdir        := Sym('libssh2_sftp_mkdir_ex');
  @ssh2_exit              := Sym('libssh2_exit');
end;
{$ELSE}
  function Sym(const Name: string): Pointer;
  begin
    Result := GetProcAddress(FLibHandle, PChar(Name));
    if Result = nil then
      raise Exception.CreateFmt('libssh2: symbol "%s" not found', [Name]);
  end;
begin
  FLibHandle := LoadLibrary(LIBSSH2_NAME);
  Result := FLibHandle <> 0;
  if not Result then Exit;
  @ssh2_init              := Sym('libssh2_init');
  @ssh2_session_new       := Sym('libssh2_session_init_ex');
  @ssh2_session_handshake := Sym('libssh2_session_handshake');
  @ssh2_session_blocking  := Sym('libssh2_session_set_blocking');
  @ssh2_session_timeout   := Sym('libssh2_session_set_timeout');
  @ssh2_session_free      := Sym('libssh2_session_free');
  @ssh2_auth_password     := Sym('libssh2_userauth_password_ex');
  @ssh2_auth_pubkey       := Sym('libssh2_userauth_publickey_fromfile_ex');
  @ssh2_channel_open      := Sym('libssh2_channel_open_ex');
  @ssh2_channel_process   := Sym('libssh2_channel_process_startup');
  @ssh2_channel_read      := Sym('libssh2_channel_read_ex');
  @ssh2_channel_eof       := Sym('libssh2_channel_eof');
  @ssh2_channel_send_eof  := Sym('libssh2_channel_send_eof');
  @ssh2_channel_close     := Sym('libssh2_channel_close');
  @ssh2_channel_free      := Sym('libssh2_channel_free');
  @ssh2_channel_exit_code := Sym('libssh2_channel_get_exit_status');
  @ssh2_sftp_init         := Sym('libssh2_sftp_init');
  @ssh2_sftp_shutdown     := Sym('libssh2_sftp_shutdown');
  @ssh2_sftp_open_ex      := Sym('libssh2_sftp_open_ex');
  @ssh2_sftp_readdir      := Sym('libssh2_sftp_readdir_ex');
  @ssh2_sftp_read         := Sym('libssh2_sftp_read');
  @ssh2_sftp_write        := Sym('libssh2_sftp_write');
  @ssh2_sftp_close        := Sym('libssh2_sftp_close_handle');
  @ssh2_sftp_unlink       := Sym('libssh2_sftp_unlink_ex');
  @ssh2_sftp_mkdir        := Sym('libssh2_sftp_mkdir_ex');
  @ssh2_exit              := Sym('libssh2_exit');
end;
{$ENDIF}

procedure TSSHTool.FreeLib;
begin
  { Do NOT call FreeLibrary or ssh2_exit here — same reason as TTY.Transport.SSH:
    MinGW libssh2 atexit handlers conflict with explicit session_free, causing
    double-free in msvcrt.dll. The DLL is released when the process exits. }
  FLibHandle := 0;
end;

// ── TCP Socket ───────────────────────────────────────────────────────────────

function TSSHTool.CreateTCPSocket(const AHost: string; APort: Integer; ATimeoutMs: Integer): THandle;
{$IFDEF MSWINDOWS}
var
  Data    : WSAData;
  Host    : PHostEnt;
  AddrIn  : TSockAddrIn;
  Sock    : TSocket;
  NonBlock: u_long;
  FDWrite : TFDSet;
  FDExcept: TFDSet;
  TV      : timeval;
  Rc      : Integer;
  SockErr : Integer;
  ErrLen  : Integer;
  TMsec   : Integer;
begin
  WSAStartup($0202, Data);
  Host := gethostbyname(PAnsiChar(AnsiString(AHost)));
  if Host = nil then
    raise Exception.CreateFmt('Cannot resolve host: %s', [AHost]);
  FillChar(AddrIn, SizeOf(AddrIn), 0);
  AddrIn.sin_family := AF_INET;
  AddrIn.sin_port   := htons(APort);
  AddrIn.sin_addr   := PInAddr(Host^.h_addr_list^)^;
  Sock := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if Sock = INVALID_SOCKET then
    raise Exception.Create('Cannot create TCP socket');

  // Non-blocking connect so we can enforce a timeout via select()
  TMsec := ATimeoutMs;
  if TMsec <= 0 then TMsec := 30000;

  NonBlock := 1;
  ioctlsocket(Sock, FIONBIO, NonBlock);
  wsa_connect(Sock, @AddrIn, SizeOf(AddrIn));  // expects WSAEWOULDBLOCK

  FillChar(FDWrite,  SizeOf(FDWrite),  0);
  FillChar(FDExcept, SizeOf(FDExcept), 0);
  FDWrite.fd_count    := 1;  FDWrite.fd_array[0]  := Sock;
  FDExcept.fd_count   := 1;  FDExcept.fd_array[0] := Sock;
  TV.tv_sec  := TMsec div 1000;
  TV.tv_usec := (TMsec mod 1000) * 1000;

  Rc := select(0, nil, @FDWrite, @FDExcept, @TV);
  if Rc <= 0 then
  begin
    closesocket(Sock);
    if Rc = 0 then
      raise Exception.CreateFmt('Connection to %s:%d timed out after %dms', [AHost, APort, TMsec])
    else
      raise Exception.CreateFmt('Cannot connect to %s:%d', [AHost, APort]);
  end;

  // Verify no socket-level error (covers both success-in-writefds and error-in-exceptfds)
  SockErr := 0;
  ErrLen  := SizeOf(SockErr);
  getsockopt(Sock, SOL_SOCKET, SO_ERROR, PAnsiChar(@SockErr), ErrLen);
  if SockErr <> 0 then
  begin
    closesocket(Sock);
    raise Exception.CreateFmt('Cannot connect to %s:%d (WSA error %d)', [AHost, APort, SockErr]);
  end;

  // Restore blocking mode
  NonBlock := 0;
  ioctlsocket(Sock, FIONBIO, NonBlock);

  Result := THandle(Sock);
end;
{$ELSE}
var
  Hints: addrinfo;
  Res  : Paddrinfo;
  Sock : Integer;
begin
  FillChar(Hints, SizeOf(Hints), 0);
  Hints.ai_family   := AF_INET;
  Hints.ai_socktype := SOCK_STREAM;
  if getaddrinfo(MarshaledAString(UTF8Encode(AHost)),
                 MarshaledAString(UTF8Encode(IntToStr(APort))),
                 Hints, Res) <> 0 then
    raise Exception.CreateFmt('Cannot resolve: %s', [AHost]);
  try
    Sock := Posix.SysSocket.socket(Res^.ai_family, Res^.ai_socktype, Res^.ai_protocol);
    if Sock < 0 then raise Exception.Create('Cannot create TCP socket');
    if Posix.SysSocket.connect(Sock, Res^.ai_addr^, Res^.ai_addrlen) <> 0 then
    begin
      __close(Sock);
      raise Exception.CreateFmt('Cannot connect to %s:%d', [AHost, APort]);
    end;
    Result := THandle(Sock);
  finally
    freeaddrinfo(Res^);
  end;
end;
{$ENDIF}

// ── Connect / Disconnect ─────────────────────────────────────────────────────

procedure TSSHTool.SSHConnect(const AHost: string; APort: Integer;
  const AUser, APass, AKeyFile, APassphrase: string; ATimeoutMs: Integer = 30000);
var
  User, Pass, KeyF, PP: RawByteString;
  Port: Integer;
begin
  if not LoadLib then
    raise Exception.CreateFmt('Cannot load %s', [LIBSSH2_NAME]);

  Port := APort;
  if Port <= 0 then Port := 22;

  SSHLog(Format('CONNECT host=%s port=%d user=%s auth=%s',
    [AHost, Port, AUser, IfThen(AKeyFile <> '', 'pubkey', 'password')]));

  FSocket := CreateTCPSocket(AHost, Port, ATimeoutMs);

  ssh2_init(0);
  FSession := ssh2_session_new(nil, nil, nil, nil);
  if FSession = nil then
    raise Exception.Create('libssh2_session_init_ex failed');

  ssh2_session_blocking(FSession, 1);

  // Apply timeout to ALL blocking libssh2 operations (handshake, read, close…)
  var TMsec := ATimeoutMs;
  if TMsec <= 0 then TMsec := 30000;
  FTimeoutMs := TMsec;
  ssh2_session_timeout(FSession, TMsec);

  if ssh2_session_handshake(FSession, FSocket) <> 0 then
    raise Exception.Create('SSH handshake failed');

  User := UTF8Encode(AUser);
  if AKeyFile <> '' then
  begin
    KeyF := UTF8Encode(AKeyFile);
    PP   := UTF8Encode(APassphrase);
    if ssh2_auth_pubkey(FSession, PAnsiChar(User), nil,
                        PAnsiChar(KeyF), PAnsiChar(PP)) <> 0 then
      raise Exception.Create('SSH public-key authentication failed');
  end
  else
  begin
    Pass := UTF8Encode(APass);
    if ssh2_auth_password(FSession,
                          PAnsiChar(User), Length(User),
                          PAnsiChar(Pass), Length(Pass), nil) <> 0 then
      raise Exception.Create('SSH password authentication failed');
  end;
  SSHLog('CONNECT_OK');
end;

procedure TSSHTool.SSHDisconnect;
begin
  SSHLog('DISCONNECT');
  if FSession <> nil then
  begin
    ssh2_session_free(FSession);
    FSession := nil;
  end;
{$IFDEF MSWINDOWS}
  if FSocket <> INVALID_SOCKET then
  begin
    closesocket(FSocket);
    FSocket := INVALID_SOCKET;
  end;
{$ELSE}
  if Integer(FSocket) >= 0 then
  begin
    __close(Integer(FSocket));
    FSocket := THandle(-1);
  end;
{$ENDIF}
  FreeLib;
end;

// ── Channel helpers ──────────────────────────────────────────────────────────

function TSSHTool.ReadChannel(AChannel: Pointer; AStreamId: Integer): string;
var
  Buf       : array[0..16383] of Byte;
  N         : NativeInt;
  BS        : TBytesStream;
  Iter      : Integer;
  EofSt     : Integer;
  StartTs   : TDateTime;
  DeadlineMs: Integer;
  BytesRead : Int64;
begin
  SSHLog(Format('READ_START stream=%d', [AStreamId]));
  Iter       := 0;
  BytesRead  := 0;
  StartTs    := Now;
  DeadlineMs := FTimeoutMs;
  if DeadlineMs <= 0 then DeadlineMs := 30000;
  BS := TBytesStream.Create;
  try
    repeat
      N := ssh2_channel_read(AChannel, AStreamId, @Buf[0], SizeOf(Buf));
      if N > 0 then
      begin
        BS.Write(Buf[0], N);
        Inc(BytesRead, N);
      end
      else if N = 0 then
      begin
        EofSt := ssh2_channel_eof(AChannel);
        if EofSt <> 0 then Break;
        // Wall-clock timeout: channel_read can return 0 immediately (no data for
        // this stream yet) without ever blocking, so libssh2 session timeout
        // does not fire. We enforce our own deadline here.
        if MilliSecondsBetween(Now, StartTs) >= DeadlineMs then
        begin
          SSHLog(Format('READ_TIMEOUT stream=%d iter=%d bytes=%d after=%dms',
            [AStreamId, Iter, BytesRead, DeadlineMs]));
          Break;
        end;
        Inc(Iter);
        // Log every ~1 second (200 x 5 ms) to detect hangs
        if (Iter mod 200) = 0 then
          SSHLog(Format('READ_WAIT stream=%d iter=%d bytes=%d eof=%d',
            [AStreamId, Iter, BytesRead, EofSt]));
        Sleep(5);
      end
      else
      begin
        SSHLog(Format('READ_ERROR stream=%d iter=%d bytes=%d n=%d',
          [AStreamId, Iter, BytesRead, N]));
        Break;
      end;
    until False;
    // Decode accumulated bytes as UTF-8 (servers are virtually always UTF-8)
    Result := TEncoding.UTF8.GetString(BS.Bytes, 0, BS.Size);
    SSHLog(Format('READ_DONE stream=%d bytes=%d iter=%d',
      [AStreamId, BytesRead, Iter]));
  finally
    BS.Free;
  end;
end;

// Reads stdout (stream 0) and stderr (stream 1) interleaved to prevent the
// SSH channel window deadlock: if the remote command writes enough stderr
// to fill the channel window while the client is draining stdout only,
// the server blocks on write → stdout EOF never arrives → client hangs.
procedure TSSHTool.ReadChannelBoth(AChannel: Pointer;
  out AStdOut, AStdErr: string);
var
  Buf        : array[0..16383] of Byte;
  N          : NativeInt;
  BSOut, BSErr: TBytesStream;
  Iter       : Integer;
  StartTs    : TDateTime;
  DeadlineMs : Integer;
  BytesOut, BytesErr: Int64;
  OutDone, ErrDone: Boolean;
begin
  SSHLog('READ_BOTH_START');
  Iter       := 0;
  BytesOut   := 0;
  BytesErr   := 0;
  StartTs    := Now;
  DeadlineMs := FTimeoutMs;
  if DeadlineMs <= 0 then DeadlineMs := 30000;
  BSOut := TBytesStream.Create;
  BSErr := TBytesStream.Create;
  try
    OutDone := False;
    ErrDone := False;
    repeat
      // Drain whatever is available on each stream non-blockingly
      if not OutDone then
      begin
        N := ssh2_channel_read(AChannel, 0, @Buf[0], SizeOf(Buf));
        if N > 0 then begin BSOut.Write(Buf[0], N); Inc(BytesOut, N); end
        else if N = 0 then begin if ssh2_channel_eof(AChannel) <> 0 then OutDone := True; end
        else OutDone := True;
      end;
      if not ErrDone then
      begin
        N := ssh2_channel_read(AChannel, 1, @Buf[0], SizeOf(Buf));
        if N > 0 then begin BSErr.Write(Buf[0], N); Inc(BytesErr, N); end
        else if N = 0 then begin if ssh2_channel_eof(AChannel) <> 0 then ErrDone := True; end
        else ErrDone := True;
      end;

      if OutDone and ErrDone then Break;

      if MilliSecondsBetween(Now, StartTs) >= DeadlineMs then
      begin
        SSHLog(Format('READ_BOTH_TIMEOUT iter=%d out=%d err=%d after=%dms',
          [Iter, BytesOut, BytesErr, DeadlineMs]));
        Break;
      end;
      Inc(Iter);
      if (Iter mod 200) = 0 then
        SSHLog(Format('READ_BOTH_WAIT iter=%d out=%d err=%d',
          [Iter, BytesOut, BytesErr]));
      if (not OutDone) or (not ErrDone) then Sleep(5);
    until False;

    AStdOut := TEncoding.UTF8.GetString(BSOut.Bytes, 0, BSOut.Size);
    AStdErr := TEncoding.UTF8.GetString(BSErr.Bytes, 0, BSErr.Size);
    SSHLog(Format('READ_BOTH_DONE out=%d err=%d iter=%d', [BytesOut, BytesErr, Iter]));
  finally
    BSOut.Free;
    BSErr.Free;
  end;
end;

function TSSHTool.GetPermString(APerms: UInt64): string;
var
  P: UInt64;
  S: string;
begin
  P := APerms and $1FF;  // lower 9 bits: rwxrwxrwx
  case APerms and S_IFMT of
    S_IFDIR: S := 'd';
    S_IFLNK: S := 'l';
    S_IFREG: S := '-';
  else        S := '?';
  end;
  S := S + IfThen((P and $100) <> 0, 'r', '-')
         + IfThen((P and $080) <> 0, 'w', '-')
         + IfThen((P and $040) <> 0, 'x', '-')
         + IfThen((P and $020) <> 0, 'r', '-')
         + IfThen((P and $010) <> 0, 'w', '-')
         + IfThen((P and $008) <> 0, 'x', '-')
         + IfThen((P and $004) <> 0, 'r', '-')
         + IfThen((P and $002) <> 0, 'w', '-')
         + IfThen((P and $001) <> 0, 'x', '-');
  Result := S;
end;

function TSSHTool.MTimeToStr(AUnixTs: UInt64): string;
begin
  try
    Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', UnixToDateTime(Int64(AUnixTs)));
  except
    Result := '';
  end;
end;

// ── exec ─────────────────────────────────────────────────────────────────────

function TSSHTool.DoExec(const P: TSSHParams): TJSONObject;
var
  Chan    : Pointer;
  Cmd     : RawByteString;
  StdOut  : string;
  StdErr  : string;
  ExitCode: Integer;
begin
  if P.Command = '' then
    raise Exception.Create('"command" is required for exec');

  SSHConnect(P.Host, P.Port, P.Username, P.Password, P.PrivateKeyPath, P.Passphrase, P.TimeoutMs);
  try
    Chan := ssh2_channel_open(FSession,
      'session', 7,
      2 * 1024 * 1024, 32768,
      nil, 0);
    if Chan = nil then
      raise Exception.Create('Cannot open SSH channel');
    try
      Cmd := UTF8Encode(P.Command);
      if ssh2_channel_process(Chan, 'exec', 4,
                              PAnsiChar(Cmd), Length(Cmd)) <> 0 then
        raise Exception.Create('Failed to start exec channel');

      // Interleaved read prevents SSH channel window deadlock when the remote
      // command writes heavily to both streams simultaneously.
      // Exit status arrives before EOF — available immediately after read.
      // Skipping channel_send_eof + channel_close: libssh2_channel_close can
      // block indefinitely on slow/degraded connections (session timeout does
      // not reliably cover it in the MinGW build).
      ReadChannelBoth(Chan, StdOut, StdErr);
      ExitCode := ssh2_channel_exit_code(Chan);
    finally
      ssh2_channel_free(Chan);
    end;
  finally
    SSHDisconnect;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('operation',  'exec');
  Result.AddPair('host',       P.Host);
  Result.AddPair('command',    P.Command);
  Result.AddPair('stdout',     StdOut);
  Result.AddPair('stderr',     StdErr);
  Result.AddPair('exit_code',  TJSONNumber.Create(ExitCode));
  Result.AddPair('ok',         TJSONBool.Create(ExitCode = 0));
end;

// ── sftp_list ────────────────────────────────────────────────────────────────

function TSSHTool.DoSFTPList(const P: TSSHParams): TJSONObject;
var
  SFTP    : Pointer;
  DirH    : Pointer;
  Attrs   : TLIBSSH2SFTPAttrs;
  NameBuf : array[0..1023] of AnsiChar;
  LongBuf : array[0..1023] of AnsiChar;
  N       : NativeInt;
  Files   : TJSONArray;
  Item    : TJSONObject;
  Name    : string;
  IsDir   : Boolean;
  RemPath : AnsiString;
begin
  if P.RemotePath = '' then
    raise Exception.Create('"remote_path" is required for sftp_list');

  SSHConnect(P.Host, P.Port, P.Username, P.Password, P.PrivateKeyPath, P.Passphrase, P.TimeoutMs);
  try
    SFTP := ssh2_sftp_init(FSession);
    if SFTP = nil then
      raise Exception.Create('Cannot init SFTP subsystem');
    try
      RemPath := AnsiString(P.RemotePath);
      DirH := ssh2_sftp_open_ex(SFTP,
        PAnsiChar(RemPath), Length(RemPath),
        0, 0, LIBSSH2_SFTP_OPENDIR);
      if DirH = nil then
        raise Exception.CreateFmt('Cannot open remote directory: %s', [P.RemotePath]);
      try
        Files := TJSONArray.Create;
        repeat
          FillChar(Attrs, SizeOf(Attrs), 0);
          N := ssh2_sftp_readdir(DirH,
            @NameBuf[0], SizeOf(NameBuf) - 1,
            @LongBuf[0], SizeOf(LongBuf) - 1,
            @Attrs);
          if N <= 0 then Break;
          NameBuf[N] := #0;
          Name := string(AnsiString(NameBuf));
          if (Name = '.') or (Name = '..') then Continue;

          IsDir := (Attrs.permissions and S_IFMT) = S_IFDIR;

          Item := TJSONObject.Create;
          Item.AddPair('name',        Name);
          Item.AddPair('path',        P.RemotePath.TrimRight(['/']) + '/' + Name);
          Item.AddPair('size',        TJSONNumber.Create(Int64(Attrs.filesize)));
          Item.AddPair('is_dir',      TJSONBool.Create(IsDir));
          Item.AddPair('permissions', GetPermString(Attrs.permissions));
          Item.AddPair('modified',    MTimeToStr(Attrs.mtime));
          Files.AddElement(Item);
        until False;
      finally
        ssh2_sftp_close(DirH);
      end;
    finally
      ssh2_sftp_shutdown(SFTP);
    end;
  finally
    SSHDisconnect;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('operation',   'sftp_list');
  Result.AddPair('remote_path', P.RemotePath);
  Result.AddPair('count',       TJSONNumber.Create(Files.Count));
  Result.AddPair('files',       Files);
end;

// ── sftp_read ────────────────────────────────────────────────────────────────

function TSSHTool.DoSFTPRead(const P: TSSHParams): TJSONObject;
var
  SFTP    : Pointer;
  FileH   : Pointer;
  Buf     : array[0..65535] of Byte;
  N       : NativeInt;
  BS      : TBytesStream;
  Bytes   : TBytes;
  Content : string;
  Enc     : TEncoding;
  RemPath : AnsiString;
begin
  if P.RemotePath = '' then
    raise Exception.Create('"remote_path" is required for sftp_read');

  SSHConnect(P.Host, P.Port, P.Username, P.Password, P.PrivateKeyPath, P.Passphrase, P.TimeoutMs);
  try
    SFTP := ssh2_sftp_init(FSession);
    if SFTP = nil then
      raise Exception.Create('Cannot init SFTP subsystem');
    try
      RemPath := AnsiString(P.RemotePath);
      FileH := ssh2_sftp_open_ex(SFTP,
        PAnsiChar(RemPath), Length(RemPath),
        LIBSSH2_FXF_READ, 0, LIBSSH2_SFTP_OPENFILE);
      if FileH = nil then
        raise Exception.CreateFmt('Cannot open remote file: %s', [P.RemotePath]);
      try
        BS := TBytesStream.Create;
        try
          repeat
            N := ssh2_sftp_read(FileH, @Buf[0], SizeOf(Buf));
            if N > 0 then
              BS.Write(Buf[0], N)
            else if N = 0 then
              Break
            else
              Break;
          until False;
          Bytes := BS.Bytes;
          SetLength(Bytes, BS.Size);
        finally
          BS.Free;
        end;
      finally
        ssh2_sftp_close(FileH);
      end;
    finally
      ssh2_sftp_shutdown(SFTP);
    end;
  finally
    SSHDisconnect;
  end;

  var EncName := LowerCase(Trim(P.Encoding));
  if EncName = '' then EncName := 'utf-8';
  if EncName = 'utf-8' then Enc := TEncoding.UTF8
  else if EncName = 'utf-16' then Enc := TEncoding.Unicode
  else Enc := TEncoding.UTF8;

  Content := Enc.GetString(Bytes);

  Result := TJSONObject.Create;
  Result.AddPair('operation',   'sftp_read');
  Result.AddPair('remote_path', P.RemotePath);
  Result.AddPair('size',        TJSONNumber.Create(Length(Bytes)));
  Result.AddPair('encoding',    EncName);
  Result.AddPair('content',     Content);
end;

// ── sftp_write ───────────────────────────────────────────────────────────────

function TSSHTool.DoSFTPWrite(const P: TSSHParams): TJSONObject;
var
  SFTP    : Pointer;
  FileH   : Pointer;
  Bytes   : TBytes;
  Offset  : Integer;
  N       : NativeInt;
  Written : Int64;
  Enc     : TEncoding;
  RemPath : AnsiString;
begin
  if P.RemotePath = '' then
    raise Exception.Create('"remote_path" is required for sftp_write');

  var EncName := LowerCase(Trim(P.Encoding));
  if EncName = '' then EncName := 'utf-8';
  if EncName = 'utf-8' then Enc := TEncoding.UTF8
  else Enc := TEncoding.UTF8;
  Bytes := Enc.GetBytes(P.Content);

  SSHConnect(P.Host, P.Port, P.Username, P.Password, P.PrivateKeyPath, P.Passphrase, P.TimeoutMs);
  try
    SFTP := ssh2_sftp_init(FSession);
    if SFTP = nil then
      raise Exception.Create('Cannot init SFTP subsystem');
    try
      RemPath := AnsiString(P.RemotePath);
      FileH := ssh2_sftp_open_ex(SFTP,
        PAnsiChar(RemPath), Length(RemPath),
        LIBSSH2_FXF_WRITE or LIBSSH2_FXF_CREAT or LIBSSH2_FXF_TRUNC,
        SFTP_PERM_FILE, LIBSSH2_SFTP_OPENFILE);
      if FileH = nil then
        raise Exception.CreateFmt('Cannot open remote file for writing: %s', [P.RemotePath]);
      try
        Offset  := 0;
        Written := 0;
        while Offset < Length(Bytes) do
        begin
          N := ssh2_sftp_write(FileH, @Bytes[Offset], Length(Bytes) - Offset);
          if N <= 0 then Break;
          Inc(Offset, N);
          Inc(Written, N);
        end;
      finally
        ssh2_sftp_close(FileH);
      end;
    finally
      ssh2_sftp_shutdown(SFTP);
    end;
  finally
    SSHDisconnect;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('operation',        'sftp_write');
  Result.AddPair('remote_path',      P.RemotePath);
  Result.AddPair('bytes_written',    TJSONNumber.Create(Written));
  Result.AddPair('ok',               TJSONBool.Create(Written = Length(Bytes)));
end;

// ── sftp_delete ──────────────────────────────────────────────────────────────

function TSSHTool.DoSFTPDelete(const P: TSSHParams): TJSONObject;
var
  SFTP    : Pointer;
  RC      : Integer;
  RemPath : AnsiString;
begin
  if P.RemotePath = '' then
    raise Exception.Create('"remote_path" is required for sftp_delete');

  SSHConnect(P.Host, P.Port, P.Username, P.Password, P.PrivateKeyPath, P.Passphrase, P.TimeoutMs);
  try
    SFTP := ssh2_sftp_init(FSession);
    if SFTP = nil then
      raise Exception.Create('Cannot init SFTP subsystem');
    try
      RemPath := AnsiString(P.RemotePath);
      RC := ssh2_sftp_unlink(SFTP, PAnsiChar(RemPath), Length(RemPath));
    finally
      ssh2_sftp_shutdown(SFTP);
    end;
  finally
    SSHDisconnect;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('operation',   'sftp_delete');
  Result.AddPair('remote_path', P.RemotePath);
  Result.AddPair('ok',          TJSONBool.Create(RC = 0));
  if RC <> 0 then
    Result.AddPair('error_code', TJSONNumber.Create(RC));
end;

// ── sftp_mkdir ───────────────────────────────────────────────────────────────

function TSSHTool.DoSFTPMkDir(const P: TSSHParams): TJSONObject;
var
  SFTP    : Pointer;
  RC      : Integer;
  RemPath : AnsiString;
begin
  if P.RemotePath = '' then
    raise Exception.Create('"remote_path" is required for sftp_mkdir');

  SSHConnect(P.Host, P.Port, P.Username, P.Password, P.PrivateKeyPath, P.Passphrase, P.TimeoutMs);
  try
    SFTP := ssh2_sftp_init(FSession);
    if SFTP = nil then
      raise Exception.Create('Cannot init SFTP subsystem');
    try
      RemPath := AnsiString(P.RemotePath);
      RC := ssh2_sftp_mkdir(SFTP, PAnsiChar(RemPath), Length(RemPath), SFTP_PERM_DIR);
    finally
      ssh2_sftp_shutdown(SFTP);
    end;
  finally
    SSHDisconnect;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('operation',   'sftp_mkdir');
  Result.AddPair('remote_path', P.RemotePath);
  Result.AddPair('ok',          TJSONBool.Create(RC = 0));
  if RC <> 0 then
    Result.AddPair('error_code', TJSONNumber.Create(RC));
end;

// ── scp_upload (via SFTP) ────────────────────────────────────────────────────

function TSSHTool.DoSCPUpload(const P: TSSHParams): TJSONObject;
var
  SFTP      : Pointer;
  FileH     : Pointer;
  LocalData : TBytes;
  Offset    : Integer;
  N         : NativeInt;
  Written   : Int64;
  RemPath   : AnsiString;
begin
  if P.LocalPath = '' then
    raise Exception.Create('"local_path" is required for scp_upload');
  if P.RemotePath = '' then
    raise Exception.Create('"remote_path" is required for scp_upload');
  if not TFile.Exists(P.LocalPath) then
    raise Exception.CreateFmt('Local file not found: %s', [P.LocalPath]);

  LocalData := TFile.ReadAllBytes(P.LocalPath);

  SSHConnect(P.Host, P.Port, P.Username, P.Password, P.PrivateKeyPath, P.Passphrase, P.TimeoutMs);
  try
    SFTP := ssh2_sftp_init(FSession);
    if SFTP = nil then
      raise Exception.Create('Cannot init SFTP subsystem');
    try
      RemPath := AnsiString(P.RemotePath);
      FileH := ssh2_sftp_open_ex(SFTP,
        PAnsiChar(RemPath), Length(RemPath),
        LIBSSH2_FXF_WRITE or LIBSSH2_FXF_CREAT or LIBSSH2_FXF_TRUNC,
        SFTP_PERM_FILE, LIBSSH2_SFTP_OPENFILE);
      if FileH = nil then
        raise Exception.CreateFmt('Cannot create remote file: %s', [P.RemotePath]);
      try
        Offset  := 0;
        Written := 0;
        while Offset < Length(LocalData) do
        begin
          N := ssh2_sftp_write(FileH, @LocalData[Offset], Length(LocalData) - Offset);
          if N <= 0 then Break;
          Inc(Offset, N);
          Inc(Written, N);
        end;
      finally
        ssh2_sftp_close(FileH);
      end;
    finally
      ssh2_sftp_shutdown(SFTP);
    end;
  finally
    SSHDisconnect;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('operation',        'scp_upload');
  Result.AddPair('local_path',       P.LocalPath);
  Result.AddPair('remote_path',      P.RemotePath);
  Result.AddPair('bytes_transferred',TJSONNumber.Create(Written));
  Result.AddPair('ok',               TJSONBool.Create(Written = Length(LocalData)));
end;

// ── scp_download (via SFTP) ──────────────────────────────────────────────────

function TSSHTool.DoSCPDownload(const P: TSSHParams): TJSONObject;
var
  SFTP    : Pointer;
  FileH   : Pointer;
  Buf     : array[0..65535] of Byte;
  N       : NativeInt;
  BS      : TBytesStream;
  Bytes   : TBytes;
  RemPath : AnsiString;
begin
  if P.RemotePath = '' then
    raise Exception.Create('"remote_path" is required for scp_download');
  if P.LocalPath = '' then
    raise Exception.Create('"local_path" is required for scp_download');

  SSHConnect(P.Host, P.Port, P.Username, P.Password, P.PrivateKeyPath, P.Passphrase, P.TimeoutMs);
  try
    SFTP := ssh2_sftp_init(FSession);
    if SFTP = nil then
      raise Exception.Create('Cannot init SFTP subsystem');
    try
      RemPath := AnsiString(P.RemotePath);
      FileH := ssh2_sftp_open_ex(SFTP,
        PAnsiChar(RemPath), Length(RemPath),
        LIBSSH2_FXF_READ, 0, LIBSSH2_SFTP_OPENFILE);
      if FileH = nil then
        raise Exception.CreateFmt('Cannot open remote file: %s', [P.RemotePath]);
      try
        BS := TBytesStream.Create;
        try
          repeat
            N := ssh2_sftp_read(FileH, @Buf[0], SizeOf(Buf));
            if N > 0 then BS.Write(Buf[0], N)
            else Break;
          until False;
          Bytes := BS.Bytes;
          SetLength(Bytes, BS.Size);
        finally
          BS.Free;
        end;
      finally
        ssh2_sftp_close(FileH);
      end;
    finally
      ssh2_sftp_shutdown(SFTP);
    end;
  finally
    SSHDisconnect;
  end;

  TFile.WriteAllBytes(P.LocalPath, Bytes);

  Result := TJSONObject.Create;
  Result.AddPair('operation',         'scp_download');
  Result.AddPair('remote_path',       P.RemotePath);
  Result.AddPair('local_path',        P.LocalPath);
  Result.AddPair('bytes_transferred', TJSONNumber.Create(Int64(Length(Bytes))));
  Result.AddPair('ok',                TJSONBool.Create(True));
end;

// ── ExecuteWithParams ────────────────────────────────────────────────────────

function TSSHTool.ExecuteWithParams(const AParams: TSSHParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R : TJSONObject;
begin
  Op := LowerCase(Trim(AParams.Operation));
  SSHLog(Format('REQUEST op=%s host=%s:%d user=%s cmd="%s" remote="%s"',
    [Op, AParams.Host, AParams.Port, AParams.Username,
     AParams.Command, AParams.RemotePath]));
  try
    if AParams.Host = '' then
      raise Exception.Create('"host" is required');
    if AParams.Username = '' then
      raise Exception.Create('"username" is required');
    if (AParams.Password = '') and (AParams.PrivateKeyPath = '') then
      raise Exception.Create('either "password" or "private_key_path" is required');

    if      Op = 'exec'         then R := DoExec(AParams)
    else if Op = 'sftp_list'    then R := DoSFTPList(AParams)
    else if Op = 'sftp_read'    then R := DoSFTPRead(AParams)
    else if Op = 'sftp_write'   then R := DoSFTPWrite(AParams)
    else if Op = 'sftp_delete'  then R := DoSFTPDelete(AParams)
    else if Op = 'sftp_mkdir'   then R := DoSFTPMkDir(AParams)
    else if Op = 'scp_upload'   then R := DoSCPUpload(AParams)
    else if Op = 'scp_download' then R := DoSCPDownload(AParams)
    else
      raise Exception.CreateFmt(
        'Unknown operation: "%s". Valid: exec, sftp_list, sftp_read, ' +
        'sftp_write, sftp_delete, sftp_mkdir, scp_upload, scp_download', [Op]);

    SSHLog(Format('RESPONSE op=%s ok=true preview=%s',
      [Op, Copy(R.ToJSON, 1, 120)]));
    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;
  except
    on E: Exception do
    begin
      SSHLog(Format('ERROR op=%s msg="%s"', [Op, E.Message]));
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-ssh]: ' + E.Message)
        .Build;
    end;
  end;
  SSHLogTrim;
end;

// ── Constructor & RegisterTools ──────────────────────────────────────────────

constructor TSSHTool.Create;
begin
  inherited;
  FName := 'mcp-ssh';
  FDescription :=
    'SSH client via libssh2. Connect to remote servers using password or private key. ' +
    'exec: run a command, returns stdout/stderr/exit_code (command required). ' +
    'sftp_list: list remote directory (remote_path required). ' +
    'sftp_read: read remote file as text (remote_path, encoding=utf-8). ' +
    'sftp_write: write text to remote file (remote_path, content). ' +
    'sftp_delete: delete remote file (remote_path). ' +
    'sftp_mkdir: create remote directory (remote_path). ' +
    'scp_upload: upload local file to remote (local_path, remote_path). ' +
    'scp_download: download remote file to local (remote_path, local_path). ' +
    'Auth: password OR private_key_path (PEM) + optional passphrase.';
  FLibHandle  := 0;
  FSession    := nil;
  FTimeoutMs  := 30000;
{$IFDEF MSWINDOWS}
  FSocket := INVALID_SOCKET;
{$ELSE}
  FSocket := THandle(-1);
{$ENDIF}
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-ssh',
    function: IAiMCPTool
    begin
      Result := TSSHTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-ssh');
end;

end.
