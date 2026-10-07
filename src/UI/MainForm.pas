unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, LCLIntf, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, SimGauges, SimPushButton, SimSelectorSwitch, SimFader,
  SimLedBarGraph, SimIndicators, SimLcdDisplay, SimInputs, SimJoystick,
  SimThrottleLever, SimContainers, Game.State, Engine.PhysicsThread,
  Engine.RendererBGRA, Data.TelemetryLogger, Engine.Audio, UnitAbout;

type
  { TFormMain }
  TFormMain = class(TForm)
    btnBurn10: TSimPushButton;
    btnBurn30: TSimPushButton;
    btnBurn60: TSimPushButton;
    btnBurnCustom: TSimPushButton;
    btnExecute: TSimPushButton;
    btnReset: TSimPushButton;
    lblAlignLabel: TLabel;
    lblAlignVal: TLabel;
    lblAngleLabel: TSevenSegment;
    lblApoLabel: TLabel;
    lblApoVal: TLabel;
    lblIntegrityVal: TSimLedBarGraph;
    lblBatteryVal1: TSimLedBarGraph;
    lblFuelVal: TCircularGauge;
    lblControlBoardTitle: TLabel;
    lblOrbitalMapTitle: TLabel;
    lblPerLabel: TLabel;
    lblPerVal: TLabel;
    lblPowerLabel: TSevenSegment;
    lblTelemetryTitle: TLabel;
    lblThrustTitle1: TLabel;
    lblVelLabel: TLabel;
    lblVelVal: TLabel;
    MainMenu1: TMainMenu;
    memoTerminal: TMemo;
    MenuItem1: TMenuItem;
    MenuItem2: TMenuItem;
    mnTerminate: TMenuItem;
    mnHelp: TMenuItem;
    MenuItem6: TMenuItem;
    Panel1: TPanel;
    Panel2: TPanel;
    Panel3: TPanel;
    Panel4: TPanel;
    Panel5: TPanel;
    Panel6: TPanel;
    Panel8: TPanel;
    Panel9: TPanel;
    pbOrbitalMap: TPaintBox;
    pnlControlBoard: TPanel;
    pnlOrbitalMap: TPanel;
    pnlTelemetry: TPanel;
    tbAngle: TSimFader;
    tbPower: TSimFader;
    tmrUIUpdate: TTimer;
    procedure btnBurn10Click(Sender: TObject);
    procedure btnBurn30Click(Sender: TObject);
    procedure btnBurn60Click(Sender: TObject);
    procedure btnBurnCustomClick(Sender: TObject);
    procedure btnExecuteClick(Sender: TObject);
    procedure btnResetClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure MenuItem6Click(Sender: TObject);
    procedure mnHelpClick(Sender: TObject);
    procedure mnTerminateClick(Sender: TObject);
    procedure pbOrbitalMapPaint(Sender: TObject);
    procedure pbOrbitalMapResize(Sender: TObject);
    procedure tbPowerChange(Sender: TObject);
    procedure tbAngleChange(Sender: TObject);
    procedure tmrUIUpdateTimer(Sender: TObject);
  private
    FGameState: TGameState;
    FPhysicsThread: TPhysicsThread;
    FRenderer: TRendererBGRA;
    FLastStatus: TGameStatus;

    FLastCapsuleActive: Boolean;

    FSelectedBurnDuration: Double;
    FTargetBurnStopTime: Double;

    procedure ResetBurnButtons;
    procedure UpdateTerminalLog(const AMsg: String);
  public
  end;

var
  FormMain: TFormMain;

implementation

{$R *.lfm}

{ TFormMain }

