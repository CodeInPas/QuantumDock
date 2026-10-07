program QuantumDockOS;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Forms,
  MainForm, UnitAbout, BASS;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Title:='QuantumDock';
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.CreateForm(TFormAbout, FormAbout);
  Application.Run;
end.

