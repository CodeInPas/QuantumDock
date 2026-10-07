unit Data.TelemetryLogger;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, sqldb, sqlite3conn, syncobjs, Generics.Collections;

type
  TLogType = (ltInfo, ltWarning, ltCritical, ltCommand, ltMissionResult);

  TLogEntry = record
    LogTime: TDateTime;
    EntryType: TLogType;
    Message: String;
    // Data tambahan untuk Mission Result
    DurationSecs: Double;
    FuelLeft: Double;
    BatteryLeft: Double;
    IntegrityLeft: Double;
  end;

  TLoggerThread = class(TThread)
  private
    FQueue: specialize TQueue<TLogEntry>;
    FLock: TCriticalSection;
    FSignal: TEvent;

    FConnection: TSQLite3Connection;
    FTransaction: TSQLTransaction;
    FQuery: TSQLQuery;

    procedure InitDatabase;
    procedure FlushQueue;
    function LogTypeToStr(ALogType: TLogType): String;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;

    // Prosedur lama untuk System Logs
    procedure AddLog(ALogType: TLogType; const AMessage: String);

    // Prosedur baru untuk menyimpan Mission History
    procedure AddMissionResult(const AStatusMsg: String; ADuration, AFuel, ABattery, AIntegrity: Double);
  end;

  TTelemetryLogger = class
  private
    class var FLoggerThread: TLoggerThread;
  public
    class procedure Initialize;
    class procedure Shutdown;
    class procedure LogInfo(const AMsg: String);
    class procedure LogWarning(const AMsg: String);
    class procedure LogCritical(const AMsg: String);
    class procedure LogCommand(const AMsg: String);

    // Wrapper baru untuk mencatat akhir permainan
    class procedure LogMission(const AFinalStatus: String; ADuration, AFuel, ABattery, AIntegrity: Double);
  end;

implementation

{ TLoggerThread }

constructor TLoggerThread.Create;
begin
  inherited Create(False);
  FreeOnTerminate := False;

  FQueue := specialize TQueue<TLogEntry>.Create;
  FLock := TCriticalSection.Create;
  FSignal := TEvent.Create(nil, False, False, '');

  InitDatabase;
end;

destructor TLoggerThread.Destroy;
begin
  Terminate;
  FSignal.SetEvent;
  WaitFor;

  FlushQueue;

  FQuery.Free;
  FTransaction.Free;
  FConnection.Free;

  FSignal.Free;
  FLock.Free;
  FQueue.Free;
  inherited Destroy;
end;

procedure TLoggerThread.InitDatabase;
var
  DbPath: String;
begin
  DbPath := ExtractFilePath(ParamStr(0)) + 'assets' + DirectorySeparator + 'db' + DirectorySeparator + 'telemetry.db';

  ForceDirectories(ExtractFilePath(DbPath));

  FConnection := TSQLite3Connection.Create(nil);
  FTransaction := TSQLTransaction.Create(nil);
  FQuery := TSQLQuery.Create(nil);

  FConnection.DatabaseName := DbPath;
  FConnection.Transaction := FTransaction;

  FQuery.Database := FConnection;
  FQuery.Transaction := FTransaction;

  try
    FConnection.Open;
    FTransaction.StartTransaction;

    // Tabel 1: system_logs (yang sudah ada)
    FConnection.ExecuteDirect(
      'CREATE TABLE IF NOT EXISTS system_logs (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, ' +
      'log_type VARCHAR(20), ' +
      'message TEXT);'
    );

    // Tabel 2: mission_history (Tabel Baru)
    FConnection.ExecuteDirect(
      'CREATE TABLE IF NOT EXISTS mission_history (' +
      'mission_id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'end_time DATETIME DEFAULT CURRENT_TIMESTAMP, ' +
      'status VARCHAR(50), ' +
      'duration_sec REAL, ' +
      'fuel_rem REAL, ' +
      'battery_rem REAL, ' +
      'integrity_rem REAL);'
    );

    FTransaction.Commit;
  except
    on E: Exception do
    begin
      if FTransaction.Active then FTransaction.Rollback;
    end;
  end;
end;

function TLoggerThread.LogTypeToStr(ALogType: TLogType): String;
begin
  case ALogType of
    ltInfo: Result := 'INFO';
    ltWarning: Result := 'WARNING';
    ltCritical: Result := 'CRITICAL';
    ltCommand: Result := 'COMMAND';
    ltMissionResult: Result := 'MISSION_END';
    else Result := 'UNKNOWN';
  end;
end;

