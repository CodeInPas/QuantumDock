unit Utils.ObjectPool;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, syncobjs, Generics.Collections;

type
  { TObjectPool: Thread-safe generic object pool
    Tujuan: Mencegah memory fragmentation dan CPU spike akibat alokasi memori dinamis
    berulang saat game loop 60 FPS (terutama untuk buffer TBGRABitmap atau TPointF node). }

  generic TObjectPool<T: class> = class
  public type
    TFactoryFunc = function: T of object; // Method pointer untuk instansiasi objek baru
  private
    FPool: specialize TStack<T>; // Menggunakan Stack (LIFO) untuk optimalisasi L1/L2 CPU Cache
    FLock: TCriticalSection;     // Mutex untuk keamanan Thread (Physics vs Main GUI Thread)
    FFactory: TFactoryFunc;
  public
    constructor Create(AFactory: TFactoryFunc);
    destructor Destroy; override;

    { Mengambil objek dari pool. Jika pool kosong, otomatis membuat instance baru via Factory }
    function Acquire: T;

    { Mengembalikan objek ke pool untuk digunakan kembali pada siklus render/physics berikutnya }
    procedure Release(AItem: T);

    { Membebaskan seluruh memori objek di dalam pool (dipanggil saat aplikasi ditutup) }
    procedure Clear;
  end;

implementation

{ TObjectPool }

constructor TObjectPool.Create(AFactory: TFactoryFunc);
begin
  inherited Create;
  FPool := specialize TStack<T>.Create;
  FLock := TCriticalSection.Create;
  FFactory := AFactory;
end;

destructor TObjectPool.Destroy;
begin
  Clear;
  FPool.Free;
  FLock.Free;
  inherited Destroy;
end;

function TObjectPool.Acquire: T;
begin
  FLock.Acquire;
  try
    if FPool.Count > 0 then
      Result := FPool.Pop
    else
    begin
      if Assigned(FFactory) then
        Result := FFactory()
      else
        Result := nil;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TObjectPool.Release(AItem: T);
begin
  if AItem = nil then Exit;

  FLock.Acquire;
  try
    FPool.Push(AItem);
  finally
    FLock.Release;
  end;
end;

procedure TObjectPool.Clear;
var
  Item: T;
begin
  FLock.Acquire;
  try
    while FPool.Count > 0 do
    begin
      Item := FPool.Pop;
      Item.Free;
    end;
  finally
    FLock.Release;
  end;
end;

end.

