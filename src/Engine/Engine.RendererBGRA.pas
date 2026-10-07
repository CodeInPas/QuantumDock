unit Engine.RendererBGRA;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Types, Math,
  BGRABitmap, BGRABitmapTypes,
  Game.State, Game.CargoEntity;

type
  // --- RECORD UNTUK EFEK BINTANG 3D ---
  TStar = record
    X, Y: Double;
    Z: Double; // Menentukan kecepatan gerak (Parallax/Kedalaman)
    Size: Double;
    Color: TBGRAPixel;
  end;

  { TRendererBGRA: Menangani seluruh visualisasi orbital map menggunakan BGRABitmap. }
  TRendererBGRA = class
  private
    FBuffer: TBGRABitmap;
    FStaticCache: TBGRABitmap;
    FScanlineCache: TBGRABitmap;
    FGameState: TGameState;

    FWidth: Integer;
    FHeight: Integer;
    FScale: Double;
    FCenterX, FCenterY: Double;

    FNeedsCacheUpdate: Boolean;

    FPredictPower: Double;
    FPredictAngleDeg: Double;
    FPredictDuration: Double;

    FStars: array[0..200] of TStar; // Array penyimpan 200 bintang

    procedure InitStars;
    procedure UpdateAndDrawStars;
    procedure DrawSun;

    procedure UpdateStaticCache;
    procedure UpdateScanlines;
    procedure ApplyGlitchEffect;

    function WorldToScreen(const AWorldPos: TVector2D): TPointF;

    procedure DrawPlanet;
    procedure DrawStation;
    procedure DrawCargo;
    procedure DrawCapsule;
    procedure DrawPredictedOrbit;
    procedure DrawExplosion;
    procedure DrawGameOverText;
  public
    constructor Create(AGameState: TGameState);
    destructor Destroy; override;

    procedure SetPredictedManeuver(APower, AAngle, ADuration: Double);

    procedure Resize(AWidth, AHeight: Integer);
    procedure Render(ACanvas: TCanvas);
  end;

implementation

{ TRendererBGRA }

constructor TRendererBGRA.Create(AGameState: TGameState);
begin
  inherited Create;
  FGameState := AGameState;
  FBuffer := nil;
  FStaticCache := nil;
  FScanlineCache := nil;
  FWidth := 0;
  FHeight := 0;
  FScale := 0.02;
  FNeedsCacheUpdate := True;

  FPredictPower := 0;
  FPredictAngleDeg := 0;
  FPredictDuration := 0;

  Randomize;
  InitStars; // Inisialisasi posisi awal bintang
end;

destructor TRendererBGRA.Destroy;
begin
  if Assigned(FBuffer) then FBuffer.Free;
  if Assigned(FStaticCache) then FStaticCache.Free;
  if Assigned(FScanlineCache) then FScanlineCache.Free;
  inherited Destroy;
end;

// --- INISIALISASI BINTANG ---
procedure TRendererBGRA.InitStars;
var
  I: Integer;
begin
  for I := Low(FStars) to High(FStars) do
  begin
    FStars[I].X := Random(2500);
    FStars[I].Y := Random(1500);
    FStars[I].Z := Random * 2.5 + 0.5; // Z menentukan kedalaman
    FStars[I].Size := Random * 1.5 + 0.5;
    // Warna bintang bervariasi dari putih ke kebiruan
    FStars[I].Color := BGRA(200 + Random(55), 200 + Random(55), 255, 100 + Random(155));
  end;
end;

// --- EFEK PARALLAX BINTANG ---
procedure TRendererBGRA.UpdateAndDrawStars;
var
  I: Integer;
  DriftSpeed: Double;
begin
  for I := Low(FStars) to High(FStars) do
  begin
    // Bintang yang lebih "dekat" (Z besar) bergerak lebih cepat
    DriftSpeed := FStars[I].Z * 0.15;
    FStars[I].X := FStars[I].X - DriftSpeed;

    // Jika keluar dari layar kiri, munculkan lagi di kanan
    if FStars[I].X < 0 then
    begin
      FStars[I].X := FWidth;
      FStars[I].Y := Random(Max(100, FHeight));
    end;

    FBuffer.FillEllipseAntialias(FStars[I].X, FStars[I].Y, FStars[I].Size, FStars[I].Size, FStars[I].Color);
  end;
