unit Engine.PhysicsThread;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows, syncobjs, Game.State;

type
  { TPhysicsThread: Menjalankan simulasi fisika secara konstan di background.
    Memisahkan kalkulasi berat (integrasi orbit, gravitasi) dari Main UI Thread. }
  TPhysicsThread = class(TThread)
  private
    FGameState: TGameState;
    FStateLock: TCriticalSection;
    FTargetTPS: Integer; // Ticks Per Second (Target update rate)
  protected
    procedure Execute; override;
  public
    constructor Create(AGameState: TGameState; ATargetTPS: Integer = 60);
    destructor Destroy; override;

    { Digunakan oleh Main Thread (Renderer/UI) untuk membaca state dengan aman }
    procedure LockState;
    procedure UnlockState;
  end;

implementation

{ TPhysicsThread }

constructor TPhysicsThread.Create(AGameState: TGameState; ATargetTPS: Integer);
begin
  inherited Create(False); // Langsung berjalan
  FreeOnTerminate := False;
  FGameState := AGameState;
  FStateLock := TCriticalSection.Create;
  FTargetTPS := ATargetTPS;
  Priority := tpTimeCritical; // Prioritas tinggi untuk stabilitas fisika
end;

destructor TPhysicsThread.Destroy;
begin
  Terminate;
  WaitFor;
  FStateLock.Free;
  inherited Destroy;
end;

procedure TPhysicsThread.LockState;
begin
  FStateLock.Acquire;
end;

procedure TPhysicsThread.UnlockState;
begin
  FStateLock.Release;
end;

procedure TPhysicsThread.Execute;
var
  LastTime, CurrentTime, Freq: Int64;
  DeltaTime: Double;
  TargetTickTime: Double;
  SleepTime: Integer;
begin
  // Menggunakan High-Resolution Performance Counter untuk presisi waktu (Membutuhkan unit Windows)
  QueryPerformanceFrequency(Freq);
  QueryPerformanceCounter(LastTime);

  TargetTickTime := 1.0 / FTargetTPS;

  while not Terminated do
  begin
    QueryPerformanceCounter(CurrentTime);
    DeltaTime := (CurrentTime - LastTime) / Freq;

    // Mencegah 'Spiral of Death' jika thread tertahan/lagging (cap max delta time)
    if DeltaTime > 0.1 then
      DeltaTime := 0.1;

    LastTime := CurrentTime;

    // Update Physics State (Thread-Safe)
    FStateLock.Acquire;
    try
      if Assigned(FGameState) then
        FGameState.Update(DeltaTime);
    finally
      FStateLock.Release;
    end;

    // Kalkulasi sisa waktu untuk mencapai Target TPS
    QueryPerformanceCounter(CurrentTime);
    SleepTime := Trunc(((TargetTickTime - ((CurrentTime - LastTime) / Freq)) * 1000));

    if SleepTime > 0 then
      Sleep(SleepTime)
    else
      Sleep(1); // Yield ke OS agar tidak monopolize CPU 100%
  end;
end;

end.
