unit Game.CargoEntity;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  { Menggunakan Double (64-bit float) sangat krusial untuk presisi kalkulasi
    fisika orbital dan mencegah micro-stuttering/drift pada jarak jauh. }
  TVector2D = record
    X, Y: Double;
  end;

  { TCargoEntity: Model data utama untuk modul kargo yang bermanuver di luar angkasa.
    Tidak mengandung logika rendering (Decoupled Architecture), murni state dan math. }
  TCargoEntity = class
  private
    FPosition: TVector2D;
    FVelocity: TVector2D;

    // Properties Fisika & Telemetri
    FMass: Double;              // Satuan: Metrik Ton (T)
    FFuel: Double;              // Satuan: Persentase (0.0 - 100.0)
    FBattery: Double;           // Satuan: Persentase (0.0 - 100.0)
    FIntegrity: Double;         // Satuan: Persentase (0.0 - 100.0)

    // Status Manuver Aktif
    FIsThrusting: Boolean;
    FThrustPower: Double;       // Persentase dorongan (0.0 - 100.0)
    FThrustAngle: Double;       // Sudut dorongan dalam Radian untuk unit Math (Cos/Sin)

    // Parameter Engine Kargo
    FMaxThrustForce: Double;    // Gaya dorong maksimal mesin (Newton / arbitrary unit)
    FFuelBurnRate: Double;      // Laju konsumsi bahan bakar per detik pada 100% thrust

  public
    constructor Create;

    { Mengatur vektor dorongan mesin. AngleDegrees menggunakan format UI (0-360) }
    procedure SetManeuverNode(PowerPercent: Double; AngleDegrees: Double);
    procedure ExecuteBurn(Enable: Boolean);

    { Dipanggil oleh Physics Thread secara kontinu. Mengkalkulasi akselerasi
      dari thrust dan memperbarui posisi (Semi-Implicit Euler Integration) }
    procedure UpdatePhysics(DeltaTime: Double);

    { Menerima benturan mekanik atau G-Force berlebih }
    procedure ApplyStructuralStress(DamageForce: Double);

    // Akses Properti
    property Position: TVector2D read FPosition write FPosition;
    property Velocity: TVector2D read FVelocity write FVelocity;
    property Mass: Double read FMass write FMass;
    property Fuel: Double read FFuel write FFuel;
    property Battery: Double read FBattery write FBattery;
    property Integrity: Double read FIntegrity write FIntegrity;

    property IsThrusting: Boolean read FIsThrusting;
    property ThrustPower: Double read FThrustPower;
    property ThrustAngle: Double read FThrustAngle;
  end;

implementation

{ TCargoEntity }

constructor TCargoEntity.Create;
begin
  inherited Create;
  // Inisialisasi nilai default sesuai spesifikasi GDD (Cargo M4)
  FMass := 18.5;
  FFuel := 67.4;
  FBattery := 91.0;
  FIntegrity := 100.0;

  FPosition.X := 0.0;
  FPosition.Y := 0.0;
  FVelocity.X := 0.0;
  FVelocity.Y := 0.0;

  FIsThrusting := False;
  FThrustPower := 0.0;
  FThrustAngle := 0.0;

  FMaxThrustForce := 500.0; // Konstanta force dasar mesin
  FFuelBurnRate := 2.5;     // 2.5% fuel per detik pada 100% power
end;

procedure TCargoEntity.SetManeuverNode(PowerPercent: Double; AngleDegrees: Double);
begin
  // Batasi power antara 0 dan 100 persen
  FThrustPower := Max(0.0, Min(100.0, PowerPercent));

  // Konversi derajat dari UI ke Radian untuk efisiensi kalkulasi di dalam game loop
  FThrustAngle := DegToRad(AngleDegrees);
end;

procedure TCargoEntity.ExecuteBurn(Enable: Boolean);
begin
  // Mesin hanya bisa menyala jika bahan bakar dan integritas modul masih ada
  FIsThrusting := Enable and (FFuel > 0.0) and (FIntegrity > 0.0);
end;

procedure TCargoEntity.UpdatePhysics(DeltaTime: Double);
var
  AccelX, AccelY: Double;
  CurrentThrustForce: Double;
  FuelConsumed: Double;
begin
  AccelX := 0.0;
  AccelY := 0.0;

  // 1. Kalkulasi Vektor Akselerasi dari Mesin (Thrust)
  if FIsThrusting and (FFuel > 0.0) then
  begin
    // Force = MaxForce * (Power / 100)
    CurrentThrustForce := FMaxThrustForce * (FThrustPower / 100.0);

    // Hukum Newton II: A = F / m
    // Menggunakan Cos untuk sumbu X dan Sin untuk sumbu Y berdasarkan sudut Radian
    AccelX := (CurrentThrustForce * Cos(FThrustAngle)) / FMass;

    // Catatan: Pada koordinat layar (Cartesian yang dibalik), sumbu Y seringkali negatif ke atas.
    // Di level fisika (model), gunakan Cartesian standar. Konversi dilakukan di Engine.RendererBGRA.
    AccelY := (CurrentThrustForce * Sin(FThrustAngle)) / FMass;

    // 2. Konsumsi Bahan Bakar
    FuelConsumed := FFuelBurnRate * (FThrustPower / 100.0) * DeltaTime;
    FFuel := Max(0.0, FFuel - FuelConsumed);

    // Matikan mesin otomatis jika bahan bakar habis
    if FFuel <= 0.0 then
      FIsThrusting := False;
  end;

  // 3. Integrasi Numerik (Semi-Implicit Euler untuk akurasi lebih baik dari Explicit Euler)
  // v = v + a*dt
  FVelocity.X := FVelocity.X + (AccelX * DeltaTime);
  FVelocity.Y := FVelocity.Y + (AccelY * DeltaTime);

  // p = p + v*dt
  FPosition.X := FPosition.X + (FVelocity.X * DeltaTime);
  FPosition.Y := FPosition.Y + (FVelocity.Y * DeltaTime);
end;

procedure TCargoEntity.ApplyStructuralStress(DamageForce: Double);
begin
  if DamageForce <= 0 then Exit;

  FIntegrity := Max(0.0, FIntegrity - DamageForce);
  if FIntegrity <= 0.0 then
  begin
    // Memicu kondisi Loss (Hull Breach / Hancur) yang akan ditangkap oleh Game.State
    FIsThrusting := False;
  end;
end;

end.