end;

// --- GAMBAR MATAHARI ---
procedure TRendererBGRA.DrawSun;
var
  I: Integer;
  SunX, SunY: Double;
begin
  // Posisi matahari di sudut kanan atas
  SunX := FWidth * 0.85;
  SunY := FHeight * 0.15;

  if (SunX <= 0) or (SunY <= 0) then Exit;

  // Efek Corona / Cahaya Pijar (berlapis-lapis transparan)
  for I := 12 downto 1 do
  begin
    FBuffer.FillEllipseAntialias(SunX, SunY, I * 15, I * 15, BGRA(255, 120, 0, 8));
  end;

  // Inti Matahari
  FBuffer.FillEllipseAntialias(SunX, SunY, 30, 30, BGRA(255, 240, 200, 255));
  FBuffer.EllipseAntialias(SunX, SunY, 30, 30, BGRA(255, 255, 255, 200), 2.0);
end;

procedure TRendererBGRA.SetPredictedManeuver(APower, AAngle, ADuration: Double);
begin
  FPredictPower := APower;
  FPredictAngleDeg := AAngle;
  FPredictDuration := ADuration;
end;

procedure TRendererBGRA.Resize(AWidth, AHeight: Integer);
begin
  if (FWidth = AWidth) and (FHeight = AHeight) then Exit;

  FWidth := AWidth;
  FHeight := AHeight;
  FCenterX := FWidth / 2.0;
  FCenterY := FHeight / 2.0;

  if Assigned(FBuffer) then FBuffer.Free;
  FBuffer := TBGRABitmap.Create(FWidth, FHeight);

  if Assigned(FStaticCache) then FStaticCache.Free;
  FStaticCache := TBGRABitmap.Create(FWidth, FHeight);

  if Assigned(FScanlineCache) then FScanlineCache.Free;
  FScanlineCache := TBGRABitmap.Create(FWidth, FHeight);

  FNeedsCacheUpdate := True;
end;

function TRendererBGRA.WorldToScreen(const AWorldPos: TVector2D): TPointF;
begin
  Result.X := FCenterX + (AWorldPos.X * FScale);
  Result.Y := FCenterY - (AWorldPos.Y * FScale);
end;

procedure TRendererBGRA.UpdateScanlines;
var
  Y: Integer;
begin
  if not Assigned(FScanlineCache) then Exit;
  FScanlineCache.Fill(BGRA(0, 0, 0, 0));

  Y := 0;
  while Y < FHeight do
  begin
    FScanlineCache.DrawLineAntialias(0, Y, FWidth, Y, BGRA(0, 0, 0, 70), 1.0);
    Inc(Y, 3);
  end;
end;

procedure TRendererBGRA.UpdateStaticCache;
var
  X, Y: Integer;
  GridSize: Integer;
  TxtColor: TBGRAPixel;
  BottomRightText: String;
  TextW: Integer;
begin
  if not Assigned(FStaticCache) then Exit;

  // DIUBAH: Grid sekarang digambar pada latar belakang TRANSPARAN, bukan solid.
  FStaticCache.Fill(BGRA(0, 0, 0, 0));

  GridSize := 40;

  X := 0;
  while X < FWidth do
  begin
    FStaticCache.DrawLineAntialias(X, 0, X, FHeight, BGRA(0, 200, 255, 15), 1.0);
    Inc(X, GridSize);
  end;

  Y := 0;
  while Y < FHeight do
  begin
    FStaticCache.DrawLineAntialias(0, Y, FWidth, Y, BGRA(0, 200, 255, 15), 1.0);
    Inc(Y, GridSize);
  end;

  FStaticCache.DrawLineAntialias(FCenterX - 20, FCenterY, FCenterX + 20, FCenterY, BGRA(0, 255, 255, 60), 1.0);
  FStaticCache.DrawLineAntialias(FCenterX, FCenterY - 20, FCenterX, FCenterY + 20, BGRA(0, 255, 255, 60), 1.0);
  FStaticCache.EllipseAntialias(FCenterX, FCenterY, 15, 15, BGRA(0, 255, 255, 30), 1.0);

  FStaticCache.FontName := 'Terminal';
  FStaticCache.FontHeight := 12;
  FStaticCache.FontAntialias := True;
  TxtColor := BGRA(0, 255, 0, 255);

  FStaticCache.TextOut(10, 10, 'SEC: 1A-ALPHA | X: -420, Y: +280', TxtColor);

  BottomRightText := 'SEC: 9B-OMEGA | X: +420, Y: -280';
  TextW := FStaticCache.TextSize(BottomRightText).cx;
  FStaticCache.TextOut(FWidth - TextW - 10, FHeight - 25, BottomRightText, TxtColor);

  FNeedsCacheUpdate := False;
