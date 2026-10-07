unit Game.State;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Game.CargoEntity;

type
  TGameStatus = (gsInitializing, gsNominal, gsCritical, gsMissionFailed, gsDockingSuccess);

  TCelestialBody = record
    Position: TVector2D;
    Mass: Double;
    Radius: Double;
  end;

  TDockingStation = record
    Position: TVector2D;
    OrbitRadius: Double;
    OrbitAngle: Double;
    AngularSpeed: Double;
    DockingTolerance: Double;
    MaxSafeVelocity: Double;
  end;

  TFuelCapsule = record
    Active: Boolean;
    Position: TVector2D;
    Velocity: TVector2D;
    Radius: Double;
    FuelAmount: Double;
  end;

  TGameState = class
  private
    FStatus: TGameStatus;
    FCargo: TCargoEntity;
    FPlanet: TCelestialBody;
    FStation: TDockingStation;
    FFuelCapsule: TFuelCapsule;

    FTimeElapsed: Double;
    FGravitationalConstant: Double;

    FApoapsis: Double;
    FPeriapsis: Double;
    FAlignment: Double;

    procedure CalculateGravityForce(DeltaTime: Double);
    procedure UpdateStationPosition(DeltaTime: Double);

    procedure UpdateCapsulePhysics(DeltaTime: Double);
    procedure CheckCapsuleCollection;

    procedure EvaluateWinLossConditions;
    procedure CalculateTelemetry;
  public
    constructor Create;
    destructor Destroy; override;

    procedure InitializeMission;
    procedure Update(DeltaTime: Double);

    property Status: TGameStatus read FStatus write FStatus;
    property Cargo: TCargoEntity read FCargo;
    property Planet: TCelestialBody read FPlanet;
    property Station: TDockingStation read FStation;
    property FuelCapsule: TFuelCapsule read FFuelCapsule;
    property TimeElapsed: Double read FTimeElapsed;

    property GravitationalConstant: Double read FGravitationalConstant;
    property Apoapsis: Double read FApoapsis;
    property Periapsis: Double read FPeriapsis;
    property Alignment: Double read FAlignment;
  end;

implementation

{ TGameState }

constructor TGameState.Create;
begin
  inherited Create;
  FCargo := TCargoEntity.Create;
  FGravitationalConstant := 6.67430e-1;
  FStatus := gsInitializing;
end;

destructor TGameState.Destroy;
begin
  FCargo.Free;
  inherited Destroy;
end;

procedure TGameState.InitializeMission;
var
  InitPos, InitVel: TVector2D;
  CargoAngle, CargoRadius, CargoSpeed: Double;
  CapRadius, CapAngle, CapSpeed: Double;
begin
  Randomize;

  FTimeElapsed := 0.0;
  FStatus := gsNominal;

  FPlanet.Position.X := 0.0;
  FPlanet.Position.Y := 0.0;
  FPlanet.Mass := 5000000.0;
  FPlanet.Radius := 6000.0;

  FStation.OrbitRadius := 8500.0;
  FStation.OrbitAngle := Random * 2 * PI;
  FStation.AngularSpeed := 0.02;
  FStation.DockingTolerance := 800.0;
  FStation.MaxSafeVelocity := 100.0;

  FCargo.Mass := 18.5;
  FCargo.Fuel := 67.4;
  FCargo.Battery := 91.0;
  FCargo.Integrity := 100.0;

  CargoRadius := 8000.0 + (Random * 3000.0);

  CargoAngle := Random * 2 * PI;

  InitPos.X := CargoRadius * Cos(CargoAngle);
  InitPos.Y := CargoRadius * Sin(CargoAngle);
  FCargo.Position := InitPos;

  CargoSpeed := 180.0 + (Random * 50.0);
  InitVel.X := -CargoSpeed * Sin(CargoAngle);
  InitVel.Y := CargoSpeed * Cos(CargoAngle);
  FCargo.Velocity := InitVel;

  FFuelCapsule.Active := True;
  FFuelCapsule.Radius := 50.0;
  FFuelCapsule.FuelAmount := 135.0;

  // --- REVISI ZONA MUNCUL KAPSUL ---
  // Radius diperketat antara 8000 - 10500 agar selalu dekat dengan stasiun dan rute kargo
  CapRadius := 8000.0 + (Random * 2500.0);
  CapAngle := Random * 2 * PI;

  FFuelCapsule.Position.X := CapRadius * Cos(CapAngle);
  FFuelCapsule.Position.Y := CapRadius * Sin(CapAngle);

  // Kecepatan dibuat lebih stabil agar orbit kapsul lebih melingkar (tidak terlempar jauh)
  CapSpeed := 160.0 + (Random * 40.0);
  FFuelCapsule.Velocity.X := -CapSpeed * Sin(CapAngle);
  FFuelCapsule.Velocity.Y := CapSpeed * Cos(CapAngle);