procedure TFormMain.FormCreate(Sender: TObject);
begin
  TTelemetryLogger.Initialize;
  TTelemetryLogger.LogInfo('SYS INIT: COMPLETE');

  AudioEngine := TAudioEngine.Create;
  AudioEngine.PlayAmbient;

  FGameState := TGameState.Create;
  FGameState.InitializeMission;
  FLastStatus := FGameState.Status;

  FLastCapsuleActive := FGameState.FuelCapsule.Active;

  FRenderer := TRendererBGRA.Create(FGameState);

  FPhysicsThread := TPhysicsThread.Create(FGameState, 60);

  FSelectedBurnDuration := 10.0;
  FTargetBurnStopTime := -1.0;

  btnBurn10.Font.Style := [fsBold];

  tbAngle.Value := 15;
  lblAngleLabel.Value := 15;

  tbPower.Value := 85;
  lblPowerLabel.Value := 85;

  FRenderer.SetPredictedManeuver(tbPower.Value, tbAngle.Value, FSelectedBurnDuration);

  lblVelLabel.Caption := 'Rel.Vel:';

  UpdateTerminalLog('> SYS INIT: COMPLETE');
  UpdateTerminalLog('> ORBITAL MAP: ACTIVE');
  UpdateTerminalLog('> CARGO MODULE-4 STATUS: NOMINAL');
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  tmrUIUpdate.Enabled := False;

  if Assigned(FPhysicsThread) then
  begin
    FPhysicsThread.Terminate;
    FPhysicsThread.WaitFor;
    FPhysicsThread.Free;
  end;

  if Assigned(FRenderer) then FRenderer.Free;
  if Assigned(FGameState) then FGameState.Free;
  if Assigned(AudioEngine) then AudioEngine.Free;

  TTelemetryLogger.Shutdown;
end;

procedure TFormMain.MenuItem6Click(Sender: TObject);
begin
  FormAbout.ShowModal;
end;

procedure TFormMain.mnHelpClick(Sender: TObject);
begin
  OpenDocument(ExtractFilePath(Application.ExeName) + 'tutorial_quantumdoc.pdf');
end;

procedure TFormMain.mnTerminateClick(Sender: TObject);
begin
  Application.Terminate;
end;

procedure TFormMain.btnResetClick(Sender: TObject);
begin
  FPhysicsThread.LockState;
  try
    FGameState.InitializeMission;
    FLastStatus := FGameState.Status;

    FLastCapsuleActive := FGameState.FuelCapsule.Active;

    FSelectedBurnDuration := 10.0;
    FTargetBurnStopTime := -1.0;

    ResetBurnButtons;
    btnBurn10.Font.Style := [fsBold];
    tbPower.Value := 85;
    tbAngle.Value := 15;

    FRenderer.SetPredictedManeuver(tbPower.Value, tbAngle.Value, FSelectedBurnDuration);
  finally
    FPhysicsThread.UnlockState;
  end;

  memoTerminal.Lines.Clear;
  UpdateTerminalLog('> SYSTEM REBOOT INITIATED...');
  UpdateTerminalLog('> NEW MISSION PARAMETERS GENERATED');
  UpdateTerminalLog('> CARGO MODULE-4 STATUS: NOMINAL');

  if Assigned(AudioEngine) then
  begin
    AudioEngine.PlayAlarm(False);
    AudioEngine.SetEngineThrust(0.0);
  end;
end;

procedure TFormMain.ResetBurnButtons;
begin
  btnBurn10.Font.Style := [];
  btnBurn30.Font.Style := [];
  btnBurn60.Font.Style := [];
  btnBurnCustom.Font.Style := [];
end;

procedure TFormMain.btnBurn10Click(Sender: TObject);
begin
  ResetBurnButtons;
  btnBurn10.Font.Style := [fsBold];
  FSelectedBurnDuration := 10.0;
  FRenderer.SetPredictedManeuver(tbPower.Value, tbAngle.Value, FSelectedBurnDuration);
  UpdateTerminalLog('> MANEUVER DURATION SET: 10s');
end;

procedure TFormMain.btnBurn30Click(Sender: TObject);
begin
  ResetBurnButtons;
  btnBurn30.Font.Style := [fsBold];
  FSelectedBurnDuration := 30.0;
  FRenderer.SetPredictedManeuver(tbPower.Value, tbAngle.Value, FSelectedBurnDuration);
  UpdateTerminalLog('> MANEUVER DURATION SET: 30s');
end;

procedure TFormMain.btnBurn60Click(Sender: TObject);
begin
  ResetBurnButtons;
  btnBurn60.Font.Style := [fsBold];
  FSelectedBurnDuration := 60.0;
  FRenderer.SetPredictedManeuver(tbPower.Value, tbAngle.Value, FSelectedBurnDuration);
  UpdateTerminalLog('> MANEUVER DURATION SET: 60s');
end;

procedure TFormMain.btnBurnCustomClick(Sender: TObject);
var
  InputStr: String;
  Val: Integer;