end;

procedure TRendererBGRA.DrawPlanet;
var
  ScreenPos: TPointF;
  ScreenRadius: Double;
begin
  ScreenPos := WorldToScreen(FGameState.Planet.Position);
  ScreenRadius := FGameState.Planet.Radius * FScale;

  FBuffer.EllipseAntialias(ScreenPos.X, ScreenPos.Y, ScreenRadius + 10, ScreenRadius + 10,
                           BGRA(0, 255, 255, 50), 2.0, BGRA(0, 255, 255, 20));

  FBuffer.FillEllipseAntialias(ScreenPos.X, ScreenPos.Y, ScreenRadius, ScreenRadius, BGRA(20, 50, 100, 255));
  FBuffer.EllipseAntialias(ScreenPos.X, ScreenPos.Y, ScreenRadius, ScreenRadius, BGRA(0, 200, 255, 255), 1.5);
end;

procedure TRendererBGRA.DrawStation;
var
  ScreenPos: TPointF;
  OrbitScreenRadius: Double;
begin
  OrbitScreenRadius := FGameState.Station.OrbitRadius * FScale;
  FBuffer.EllipseAntialias(FCenterX, FCenterY, OrbitScreenRadius, OrbitScreenRadius, BGRA(255, 150, 0, 80), 1.0);

  ScreenPos := WorldToScreen(FGameState.Station.Position);
  FBuffer.FillEllipseAntialias(ScreenPos.X, ScreenPos.Y, 5, 5, BGRA(255, 191, 0, 255));
  FBuffer.EllipseAntialias(ScreenPos.X, ScreenPos.Y, 8, 8, BGRA(255, 191, 0, 150), 1.5);
end;

procedure TRendererBGRA.DrawCapsule;
var
  ScreenPos: TPointF;
  I: Integer;
  SimPos, SimVel: TVector2D;
  DistSq, ForceG, AccelG, AngleRadian, DeltaT: Double;
  OrbitScreenPos: TPointF;
begin
  if not FGameState.FuelCapsule.Active then Exit;

  SimPos := FGameState.FuelCapsule.Position;
  SimVel := FGameState.FuelCapsule.Velocity;
  DeltaT := 2.0;

  for I := 1 to 200 do
  begin
    DistSq := Sqr(FGameState.Planet.Position.X - SimPos.X) + Sqr(FGameState.Planet.Position.Y - SimPos.Y);
    if DistSq > 0.1 then
    begin
      ForceG := FGameState.GravitationalConstant * FGameState.Planet.Mass / DistSq;
      AccelG := ForceG;
      AngleRadian := ArcTan2(FGameState.Planet.Position.Y - SimPos.Y, FGameState.Planet.Position.X - SimPos.X);

      SimVel.X := SimVel.X + (AccelG * Cos(AngleRadian) * DeltaT);
      SimVel.Y := SimVel.Y + (AccelG * Sin(AngleRadian) * DeltaT);
    end;

    SimPos.X := SimPos.X + (SimVel.X * DeltaT);
    SimPos.Y := SimPos.Y + (SimVel.Y * DeltaT);

    OrbitScreenPos := WorldToScreen(SimPos);

    if (I mod 4 = 0) then
      FBuffer.SetPixel(Round(OrbitScreenPos.X), Round(OrbitScreenPos.Y), BGRA(0, 150, 255, 150));
  end;

  ScreenPos := WorldToScreen(FGameState.FuelCapsule.Position);

  FBuffer.DrawLineAntialias(ScreenPos.X, ScreenPos.Y - 5, ScreenPos.X + 5, ScreenPos.Y, BGRA(50, 200, 255, 255), 1.5);
  FBuffer.DrawLineAntialias(ScreenPos.X + 5, ScreenPos.Y, ScreenPos.X, ScreenPos.Y + 5, BGRA(50, 200, 255, 255), 1.5);
  FBuffer.DrawLineAntialias(ScreenPos.X, ScreenPos.Y + 5, ScreenPos.X - 5, ScreenPos.Y, BGRA(50, 200, 255, 255), 1.5);
  FBuffer.DrawLineAntialias(ScreenPos.X - 5, ScreenPos.Y, ScreenPos.X, ScreenPos.Y - 5, BGRA(50, 200, 255, 255), 1.5);

  FBuffer.FillRect(Round(ScreenPos.X) - 2, Round(ScreenPos.Y) - 2, Round(ScreenPos.X) + 2, Round(ScreenPos.Y) + 2, BGRA(50, 200, 255, 200), dmSet);