end;

procedure TGameState.CalculateGravityForce(DeltaTime: Double);
var
  DistanceX, DistanceY, DistanceSq, Distance: Double;
  ForceG, AccelG, AngleRadian: Double;
  TempVel: TVector2D;
begin
  DistanceX := FPlanet.Position.X - FCargo.Position.X;
  DistanceY := FPlanet.Position.Y - FCargo.Position.Y;
  DistanceSq := Sqr(DistanceX) + Sqr(DistanceY);

  if DistanceSq <= 0.1 then Exit;

  Distance := Sqrt(DistanceSq);
  ForceG := FGravitationalConstant * (FPlanet.Mass * FCargo.Mass) / DistanceSq;
  AccelG := ForceG / FCargo.Mass;
  AngleRadian := ArcTan2(DistanceY, DistanceX);

  TempVel := FCargo.Velocity;
  TempVel.X := TempVel.X + (AccelG * Cos(AngleRadian) * DeltaTime);
  TempVel.Y := TempVel.Y + (AccelG * Sin(AngleRadian) * DeltaTime);
  FCargo.Velocity := TempVel;
end;

procedure TGameState.UpdateCapsulePhysics(DeltaTime: Double);
var
  DistanceX, DistanceY, DistanceSq: Double;
  AccelG, AngleRadian: Double;
begin
  if not FFuelCapsule.Active then Exit;

  DistanceX := FPlanet.Position.X - FFuelCapsule.Position.X;
  DistanceY := FPlanet.Position.Y - FFuelCapsule.Position.Y;
  DistanceSq := Sqr(DistanceX) + Sqr(DistanceY);

  if DistanceSq <= Sqr(FPlanet.Radius) then
  begin
    FFuelCapsule.Active := False;
    Exit;
  end;

  if DistanceSq > 0.1 then
  begin
    AccelG := (FGravitationalConstant * FPlanet.Mass) / DistanceSq;
    AngleRadian := ArcTan2(DistanceY, DistanceX);

    FFuelCapsule.Velocity.X := FFuelCapsule.Velocity.X + (AccelG * Cos(AngleRadian) * DeltaTime);
    FFuelCapsule.Velocity.Y := FFuelCapsule.Velocity.Y + (AccelG * Sin(AngleRadian) * DeltaTime);
  end;

  FFuelCapsule.Position.X := FFuelCapsule.Position.X + (FFuelCapsule.Velocity.X * DeltaTime);
  FFuelCapsule.Position.Y := FFuelCapsule.Position.Y + (FFuelCapsule.Velocity.Y * DeltaTime);
end;

procedure TGameState.CheckCapsuleCollection;
var
  DistSq: Double;
begin
  if not FFuelCapsule.Active then Exit;

  DistSq := Sqr(FCargo.Position.X - FFuelCapsule.Position.X) + Sqr(FCargo.Position.Y - FFuelCapsule.Position.Y);

  if DistSq <= Sqr(FFuelCapsule.Radius) then
  begin
    FFuelCapsule.Active := False;

    FCargo.Fuel := FCargo.Fuel + FFuelCapsule.FuelAmount;
    if FCargo.Fuel > 100.0 then
      FCargo.Fuel := 100.0;
  end;
end;

procedure TGameState.UpdateStationPosition(DeltaTime: Double);
begin
  FStation.OrbitAngle := FStation.OrbitAngle + (FStation.AngularSpeed * DeltaTime);
  if FStation.OrbitAngle > (2 * PI) then
    FStation.OrbitAngle := FStation.OrbitAngle - (2 * PI);

  FStation.Position.X := FPlanet.Position.X + (FStation.OrbitRadius * Cos(FStation.OrbitAngle));
  FStation.Position.Y := FPlanet.Position.Y + (FStation.OrbitRadius * Sin(FStation.OrbitAngle));
end;

procedure TGameState.CalculateTelemetry;
var
  RelativeX, RelativeY, r, v, mu, epsilon, a, h, eSq, e: Double;
  AngleCargo, AngleDiff: Double;