begin
  InputStr := InputBox('Custom Burn', 'Enter duration in seconds (1-300):', '45');
  if TryStrToInt(InputStr, Val) then
  begin
    if (Val > 0) and (Val <= 300) then
    begin
      ResetBurnButtons;
      btnBurnCustom.Font.Style := [fsBold];
      FSelectedBurnDuration := Val;
      FRenderer.SetPredictedManeuver(tbPower.Value, tbAngle.Value, FSelectedBurnDuration);
      UpdateTerminalLog('> MANEUVER DURATION SET: ' + IntToStr(Val) + 's');
    end
    else
      ShowMessage('Error: Duration must be between 1 and 300 seconds.');
  end;
end;

procedure TFormMain.pbOrbitalMapPaint(Sender: TObject);
begin
  if Assigned(FRenderer) then
    FRenderer.Render(pbOrbitalMap.Canvas);
end;

procedure TFormMain.pbOrbitalMapResize(Sender: TObject);
begin
  if Assigned(FRenderer) then
    FRenderer.Resize(pbOrbitalMap.Width, pbOrbitalMap.Height);
end;

procedure TFormMain.tbPowerChange(Sender: TObject);
begin
  lblPowerLabel.Value := Trunc(tbPower.Value);
  if Assigned(FRenderer) then
    FRenderer.SetPredictedManeuver(tbPower.Value, tbAngle.Value, FSelectedBurnDuration);
end;

procedure TFormMain.tbAngleChange(Sender: TObject);
begin
  lblAngleLabel.Value := Trunc(tbAngle.Value);
  if Assigned(FRenderer) then
    FRenderer.SetPredictedManeuver(tbPower.Value, tbAngle.Value, FSelectedBurnDuration);
end;

procedure TFormMain.UpdateTerminalLog(const AMsg: String);
begin
  if memoTerminal.Lines.Count > 25 then
    memoTerminal.Lines.Delete(0);

  memoTerminal.Lines.Add(AMsg);
  memoTerminal.SelStart := Length(memoTerminal.Text);
end;

procedure TFormMain.btnExecuteClick(Sender: TObject);
var
  Power, Angle: Double;
  Msg: String;
begin
  Power := tbPower.Value;
  Angle := tbAngle.Value;

  FPhysicsThread.LockState;
  try
    FGameState.Cargo.SetManeuverNode(Power, Angle);
    FGameState.Cargo.ExecuteBurn(True);

    if FSelectedBurnDuration > 0 then
      FTargetBurnStopTime := FGameState.TimeElapsed + FSelectedBurnDuration
    else
      FTargetBurnStopTime := -1.0;
  finally
    FPhysicsThread.UnlockState;
  end;

  if Assigned(AudioEngine) then
    AudioEngine.SetEngineThrust(Power);

  Msg := Format('> COMMAND > sys.override_thrust --power %d%% --angle %d --duration %ds', [Round(Power), Round(Angle), Round(FSelectedBurnDuration)]);
  UpdateTerminalLog(Msg);
  TTelemetryLogger.LogCommand(Msg);
end;

procedure TFormMain.tmrUIUpdateTimer(Sender: TObject);
var
  StationVelX, StationVelY, RelVelX, RelVelY, RelVelMag: Double;