end;

procedure TRendererBGRA.DrawCargo;
var
  ScreenPos, EdgePos: TPointF;
  HeadingAngle, ThrustVectorX, ThrustVectorY, AngleToCenter: Double;
  P1, P2, P3: TPointF;
  Size, MaxRadius: Double;
  IsOffScreen: Boolean;
begin
  ScreenPos := WorldToScreen(FGameState.Cargo.Position);
  Size := 6.0;

  IsOffScreen := (ScreenPos.X < 10) or (ScreenPos.X > FWidth - 10) or
                 (ScreenPos.Y < 10) or (ScreenPos.Y > FHeight - 10);

  if IsOffScreen then
  begin
    AngleToCenter := ArcTan2(ScreenPos.Y - FCenterY, ScreenPos.X - FCenterX);
    MaxRadius := Min(FCenterX, FCenterY) - 15;

    EdgePos.X := FCenterX + (Cos(AngleToCenter) * MaxRadius);
    EdgePos.Y := FCenterY + (Sin(AngleToCenter) * MaxRadius);

    P1.X := EdgePos.X + (8.0 * Cos(AngleToCenter));
    P1.Y := EdgePos.Y + (8.0 * Sin(AngleToCenter));

    P2.X := EdgePos.X + (6.0 * Cos(AngleToCenter + 2.5));
    P2.Y := EdgePos.Y + (6.0 * Sin(AngleToCenter + 2.5));

    P3.X := EdgePos.X + (6.0 * Cos(AngleToCenter - 2.5));
    P3.Y := EdgePos.Y + (6.0 * Sin(AngleToCenter - 2.5));

    FBuffer.DrawPolygonAntialias([P1, P2, P3], BGRA(255, 50, 50, 255), 1.5, BGRA(255, 0, 0, 200));
    FBuffer.DrawLineAntialias(FCenterX, FCenterY, EdgePos.X, EdgePos.Y, BGRA(255, 50, 50, 60), 1.0);
  end
  else
  begin
    if (FGameState.Cargo.Velocity.X <> 0) or (FGameState.Cargo.Velocity.Y <> 0) then
      HeadingAngle := ArcTan2(FGameState.Cargo.Velocity.Y, FGameState.Cargo.Velocity.X)
    else
      HeadingAngle := 0;

    P1.X := ScreenPos.X + (Size * Cos(HeadingAngle));
    P1.Y := ScreenPos.Y - (Size * Sin(HeadingAngle));

    P2.X := ScreenPos.X + (Size * Cos(HeadingAngle + 2.5));
    P2.Y := ScreenPos.Y - (Size * Sin(HeadingAngle + 2.5));

    P3.X := ScreenPos.X + (Size * Cos(HeadingAngle - 2.5));
    P3.Y := ScreenPos.Y - (Size * Sin(HeadingAngle - 2.5));

    if FGameState.Cargo.IsThrusting then
    begin
      ThrustVectorX := ScreenPos.X - (15.0 * Cos(FGameState.Cargo.ThrustAngle));
      ThrustVectorY := ScreenPos.Y + (15.0 * Sin(FGameState.Cargo.ThrustAngle));
      FBuffer.DrawLineAntialias(ScreenPos.X, ScreenPos.Y, ThrustVectorX, ThrustVectorY, BGRA(255, 50, 50, 200), 2.0);
    end;

    FBuffer.DrawPolygonAntialias([P1, P2, P3], BGRA(0, 255, 255, 255), 1.5, BGRA(0, 150, 255, 150));
  end;