begin
  RelativeX := FCargo.Position.X - FPlanet.Position.X;
  RelativeY := FCargo.Position.Y - FPlanet.Position.Y;

  r := Sqrt(Sqr(RelativeX) + Sqr(RelativeY));
  v := Sqrt(Sqr(FCargo.Velocity.X) + Sqr(FCargo.Velocity.Y));
  mu := FGravitationalConstant * FPlanet.Mass;

  if r > 0.1 then
  begin
    epsilon := (Sqr(v) / 2.0) - (mu / r);
    h := (RelativeX * FCargo.Velocity.Y) - (RelativeY * FCargo.Velocity.X);

    if epsilon < 0 then
    begin
      a := -mu / (2.0 * epsilon);
      eSq := 1.0 + ((2.0 * epsilon * Sqr(h)) / Sqr(mu));
      if eSq < 0 then eSq := 0;
      e := Sqrt(eSq);

      FApoapsis := a * (1.0 + e);
      FPeriapsis := a * (1.0 - e);
    end
    else
    begin
      FApoapsis := -1;
      FPeriapsis := r;
    end;
  end;

  AngleCargo := ArcTan2(RelativeY, RelativeX);
  AngleDiff := Abs(AngleCargo - FStation.OrbitAngle);

  while AngleDiff > PI do
    AngleDiff := (2 * PI) - AngleDiff;

  FAlignment := Max(0.0, 100.0 * (1.0 - (AngleDiff / PI)));
end;

procedure TGameState.EvaluateWinLossConditions;
var
  DistToPlanetSq, DistToStationSq, RelVelocitySq: Double;
  StationVelX, StationVelY: Double;
  IsOffScreen, IsNearEdge: Boolean;
begin
  if (FStatus = gsMissionFailed) or (FStatus = gsDockingSuccess) then Exit;

  DistToPlanetSq := Sqr(FCargo.Position.X - FPlanet.Position.X) + Sqr(FCargo.Position.Y - FPlanet.Position.Y);

  if DistToPlanetSq <= Sqr(FPlanet.Radius) then
  begin
    FStatus := gsMissionFailed;
    FCargo.ApplyStructuralStress(100.0);
    Exit;
  end;

  IsOffScreen := (Abs(FCargo.Position.X) >= 24300.0) or (Abs(FCargo.Position.Y) >= 17350.0);
  if IsOffScreen then
  begin
    FStatus := gsMissionFailed;
    FCargo.ApplyStructuralStress(100.0);
    Exit;
  end;

  DistToStationSq := Sqr(FCargo.Position.X - FStation.Position.X) + Sqr(FCargo.Position.Y - FStation.Position.Y);
  if DistToStationSq <= Sqr(FStation.DockingTolerance) then
  begin
    StationVelX := -FStation.AngularSpeed * FStation.OrbitRadius * Sin(FStation.OrbitAngle);
    StationVelY := FStation.AngularSpeed * FStation.OrbitRadius * Cos(FStation.OrbitAngle);

    RelVelocitySq := Sqr(FCargo.Velocity.X - StationVelX) + Sqr(FCargo.Velocity.Y - StationVelY);

    if RelVelocitySq <= Sqr(FStation.MaxSafeVelocity) then
      FStatus := gsDockingSuccess
    else
    begin
      FStatus := gsMissionFailed;
      FCargo.ApplyStructuralStress(100.0);
    end;
  end;

  IsNearEdge := (Abs(FCargo.Position.X) > 22300.0) or (Abs(FCargo.Position.Y) > 15350.0);

  if (DistToPlanetSq <= Sqr(FPlanet.Radius + 1500.0)) or IsNearEdge then
  begin
    if FStatus = gsNominal then FStatus := gsCritical;
  end
  else
  begin
    if FStatus = gsCritical then FStatus := gsNominal;
  end;
end;

procedure TGameState.Update(DeltaTime: Double);
begin
  if (FStatus = gsMissionFailed) or (FStatus = gsDockingSuccess) then Exit;

  FTimeElapsed := FTimeElapsed + DeltaTime;

  UpdateStationPosition(DeltaTime);

  CalculateGravityForce(DeltaTime);
  FCargo.UpdatePhysics(DeltaTime);

  UpdateCapsulePhysics(DeltaTime);
  CheckCapsuleCollection;

  CalculateTelemetry;
  EvaluateWinLossConditions;

  if FCargo.Battery > 0.0 then
  begin
    FCargo.Battery := FCargo.Battery - (0.5 * DeltaTime);
    if FCargo.Battery <= 0.0 then
    begin
      FCargo.Battery := 0.0;
      FStatus := gsMissionFailed;
    end;
  end;

  if FStatus = gsCritical then
  begin
    if FCargo.Integrity > 0.0 then
    begin
      FCargo.Integrity := FCargo.Integrity - (5.0 * DeltaTime);
      if FCargo.Integrity <= 0.0 then
      begin
        FCargo.Integrity := 0.0;
        FStatus := gsMissionFailed;
      end;
    end;
  end;
end;

end.
