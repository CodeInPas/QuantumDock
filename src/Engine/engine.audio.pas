unit Engine.Audio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BASS; // Pastikan unit BASS dan file bass.dll tersedia di direktori proyek

type
  { TAudioEngine: Mengelola pemutaran efek suara latar, alarm, dan pendorong kapal }
  TAudioEngine = class
  private
    FInitialized: Boolean;
    FChannelAmbient: HSTREAM;
    FChannelEngine: HSTREAM;
    FSampleAlarm: HSAMPLE;
    FChannelAlarm: HCHANNEL;

    procedure LoadAssets;
  public
    constructor Create;
    destructor Destroy; override;

    procedure PlayAmbient;
    procedure SetEngineThrust(ThrustValue: Double); // Skala 0.0 hingga 100.0
    procedure PlayAlarm(Enable: Boolean);
  end;

var
  AudioEngine: TAudioEngine;

implementation

{ TAudioEngine }

constructor TAudioEngine.Create;
begin
  inherited Create;
  // Inisialisasi device BASS (-1 = default device, 44100Hz)
  FInitialized := BASS_Init(-1, 44100, 0, 0, nil);

  if FInitialized then
  begin
    BASS_SetConfig(BASS_CONFIG_GVOL_STREAM, 10000); // Set volume global maksimum
    LoadAssets;
  end;
end;

destructor TAudioEngine.Destroy;
begin
  if FInitialized then
  begin
    BASS_SampleFree(FSampleAlarm);
    BASS_StreamFree(FChannelAmbient);
    BASS_StreamFree(FChannelEngine);
    BASS_Free;
  end;
  inherited Destroy;
end;

procedure TAudioEngine.LoadAssets;
begin
  // Pastikan file audio diletakkan di dalam folder 'assets' berdekatan dengan file executable
  // Flag BASS_SAMPLE_LOOP digunakan agar suara berputar terus-menerus tanpa putus

  FChannelAmbient := BASS_StreamCreateFile(False, PChar('assets/sfx/ambient_space.wav'), 0, 0, BASS_SAMPLE_LOOP);
  FChannelEngine := BASS_StreamCreateFile(False, PChar('assets/sfx/engine_rumble.wav'), 0, 0, BASS_SAMPLE_LOOP);

  // Memuat alarm sebagai Sample untuk respon pemutaran instan
  FSampleAlarm := BASS_SampleLoad(False, PChar('assets/sfx/alarm_critical.wav'), 0, 0, 3, BASS_SAMPLE_LOOP);

  if FSampleAlarm <> 0 then
    FChannelAlarm := BASS_SampleGetChannel(FSampleAlarm, False);

  // Jalankan mesin dalam kondisi siaga (volume 0.0) agar siap dinaikkan saat slider digeser
  if FChannelEngine <> 0 then
  begin
    BASS_ChannelSetAttribute(FChannelEngine, BASS_ATTRIB_VOL, 0.0);
    BASS_ChannelPlay(FChannelEngine, False);
  end;
end;

procedure TAudioEngine.PlayAmbient;
begin
  if FInitialized and (FChannelAmbient <> 0) then
  begin
    BASS_ChannelSetAttribute(FChannelAmbient, BASS_ATTRIB_VOL, 0.35); // Volume latar 35%
    BASS_ChannelPlay(FChannelAmbient, False);
  end;
end;

procedure TAudioEngine.SetEngineThrust(ThrustValue: Double);
var
  TargetVol: Single;
begin
  if not FInitialized or (FChannelEngine = 0) then Exit;

  // Normalisasi skala Thrust (0 - 100) menjadi skala Volume BASS (0.0 - 1.0)
  TargetVol := ThrustValue / 100.0;

  BASS_ChannelSetAttribute(FChannelEngine, BASS_ATTRIB_VOL, TargetVol);

  // Modulasi pitch: Frekuensi naik seiring bertambahnya daya pendorong (efek putaran turbin)
  BASS_ChannelSetAttribute(FChannelEngine, BASS_ATTRIB_FREQ, 44100 + (TargetVol * 12000));
end;

procedure TAudioEngine.PlayAlarm(Enable: Boolean);
begin
  if not FInitialized or (FChannelAlarm = 0) then Exit;

  if Enable then
  begin
    if BASS_ChannelIsActive(FChannelAlarm) <> BASS_ACTIVE_PLAYING then
    begin
      BASS_ChannelSetAttribute(FChannelAlarm, BASS_ATTRIB_VOL, 0.8);
      BASS_ChannelPlay(FChannelAlarm, False);
    end;
  end
  else
  begin
    BASS_ChannelStop(FChannelAlarm);
  end;
end;

end.