end;

procedure TRendererBGRA.DrawPredictedOrbit;
var
  I, ProjectedSeconds: Integer;
  SimPos, SimVel: TVector2D;
  ScreenPos: TPointF;
  DeltaT, AccelG, ForceG, DistSq, AngleRadian: Double;
  PredThrustAngle, BurnAccel, BurnForce: Double;
  TotalDurationSim: Double;
begin
  SimPos := FGameState.Cargo.Position;
  SimVel := FGameState.Cargo.Velocity;
  DeltaT := 1.0;
  TotalDurationSim := 0.0;
  ProjectedSeconds := 150;

  PredThrustAngle := FPredictAngleDeg * (PI / 180.0);

  BurnForce := (FPredictPower / 100.0) * 1500.0;
  BurnAccel := BurnForce / FGameState.Cargo.Mass;

  for I := 1 to ProjectedSeconds do
  begin
    DistSq := Sqr(FGameState.Planet.Position.X - SimPos.X) + Sqr(FGameState.Planet.Position.Y - SimPos.Y);
    if DistSq > 0.1 then
    begin
      ForceG := FGameState.GravitationalConstant * (FGameState.Planet.Mass * FGameState.Cargo.Mass) / DistSq;
      AccelG := ForceG / FGameState.Cargo.Mass;
      AngleRadian := ArcTan2(FGameState.Planet.Position.Y - SimPos.Y, FGameState.Planet.Position.X - SimPos.X);

      SimVel.X := SimVel.X + (AccelG * Cos(AngleRadian) * DeltaT);
      SimVel.Y := SimVel.Y + (AccelG * Sin(AngleRadian) * DeltaT);
    end;

    if TotalDurationSim < FPredictDuration then
    begin
      SimVel.X := SimVel.X + (BurnAccel * Cos(PredThrustAngle) * DeltaT);
      SimVel.Y := SimVel.Y + (BurnAccel * Sin(PredThrustAngle) * DeltaT);
    end;

    SimPos.X := SimPos.X + (SimVel.X * DeltaT);
    SimPos.Y := SimPos.Y + (SimVel.Y * DeltaT);
    TotalDurationSim := TotalDurationSim + DeltaT;

    ScreenPos := WorldToScreen(SimPos);

    if (I mod 3 = 0) then
    begin
      if TotalDurationSim < FPredictDuration then
        FBuffer.SetPixel(Round(ScreenPos.X), Round(ScreenPos.Y), BGRA(255, 255, 0, 200))
      else
        FBuffer.SetPixel(Round(ScreenPos.X), Round(ScreenPos.Y), BGRA(0, 255, 100, 120));
    end;
  end;
end;

procedure TRendererBGRA.DrawExplosion;
var
  ScreenPos: TPointF;
  I: Integer;
  Rad: Double;
begin
  ScreenPos := WorldToScreen(FGameState.Cargo.Position);

  for I := 6 downto 1 do
  begin
    Rad := I * 9.0 + Random(6);
    if I mod 2 = 0 then
      FBuffer.FillEllipseAntialias(ScreenPos.X, ScreenPos.Y, Rad, Rad, BGRA(255, 100, 0, 180))
    else
      FBuffer.FillEllipseAntialias(ScreenPos.X, ScreenPos.Y, Rad, Rad, BGRA(255, 20, 0, 180));
  end;

  FBuffer.FillEllipseAntialias(ScreenPos.X, ScreenPos.Y, 12, 12, BGRA(255, 255, 100, 255));
end;

procedure TRendererBGRA.DrawGameOverText;
var
  TxtMain, TxtSub: String;
  TextSizeMain, TextSizeSub: TSize;
  X, Y: Integer;