begin
  pbOrbitalMap.Invalidate;

  FPhysicsThread.LockState;
  try
    if FGameState.Cargo.IsThrusting and (FTargetBurnStopTime > 0) then
    begin
      if FGameState.TimeElapsed >= FTargetBurnStopTime then
      begin
        FGameState.Cargo.ExecuteBurn(False);
        FTargetBurnStopTime := -1.0;

        if Assigned(AudioEngine) then
          AudioEngine.SetEngineThrust(0.0);

        UpdateTerminalLog('> STATUS: MANEUVER COMPLETE (AUTO-CUTOFF)');
      end;
    end;

    if FLastCapsuleActive and not FGameState.FuelCapsule.Active then
    begin
      UpdateTerminalLog('> EVENT: FUEL CAPSULE INTERCEPTED');
      UpdateTerminalLog(Format('> SYS: REFUELING COMPLETE. CURRENT: %d%%', [Trunc(FGameState.Cargo.Fuel)]));
      FLastCapsuleActive := False;
    end;

    lblFuelVal.Value := Trunc(FGameState.Cargo.Fuel);
    lblBatteryVal1.Value := Trunc(FGameState.Cargo.Battery);
    lblIntegrityVal.Value := Trunc(FGameState.Cargo.Integrity);

    // --- MENGUNCI TOMBOL EXECUTE JIKA BAHAN BAKAR HABIS ATAU GAME OVER ---
    btnExecute.Enabled := (FGameState.Cargo.Fuel > 0.0) and
                          (FGameState.Status in [gsNominal, gsCritical]);

    // Force cutoff jika sedang thrusting tapi bahan bakar tiba-tiba habis
    if (not btnExecute.Enabled) and FGameState.Cargo.IsThrusting then
    begin
      FGameState.Cargo.ExecuteBurn(False);
      FTargetBurnStopTime := -1.0;
      if Assigned(AudioEngine) then
        AudioEngine.SetEngineThrust(0.0);
    end;

    StationVelX := -FGameState.Station.AngularSpeed * FGameState.Station.OrbitRadius * Sin(FGameState.Station.OrbitAngle);
    StationVelY := FGameState.Station.AngularSpeed * FGameState.Station.OrbitRadius * Cos(FGameState.Station.OrbitAngle);

    RelVelX := FGameState.Cargo.Velocity.X - StationVelX;
    RelVelY := FGameState.Cargo.Velocity.Y - StationVelY;

    RelVelMag := Sqrt(Sqr(RelVelX) + Sqr(RelVelY));
    lblVelVal.Caption := FormatFloat('#,##0.0 m/s', RelVelMag);

    if RelVelMag > 100.0 then
      lblVelVal.Font.Color := clRed
    else
      lblVelVal.Font.Color := clLime;

    if FGameState.Apoapsis < 0 then
      lblApoVal.Caption := 'ESCAPE'
    else
      lblApoVal.Caption := FormatFloat('#,##0.0 km', FGameState.Apoapsis / 100.0);

    lblPerVal.Caption := FormatFloat('#,##0.0 km', FGameState.Periapsis / 100.0);
    lblAlignVal.Caption := FormatFloat('0.0 "%"', FGameState.Alignment);

    if FGameState.Alignment >= 90.0 then
      lblAlignVal.Font.Color := clLime
    else if FGameState.Alignment >= 50.0 then
      lblAlignVal.Font.Color := clYellow
    else
      lblAlignVal.Font.Color := clRed;

    if FGameState.Status = gsCritical then
      pnlOrbitalMap.Color := $000000AA
    else
      pnlOrbitalMap.Color := $00F2E8E6;

    if FGameState.Status <> FLastStatus then
    begin
      case FGameState.Status of
        gsCritical:
        begin
          UpdateTerminalLog('> WARNING: ORBITAL DECAY / SIGNAL LOSS IMMINENT');
          if Assigned(AudioEngine) then AudioEngine.PlayAlarm(True);
        end;
        gsNominal:
        begin
          if FLastStatus = gsCritical then
          begin
            UpdateTerminalLog('> STATUS: ORBIT STABILIZED');
            if Assigned(AudioEngine) then AudioEngine.PlayAlarm(False);
          end;
        end;
        gsMissionFailed:
        begin
          UpdateTerminalLog('> CRITICAL FAILURE: HULL BREACH / SIGNAL LOST');
          if Assigned(AudioEngine) then
          begin
            AudioEngine.PlayAlarm(True);
            AudioEngine.SetEngineThrust(0.0);
          end;
          TTelemetryLogger.LogMission('FAILED', FGameState.TimeElapsed, FGameState.Cargo.Fuel, FGameState.Cargo.Battery, FGameState.Cargo.Integrity);
        end;
        gsDockingSuccess:
        begin
          UpdateTerminalLog('> SUCCESS: CARGO DOCKED SECURELY');
          if Assigned(AudioEngine) then
          begin
            AudioEngine.PlayAlarm(False);
            AudioEngine.SetEngineThrust(0.0);
          end;
          TTelemetryLogger.LogMission('SUCCESS', FGameState.TimeElapsed, FGameState.Cargo.Fuel, FGameState.Cargo.Battery, FGameState.Cargo.Integrity);
        end;
      end;
      FLastStatus := FGameState.Status;
    end;

  finally
    FPhysicsThread.UnlockState;
  end;
end;

end.