procedure TLoggerThread.AddLog(ALogType: TLogType; const AMessage: String);
var
  Entry: TLogEntry;
begin
  Entry.LogTime := Now;
  Entry.EntryType := ALogType;
  Entry.Message := AMessage;

  FLock.Acquire;
  try
    FQueue.Enqueue(Entry);
  finally
    FLock.Release;
  end;

  FSignal.SetEvent;
end;

procedure TLoggerThread.AddMissionResult(const AStatusMsg: String; ADuration, AFuel, ABattery, AIntegrity: Double);
var
  Entry: TLogEntry;
begin
  Entry.LogTime := Now;
  Entry.EntryType := ltMissionResult;
  Entry.Message := AStatusMsg;
  Entry.DurationSecs := ADuration;
  Entry.FuelLeft := AFuel;
  Entry.BatteryLeft := ABattery;
  Entry.IntegrityLeft := AIntegrity;

  FLock.Acquire;
  try
    FQueue.Enqueue(Entry);
  finally
    FLock.Release;
  end;

  FSignal.SetEvent;
end;

procedure TLoggerThread.FlushQueue;
var
  Entry: TLogEntry;
begin
  if not FConnection.Connected then Exit;

  FLock.Acquire;
  try
    if FQueue.Count > 0 then
    begin
      FTransaction.StartTransaction;
      try
        while FQueue.Count > 0 do
        begin
          Entry := FQueue.Dequeue;

          if Entry.EntryType = ltMissionResult then
          begin
            // Masukkan ke tabel mission_history
            FQuery.SQL.Text := 'INSERT INTO mission_history (end_time, status, duration_sec, fuel_rem, battery_rem, integrity_rem) ' +
                               'VALUES (:ts, :status, :dur, :fuel, :bat, :integ)';
            FQuery.ParamByName('ts').AsDateTime := Entry.LogTime;
            FQuery.ParamByName('status').AsString := Entry.Message;
            FQuery.ParamByName('dur').AsFloat := Entry.DurationSecs;
            FQuery.ParamByName('fuel').AsFloat := Entry.FuelLeft;
            FQuery.ParamByName('bat').AsFloat := Entry.BatteryLeft;
            FQuery.ParamByName('integ').AsFloat := Entry.IntegrityLeft;
          end
          else
          begin
            // Masukkan ke tabel system_logs
            FQuery.SQL.Text := 'INSERT INTO system_logs (timestamp, log_type, message) VALUES (:ts, :type, :msg)';
            FQuery.ParamByName('ts').AsDateTime := Entry.LogTime;
            FQuery.ParamByName('type').AsString := LogTypeToStr(Entry.EntryType);
            FQuery.ParamByName('msg').AsString := Entry.Message;
          end;

          FQuery.ExecSQL;
        end;
        FTransaction.Commit;
      except
        FTransaction.Rollback;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TLoggerThread.Execute;
begin
  while not Terminated do
  begin
    if FSignal.WaitFor(1000) = wrSignaled then
    begin
      if Terminated then Break;
      FlushQueue;
    end
    else
    begin
      if not Terminated then FlushQueue;
    end;
  end;
end;

{ TTelemetryLogger }

class procedure TTelemetryLogger.Initialize;
begin
  if not Assigned(FLoggerThread) then
    FLoggerThread := TLoggerThread.Create;
end;

class procedure TTelemetryLogger.Shutdown;
begin
  if Assigned(FLoggerThread) then
  begin
    FLoggerThread.Free;
    FLoggerThread := nil;
  end;
end;

class procedure TTelemetryLogger.LogInfo(const AMsg: String);
begin
  if Assigned(FLoggerThread) then FLoggerThread.AddLog(ltInfo, AMsg);
end;

class procedure TTelemetryLogger.LogWarning(const AMsg: String);
begin
  if Assigned(FLoggerThread) then FLoggerThread.AddLog(ltWarning, AMsg);
end;

class procedure TTelemetryLogger.LogCritical(const AMsg: String);
begin
  if Assigned(FLoggerThread) then FLoggerThread.AddLog(ltCritical, AMsg);
end;

class procedure TTelemetryLogger.LogCommand(const AMsg: String);
begin
  if Assigned(FLoggerThread) then FLoggerThread.AddLog(ltCommand, AMsg);
end;

class procedure TTelemetryLogger.LogMission(const AFinalStatus: String; ADuration, AFuel, ABattery, AIntegrity: Double);
begin
  if Assigned(FLoggerThread) then
    FLoggerThread.AddMissionResult(AFinalStatus, ADuration, AFuel, ABattery, AIntegrity);
end;

end.