begin
  TxtMain := 'GAME OVER';
  TxtSub := 'CRITICAL HULL BREACH';

  FBuffer.FontName := 'Consolas';
  FBuffer.FontHeight := 72;
  FBuffer.FontStyle := [fsBold];

  TextSizeMain := FBuffer.TextSize(TxtMain);
  X := Round(FCenterX) - (TextSizeMain.cx div 2);
  Y := Round(FCenterY) - (TextSizeMain.cy div 2) - 20;

  FBuffer.TextOut(X + 4, Y + 4, TxtMain, BGRA(200, 0, 0, 150));
  FBuffer.TextOut(X - 2, Y - 2, TxtMain, BGRA(200, 0, 0, 150));

  FBuffer.TextOut(X, Y, TxtMain, BGRA(255, 255, 255, 255));

  FBuffer.FontHeight := 24;
  TextSizeSub := FBuffer.TextSize(TxtSub);
  X := Round(FCenterX) - (TextSizeSub.cx div 2);
  Y := Y + TextSizeMain.cy + 10;

  FBuffer.TextOut(X, Y, TxtSub, BGRA(255, 50, 50, 255));
end;

procedure TRendererBGRA.ApplyGlitchEffect;
var
  I, BandY, BandHeight, ShiftX: Integer;
  TempBand: TBGRABitmap;
  GlitchChance: Integer;
begin
  if FGameState.Status = gsCritical then
    GlitchChance := 35
  else if FGameState.Status = gsMissionFailed then
    GlitchChance := 60
  else
    GlitchChance := 3;

  if Random(100) >= GlitchChance then Exit;

  for I := 0 to Random(4) + 2 do
  begin
    BandY := Random(FHeight - 20);
    BandHeight := Random(25) + 5;
    ShiftX := Random(41) - 20;

    if BandY + BandHeight > FHeight then
      BandHeight := FHeight - BandY;

    TempBand := FBuffer.GetPart(Rect(0, BandY, FWidth, BandY + BandHeight)) as TBGRABitmap;
    FBuffer.PutImage(ShiftX, BandY, TempBand, dmSet);
    TempBand.Free;
  end;

  for I := 0 to Random(5) do
  begin
    BandY := Random(FHeight);
    FBuffer.DrawLineAntialias(0, BandY, FWidth, BandY,
      BGRA(255, 100, 100, Random(150) + 50), 1.5);
  end;
end;

procedure TRendererBGRA.Render(ACanvas: TCanvas);
begin
  if (FWidth <= 0) or (FHeight <= 0) or not Assigned(FBuffer) then Exit;

  if FNeedsCacheUpdate then
  begin
    UpdateStaticCache;
    UpdateScanlines;
  end;

  // 1. Gambar latar belakang luar angkasa yang gelap
  FBuffer.Fill(BGRA(2, 5, 12, 255));

  // 2. Render bintang 3D parallax & Matahari di background
  UpdateAndDrawStars;
  DrawSun;

  // 3. Timpa dengan grid radar taktis (transparan)
  FBuffer.PutImage(0, 0, FStaticCache, dmDrawWithTransparency);

  // 4. Render elemen fisika utama
  if Assigned(FGameState) then
  begin
    DrawPlanet;
    DrawStation;
    DrawCapsule;

    if FGameState.Status = gsMissionFailed then
    begin
      DrawExplosion;
      DrawGameOverText;
    end
    else
    begin
      DrawPredictedOrbit;
      DrawCargo;

      if FGameState.Status = gsDockingSuccess then
      begin
        FBuffer.FontName := 'Consolas';
        FBuffer.FontHeight := 52;
        FBuffer.FontStyle := [fsBold];
        FBuffer.TextOut(Round(FCenterX) - 230, Round(FCenterY) - 50, 'MISSION SUCCESS', BGRA(50, 255, 50, 255));
      end;
    end;
  end;

  ApplyGlitchEffect;

  if Assigned(FScanlineCache) then
    FBuffer.PutImage(0, 0, FScanlineCache, dmDrawWithTransparency);

  FBuffer.Draw(ACanvas, 0, 0, False);
end;

end.
